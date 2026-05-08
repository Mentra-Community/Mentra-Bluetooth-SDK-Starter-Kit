# Android WebRTC Receiver Demo

This example proves a direct Mentra Live glasses-to-Android streaming path:

1. The app connects to Mentra Live over the partner-kit Bluetooth SDK.
2. The Android phone starts a phone-local GStreamer `whipserversrc` receiver.
3. The app sends that local WHIP URL to the glasses with `startStream`.
4. The glasses publish WebRTC directly back to the same Android phone.
5. The app renders decoded frames in the native Android UI.

No MediaMTX, Docker, web preview server, or Mac-side media receiver is used for the stream.

## Requirements

- Android Studio or command-line Android SDK/NDK tooling.
- A physical Android phone with Bluetooth and local network access enabled.
- GStreamer Android SDK installed at:

```sh
/Users/philippe/Library/Developer/GStreamer/Android.sdk
```

  This spike used the official GStreamer Android universal SDK download from `https://gstreamer.freedesktop.org/data/pkg/android/1.28.2/gstreamer-1.0-android-universal-1.28.2.tar.xz`, verified with the matching `.sha256sum`, and extracted locally under `/Users/philippe/Library/Developer/GStreamer/Android.sdk`. The SDK binary is intentionally not committed.

- Local Mentra Bluetooth SDK artifact available through the same Maven setup as `examples/android`.
- A Mentra Live device powered on and available over BLE.
- The phone and glasses on the same reachable local network.

If your GStreamer SDK is installed somewhere else, set `GSTREAMER_ROOT_ANDROID` before building:

```sh
export GSTREAMER_ROOT_ANDROID=/path/to/GStreamer/Android.sdk
```

## Run

Build the debug APK:

```sh
cd /Users/philippe/dev/Mentra-Bluetooth-SDK-Partner-Kit-ios-webrtc-receiver/examples/android-webrtc-receiver
./gradlew :app:assembleDebug
```

Install on the connected Android phone:

```sh
adb -s R5CN80W6MZA install -r app/build/outputs/apk/debug/app-debug.apk
```

Launch normally from the phone, or launch an autorun session against the lab glasses:

```sh
adb -s R5CN80W6MZA shell am start \
  -n com.mentra.examples.androidwebrtcreceiver/.MainActivity \
  --ez autorun true \
  --es target Mentra_Live_E613
```

For teardown verification, add `--el autoStopAfter <seconds>` to call the same stop path as the Stop button:

```sh
adb -s R5CN80W6MZA shell am start \
  -n com.mentra.examples.androidwebrtcreceiver/.MainActivity \
  --ez autorun true \
  --es target Mentra_Live_E613 \
  --el autoStopAfter 10
```

## App Flow

1. Tap **Scan**.
2. Select a Mentra Live device.
3. Tap **Connect**.
4. Tap **Start**.
5. Confirm the WHIP URL is shown as `http://<android-ip>:8190/whip/endpoint`.
6. Confirm the glasses privacy LED turns on.
7. Confirm the preview shows live video.
8. Tap **Stop stream and receiver** to send `stopStream` and tear down the local proxy plus GStreamer pipeline.

## Implementation Notes

- `WhipHeaderProxy.kt` listens on the advertised port, currently `8190`, and forwards to the internal GStreamer `whipserversrc` port, currently `8191`.
- The proxy normalizes WHIP `Content-Type` headers because the current GStreamer `whipserversrc` route rejects values such as `application/sdp; charset=utf-8`.
- `gstreamer_whip_receiver.c` uses `whipserversrc` constrained to H.264/Opus, inserts `h264parse` through `request-encoded-filter`, decodes H.264 with `openh264dec`, and renders raw frames through `appsink` into Compose.
- The receiver deliberately raises `openh264dec` rank and lowers AndroidMedia video decoder ranks. On the tested Note 20, the platform AVC decoder reported that only direct rendering was supported, which does not fit this spike's raw-frame `appsink` preview path.
- The app sends Bluetooth SDK stream keep-alives every 15 seconds while streaming.

## Verification Notes

The lab setup used during the spike:

- Android Note 20 adb serial `R5CN80W6MZA`.
- Mentra Live glasses adb serial `0123456789ABCDEF`.
- Mentra Live BLE target `Mentra_Live_E613`.

Useful log watchers:

```sh
adb -s R5CN80W6MZA logcat -v threadtime | rg -i "Mentra|GStreamer|GST|WHIP|webrtc|status|error"
adb -s 0123456789ABCDEF logcat -v threadtime | rg -i "WhipStreamingService|WHIP|stream_status|PeerConnection|IceConnection|error"
```

If the stream does not start or the glasses privacy LED does not turn on, inspect the ASG client logs from the glasses before assuming the Android receiver is the failing side.

## Known Limitations

- This is a spike app, not a polished reference UI.
- The default GStreamer SDK path is absolute and local-machine specific.
- The native bridge currently builds only `arm64-v8a`.
- The receiver is constrained to H.264/Opus.
- The preview is downscaled to `480x270` in the pipeline and copied through `appsink`, which is simple and stable for this demo but not the most efficient renderer.
