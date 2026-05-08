# iOS WebRTC Receiver Demo

This example proves a direct Mentra Live glasses-to-iPhone streaming path:

1. The app connects to Mentra Live over the partner-kit Bluetooth SDK.
2. The iPhone starts a phone-local GStreamer `whipserversrc` receiver.
3. The app sends that local WHIP URL to the glasses with `startStream`.
4. The glasses publish WebRTC directly back to the same iPhone.
5. The app decodes the H.264 video with GStreamer/VideoToolbox and shows a live preview in SwiftUI.

No MediaMTX, Docker, web preview server, or Mac-side media receiver is used for the stream.

## Requirements

- Xcode with a physical iPhone selected for development.
- CocoaPods.
- GStreamer iOS SDK installed at:

```sh
/Users/philippe/Library/Developer/GStreamer/iPhone.sdk/GStreamer.framework
```

  This spike used the official GStreamer iOS SDK download from `https://gstreamer.freedesktop.org/data/pkg/ios/1.28.2/`, installed locally under `/Users/philippe/Library/Developer/GStreamer/iPhone.sdk`. The SDK binary is intentionally not committed.

- Local Mentra Bluetooth SDK source available at the same path used by the partner-kit iOS example:

```sh
/Users/philippe/dev/MentraOS-philippe-os-1178-mentra-bluetooth-sdk/mobile/modules/bluetooth-sdk/ios
```

- A Mentra Live device powered on and available over BLE.
- The iPhone and glasses on the same reachable local network.

The app includes `NSLocalNetworkUsageDescription`. On first stream start, iOS may ask for local network access; approve it or the glasses cannot reach the phone-local WHIP URL.

## Run

Install pods once:

```sh
cd /Users/philippe/dev/Mentra-Bluetooth-SDK-Partner-Kit-ios-webrtc-receiver/examples/ios-webrtc-receiver
pod install
```

Build for the connected iPhone:

```sh
xcodebuild \
  -workspace MentraExample.xcworkspace \
  -scheme MentraExample \
  -configuration Debug \
  -destination 'id=00008120-001619E102E1A01E' \
  -derivedDataPath build/DerivedData \
  DEVELOPMENT_TEAM=T5XXXL6N36 \
  CODE_SIGN_STYLE=Automatic \
  build
```

Install:

```sh
xcrun devicectl device install app \
  --device 8454AEAE-49C6-5145-89D0-590945B637DE \
  build/DerivedData/Build/Products/Debug-iphoneos/MentraWebRTCReceiver.app
```

Launch normally from the iPhone, or launch an autorun session against the lab glasses:

```sh
xcrun devicectl device process launch \
  --device 8454AEAE-49C6-5145-89D0-590945B637DE \
  --terminate-existing \
  --console \
  --environment-variables '{"GST_DEBUG":"2,webrtc-whip-signaller:5,webrtcsrc:4","GST_DEBUG_NO_COLOR":"1"}' \
  com.mentra.examples.ios-webrtc-receiver \
  --autorun --target Mentra_Live_E613
```

For teardown verification, add `--auto-stop-after <seconds>` to call the same stop path as the Stop button:

```sh
xcrun devicectl device process launch \
  --device 8454AEAE-49C6-5145-89D0-590945B637DE \
  --terminate-existing \
  --console \
  com.mentra.examples.ios-webrtc-receiver \
  --autorun --target Mentra_Live_E613 --auto-stop-after 10
```

## App Flow

1. Tap **Scan**.
2. Select a Mentra Live device.
3. Tap **Connect**.
4. Tap **Start**.
5. Confirm the WHIP URL is shown as `http://<iphone-ip>:8190/whip/endpoint`.
6. Confirm the glasses privacy LED turns on.
7. Confirm the preview shows live video.
8. Tap **Stop stream and receiver** to send `stopStream` and tear down the local proxy plus GStreamer pipeline.

## Implementation Notes

- `WhipHeaderProxy.swift` listens on the advertised port, currently `8190`, and forwards to the internal GStreamer `whipserversrc` port, currently `8191`.
- The proxy normalizes WHIP `Content-Type` headers because the current GStreamer `whipserversrc` route rejects `application/sdp; charset=utf-8`.
- `GStreamerWhipReceiver.m` uses `whipserversrc` constrained to H.264/Opus, inserts `h264parse` through `request-encoded-filter`, decodes through GStreamer/VideoToolbox, and renders frames through an `appsink` into a SwiftUI-hosted `UIView`.
- The app sends Bluetooth SDK stream keep-alives every 15 seconds while streaming.

## Verified Spike State

Verified on May 8, 2026 with:

- iPhone 15 device identifier `8454AEAE-49C6-5145-89D0-590945B637DE`.
- Mentra Live `Mentra_Live_E613`.
- Phone-local WHIP URL `http://192.168.50.124:8190/whip/endpoint`.

Observed:

- BLE connection to `Mentra_Live_E613`.
- `startStream` sent with the phone-local WHIP URL.
- GStreamer WHIP server accepted the publish.
- Glasses privacy LED turned on.
- App logs reached `status=streaming`.
- Preview rendered live frames in-app.
- Keep-alive ACKs returned from the glasses.

## Known Limitations

- This is a spike app, not a polished reference UI.
- The GStreamer framework path is absolute and local-machine specific.
- Preview rendering currently copies decoded BGRA frames through `appsink`, which is simple and stable for the demo but not the most efficient renderer.
- The preview is downscaled to `480x270` in the pipeline.
- GStreamer may log an ORC JIT warning under the iOS hardened runtime; the demo still renders without requiring JIT.
- The glasses currently publish H.264 High Profile even though the WHIP SDP negotiation advertises constrained-baseline. VideoToolbox decodes it on the tested iPhone.
