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
- GStreamer iOS SDK from the official GStreamer iOS package:

```sh
./scripts/setup-gstreamer-ios.sh
```

  The script downloads `gstreamer-1.0-devel-1.28.2-ios-universal.pkg` from `https://gstreamer.freedesktop.org/data/pkg/ios/1.28.2/`, verifies the matching `.sha256sum`, and installs the SDK at the package default location: `$HOME/Library/Developer/GStreamer/iPhone.sdk`. The SDK binary is intentionally not committed.

- Mentra Bluetooth SDK available through CocoaPods.

  By default the Podfile uses `MentraBluetoothSDK` version `0.1.0`. Override with `MENTRA_BLUETOOTH_SDK_VERSION` once published versions are available. For local SDK development, point CocoaPods at a local checkout with `MENTRA_BLUETOOTH_SDK_LOCAL_PATH=/path/to/bluetooth-sdk/ios pod install`.

- A Mentra Live device powered on and available over BLE.
- The iPhone and glasses on the same reachable local network.

The app includes `NSLocalNetworkUsageDescription`. On first stream start, iOS may ask for local network access; approve it or the glasses cannot reach the phone-local WHIP URL.

## Run

From the repo root:

```sh
cd examples/ios-webrtc-receiver
./scripts/setup-gstreamer-ios.sh
pod install
```

If the GStreamer SDK lives somewhere else, pass the build setting when building:

```sh
xcodebuild ... GSTREAMER_ROOT_IOS=/path/to/iPhone.sdk
```

Build for a connected iPhone:

```sh
DEVICE_ID=replace-with-devicectl-id
DEVELOPMENT_TEAM=replace-with-apple-team-id

xcodebuild \
  -workspace MentraExample.xcworkspace \
  -scheme MentraExample \
  -configuration Debug \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath build/DerivedData \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  CODE_SIGN_STYLE=Automatic \
  build
```

Install:

```sh
xcrun devicectl device install app \
  --device "$DEVICE_ID" \
  build/DerivedData/Build/Products/Debug-iphoneos/MentraWebRTCReceiver.app
```

Launch normally from the iPhone, or launch an autorun session against a known glasses BLE name:

```sh
GLASSES_NAME=Mentra_Live_XXXX

xcrun devicectl device process launch \
  --device "$DEVICE_ID" \
  --terminate-existing \
  --console \
  --environment-variables '{"GST_DEBUG":"2,webrtc-whip-signaller:5,webrtcsrc:4","GST_DEBUG_NO_COLOR":"1"}' \
  com.mentra.examples.ios-webrtc-receiver \
  --autorun --target "$GLASSES_NAME"
```

For teardown verification, add `--auto-stop-after <seconds>` to call the same stop path as the Stop button:

```sh
xcrun devicectl device process launch \
  --device "$DEVICE_ID" \
  --terminate-existing \
  --console \
  com.mentra.examples.ios-webrtc-receiver \
  --autorun --target "$GLASSES_NAME" --auto-stop-after 10
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
- The Xcode project defaults `GSTREAMER_ROOT_IOS` to `$HOME/Library/Developer/GStreamer/iPhone.sdk`; override it with an `xcodebuild` build setting or in Xcode if you installed the SDK elsewhere.

## Verified Spike State

Verified on May 8, 2026 with:

- A physical iPhone 15 connected over USB.
- Mentra Live `Mentra_Live_E613`.
- A phone-local WHIP URL shaped like `http://<iphone-ip>:8190/whip/endpoint`.

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
- The GStreamer SDK binary is not committed. Run the setup script, or install the official SDK yourself and set `GSTREAMER_ROOT_IOS`.
- Preview rendering currently copies decoded BGRA frames through `appsink`, which is simple and stable for the demo but not the most efficient renderer.
- The preview is downscaled to `480x270` in the pipeline.
- GStreamer may log an ORC JIT warning under the iOS hardened runtime; the demo still renders without requiring JIT.
- The glasses currently publish H.264 High Profile even though the WHIP SDP negotiation advertises constrained-baseline. VideoToolbox decodes it on the tested iPhone.
