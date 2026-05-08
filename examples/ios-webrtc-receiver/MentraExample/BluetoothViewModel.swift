import Foundation
import Darwin
import MentraBluetoothSDK

struct ReceiverEvent: Identifiable {
    let id = UUID()
    let time: String
    let tag: String
    let text: String
}

@MainActor
final class BluetoothViewModel: NSObject, ObservableObject, MentraBluetoothSDKDelegate {
    @Published private(set) var discoveredDevices: [MentraDiscoveredDevice] = []
    @Published private(set) var selectedDevice: MentraDiscoveredDevice?
    @Published private(set) var glassesValues: [String: Any] = [:]
    @Published private(set) var bluetoothStatus = "SDK ready"
    @Published private(set) var glassesStatus = "Disconnected"
    @Published private(set) var receiverRunning = false
    @Published private(set) var streamStartPending = false
    @Published private(set) var streamStarted = false
    @Published private(set) var streamId: String?
    @Published private(set) var whipURL = "Receiver not started"
    @Published private(set) var localIPAddress = BluetoothViewModel.bestLocalIPv4Address() ?? "127.0.0.1"
    @Published private(set) var videoStatus = "Waiting for WHIP publish"
    @Published private(set) var autoRunEnabled = false
    @Published private(set) var autoTargetName = "Mentra_Live_E613"
    @Published private(set) var events: [ReceiverEvent] = [
        ReceiverEvent.make(tag: "APP", text: "Ready. Scan for Mentra_Live_E613.")
    ]

    let receiver = GStreamerWhipReceiver()

    private let sdk = MentraBluetoothSDK()
    private let whipProxy = WhipHeaderProxy()
    private var activeStreamId: String?
    private var keepAliveTask: Task<Void, Never>?
    private var autoStopTask: Task<Void, Never>?
    private var teardownTask: Task<Void, Never>?
    private var autoStopAfterSeconds: TimeInterval?
    private var autoRunStarted = false
    private var autoConnectAttempted = false
    private var autoStreamAttempted = false

    var glassesConnected: Bool {
        if let state = glassesValues["connectionState"] as? String {
            return state.lowercased() == "connected"
        }
        if let connected = glassesValues["connected"] as? Bool {
            return connected
        }
        return false
    }

    override init() {
        super.init()
        sdk.delegate = self
        glassesValues = sdk.glassesStatus.values
        bluetoothStatus = summarize(sdk.bluetoothStatus.values, fallback: "Bluetooth status pending")
        glassesStatus = summarize(glassesValues, fallback: "Disconnected")
        configureAutoRun()
        receiver.onStateChanged = { [weak self] message in
            Task { @MainActor in
                self?.videoStatus = message
                self?.append(tag: "GST", text: message)
            }
        }
    }

    deinit {
        keepAliveTask?.cancel()
        autoStopTask?.cancel()
        teardownTask?.cancel()
        Task { @MainActor [sdk, receiver, whipProxy] in
            sdk.stopStream()
            whipProxy.stop()
            receiver.stop()
            sdk.invalidate()
        }
    }

    func startAutoRunIfRequested() {
        guard autoRunEnabled, !autoRunStarted else { return }
        autoRunStarted = true
        autoConnectAttempted = true
        append(tag: "AUTO", text: "Auto-run enabled for \(autoTargetName); connecting by name")
        sdk.connect(model: .mentraLive, name: autoTargetName)
    }

    func startScan() {
        discoveredDevices.removeAll()
        selectedDevice = nil
        append(tag: "BLE", text: "Scanning for Mentra Live glasses")
        sdk.startScan(model: .mentraLive)
    }

    func select(_ device: MentraDiscoveredDevice) {
        selectedDevice = device
        append(tag: "BLE", text: "Selected \(device.name)")
    }

    func isSelected(_ device: MentraDiscoveredDevice) -> Bool {
        selectedDevice?.name == device.name
    }

    func connectSelectedDevice() {
        guard let device = selectedDevice else {
            append(tag: "BLE", text: "Scan and select a device first")
            return
        }
        append(tag: "BLE", text: "Connecting to \(device.name)")
        sdk.connect(to: device)
    }

    func refreshLocalIPAddress() {
        localIPAddress = BluetoothViewModel.bestLocalIPv4Address() ?? "127.0.0.1"
        append(tag: "NET", text: "Local WHIP host \(localIPAddress)")
    }

    func startDirectStream() {
        guard glassesConnected else {
            append(tag: "STREAM", text: "Connect glasses before starting stream")
            return
        }

        teardownTask?.cancel()
        teardownTask = nil
        refreshLocalIPAddress()
        let host = localIPAddress

        do {
            let ports = try startReceiverAndProxy()
            receiverRunning = true
            whipURL = "http://\(host):\(ports.publicPort)/whip/endpoint"
            videoStatus = "WHIP server listening"

            let nextStreamId = "ios-gst-\(Int(Date().timeIntervalSince1970 * 1000))"
            activeStreamId = nextStreamId
            streamId = nextStreamId
            streamStartPending = true
            append(tag: "STREAM", text: "Receiver ready at \(whipURL); proxying to local GStreamer port \(ports.backendPort)")

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard self.receiverRunning,
                      self.streamStartPending,
                      !self.streamStarted,
                      self.activeStreamId == nextStreamId else {
                    return
                }
                self.sendStartStream(streamUrl: self.whipURL, streamId: nextStreamId)
            }
        } catch {
            whipProxy.stop()
            receiver.stop()
            receiverRunning = false
            streamStartPending = false
            streamStarted = false
            append(tag: "GST", text: "Failed to start receiver: \(error.localizedDescription)")
        }
    }

    func stopDirectStream() {
        stopKeepAlive()
        autoStopTask?.cancel()
        autoStopTask = nil
        teardownTask?.cancel()

        let shouldSendStop = streamStarted || streamStartPending || glassesConnected
        let shouldDelayLocalTeardown = receiverRunning
        if shouldSendStop {
            sdk.stopStream()
        }
        streamStartPending = false
        streamStarted = false
        activeStreamId = nil
        streamId = nil
        videoStatus = shouldDelayLocalTeardown ? "Stopping" : "Stopped"
        append(tag: "STREAM", text: shouldSendStop ? "Sent stopStream to glasses" : "Stopping local receiver")

        if shouldDelayLocalTeardown {
            teardownTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    self?.finishLocalReceiverStop()
                }
            }
        } else {
            finishLocalReceiverStop()
        }
    }

    func mentraBluetoothSDK(_: MentraBluetoothSDK, didUpdateGlassesStatus status: MentraGlassesStatusUpdate) {
        glassesValues.merge(status.values) { _, new in new }
        glassesStatus = summarize(status.values, fallback: "Glasses status updated")
        append(tag: "GLASSES", text: glassesStatus)
        startAutoStreamIfReady()
    }

    func mentraBluetoothSDK(_: MentraBluetoothSDK, didUpdateBluetoothStatus status: MentraBluetoothStatusUpdate) {
        bluetoothStatus = summarize(status.values, fallback: "Bluetooth status updated")
        append(tag: "BLE", text: bluetoothStatus)
    }

    func mentraBluetoothSDK(_: MentraBluetoothSDK, didDiscover device: MentraDiscoveredDevice) {
        if !discoveredDevices.contains(where: { $0.name == device.name }) {
            discoveredDevices.append(device)
        }
        if selectedDevice == nil || device.name == "Mentra_Live_E613" {
            selectedDevice = device
        }
        append(tag: "BLE", text: "Discovered \(device.name)")
        connectAutoTargetIfNeeded(device)
    }

    func mentraBluetoothSDK(_: MentraBluetoothSDK, didChangeDefaultDevice device: MentraPairedDevice?) {
        if let device {
            append(tag: "BLE", text: "Default device changed: \(device.name)")
        }
    }

    func mentraBluetoothSDK(_: MentraBluetoothSDK, didReceive event: MentraBluetoothEvent) {
        switch event {
        case let .streamStatus(status):
            let text = summarize(status.values, fallback: "Stream status update")
            append(tag: "STREAM", text: text)
            videoStatus = text
            applyStreamStatus(status.values)
        default:
            append(tag: "EVENT", text: event.description)
        }
    }

    func mentraBluetoothSDK(_: MentraBluetoothSDK, didReceiveMicPcm frame: Data) {
        append(tag: "AUDIO", text: "Received PCM frame \(frame.count) bytes")
    }

    func mentraBluetoothSDK(_: MentraBluetoothSDK, didReceiveMicLc3 frame: Data) {
        append(tag: "AUDIO", text: "Received LC3 frame \(frame.count) bytes")
    }

    func mentraBluetoothSDK(_: MentraBluetoothSDK, didLog message: String) {
        append(tag: "SDK", text: message)
    }

    func mentraBluetoothSDK(_: MentraBluetoothSDK, didFail error: MentraBluetoothError) {
        append(tag: "SDK", text: error.description)
    }

    private func append(tag: String, text: String) {
        events.insert(ReceiverEvent.make(tag: tag, text: text), at: 0)
        if events.count > 40 {
            events.removeLast(events.count - 40)
        }
        print("[\(tag)] \(text)")
    }

    private func configureAutoRun() {
        let arguments = ProcessInfo.processInfo.arguments
        let environment = ProcessInfo.processInfo.environment
        autoRunEnabled = arguments.contains("--autorun") || environment["MENTRA_WEBRTC_AUTORUN"] == "1"
        if let targetIndex = arguments.firstIndex(of: "--target"),
           arguments.indices.contains(arguments.index(after: targetIndex)) {
            autoTargetName = arguments[arguments.index(after: targetIndex)]
        } else if let targetName = environment["MENTRA_WEBRTC_TARGET_NAME"], !targetName.isEmpty {
            autoTargetName = targetName
        }
        if let stopIndex = arguments.firstIndex(of: "--auto-stop-after"),
           arguments.indices.contains(arguments.index(after: stopIndex)),
           let seconds = TimeInterval(arguments[arguments.index(after: stopIndex)]),
           seconds > 0 {
            autoStopAfterSeconds = seconds
        } else if let secondsText = environment["MENTRA_WEBRTC_AUTO_STOP_AFTER"],
                  let seconds = TimeInterval(secondsText),
                  seconds > 0 {
            autoStopAfterSeconds = seconds
        }
    }

    private func connectAutoTargetIfNeeded(_ device: MentraDiscoveredDevice) {
        guard autoRunEnabled,
              !autoConnectAttempted,
              device.name == autoTargetName else {
            return
        }
        autoConnectAttempted = true
        selectedDevice = device
        sdk.stopScan()
        append(tag: "AUTO", text: "Target \(device.name) discovered; connecting")
        sdk.connect(to: device)
    }

    private func startAutoStreamIfReady() {
        guard autoRunEnabled,
              !autoStreamAttempted,
              !streamStartPending,
              !streamStarted,
              glassesConnected else {
            return
        }
        autoStreamAttempted = true
        append(tag: "AUTO", text: "Target connected; starting direct WHIP stream")
        startDirectStream()
    }

    private func sendStartStream(streamUrl: String, streamId: String) {
        sdk.startStream(
            MentraStreamRequest(
                streamUrl: streamUrl,
                streamId: streamId,
                keepAlive: true,
                keepAliveIntervalSeconds: 15
            )
        )
        streamStartPending = false
        streamStarted = true
        append(tag: "STREAM", text: "Sent startStream to glasses: \(streamUrl)")
    }

    private func applyStreamStatus(_ values: [String: Any]) {
        switch stringValue(values, "status") {
        case "streaming", "initializing", "starting":
            if let streamId = stringValue(values, "streamId") {
                activeStreamId = streamId
                self.streamId = streamId
            }
            if let activeStreamId, keepAliveTask == nil {
                startKeepAlive(streamId: activeStreamId)
            }
            scheduleAutoStopIfRequested()
        case "stopped", "stopping", "error", "error_not_streaming":
            streamStartPending = false
            streamStarted = false
            stopKeepAlive()
        default:
            break
        }
    }

    private func startKeepAlive(streamId: String) {
        stopKeepAlive()
        keepAliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                await MainActor.run {
                    guard let self,
                          self.activeStreamId == streamId,
                          self.streamStarted || self.streamStartPending else {
                        return
                    }
                    self.sdk.keepStreamAlive(
                        MentraStreamKeepAliveRequest(
                            streamId: streamId,
                            ackId: "ack-\(Int(Date().timeIntervalSince1970 * 1000))"
                        )
                    )
                    self.append(tag: "TX", text: "stream keep alive")
                }
            }
        }
    }

    private func stopKeepAlive() {
        keepAliveTask?.cancel()
        keepAliveTask = nil
    }

    private func finishLocalReceiverStop() {
        teardownTask?.cancel()
        teardownTask = nil
        whipProxy.stop()
        receiver.stop()
        receiverRunning = false
        videoStatus = "Stopped"
        append(tag: "STREAM", text: "Stopped stream and GStreamer receiver")
    }

    private func scheduleAutoStopIfRequested() {
        guard autoStopTask == nil,
              let seconds = autoStopAfterSeconds else {
            return
        }
        append(tag: "AUTO", text: "Auto-stop scheduled in \(Int(seconds)) seconds")
        autoStopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            await MainActor.run {
                guard let self,
                      self.streamStarted || self.receiverRunning else {
                    return
                }
                self.append(tag: "AUTO", text: "Auto-stop firing")
                self.stopDirectStream()
            }
        }
    }

    private func startReceiverAndProxy() throws -> (publicPort: Int, backendPort: Int) {
        var lastError: Error?

        for ports in [(8190, 8191), (8192, 8193), (8194, 8195)] {
            do {
                try receiver.start(withAdvertisedHost: "127.0.0.1", port: ports.1)
                try whipProxy.start(listenPort: UInt16(ports.0), backendPort: UInt16(ports.1))
                return (publicPort: ports.0, backendPort: ports.1)
            } catch {
                lastError = error
                whipProxy.stop()
                receiver.stop()
                append(tag: "NET", text: "Port pair \(ports.0)->\(ports.1) unavailable: \(error.localizedDescription)")
            }
        }

        throw lastError ?? NSError(
            domain: "com.mentra.examples.ios-webrtc-receiver",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "No local WHIP port pair was available"]
        )
    }

    private static func bestLocalIPv4Address() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else {
            return nil
        }
        defer { freeifaddrs(interfaces) }

        var fallback: String?
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            let interface = current.pointee
            guard let addressPointer = interface.ifa_addr,
                  addressPointer.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }
            let name = String(cString: interface.ifa_name)
            var address = addressPointer.pointee
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                &address,
                socklen_t(address.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else {
                continue
            }
            let ip = String(cString: hostname)
            guard ip != "127.0.0.1" else {
                continue
            }
            if name == "en0" {
                return ip
            }
            fallback = fallback ?? ip
        }
        return fallback
    }
}

private extension ReceiverEvent {
    static func make(tag: String, text: String) -> ReceiverEvent {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return ReceiverEvent(time: formatter.string(from: Date()), tag: tag, text: text)
    }
}

private func summarize(_ values: [String: Any], fallback: String) -> String {
    if values.isEmpty {
        return fallback
    }
    let preferredKeys = [
        "deviceName",
        "name",
        "model",
        "connectionState",
        "connected",
        "streaming",
        "status",
        "statusDetail",
        "wifiLocalIp",
        "batteryLevel"
    ]
    let pieces = preferredKeys.compactMap { key -> String? in
        guard let value = values[key] else { return nil }
        return "\(key)=\(value)"
    }
    if !pieces.isEmpty {
        return pieces.joined(separator: " ")
    }
    return values
        .sorted { $0.key < $1.key }
        .prefix(4)
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: " ")
}

private func stringValue(_ values: [String: Any], _ key: String) -> String? {
    guard let value = values[key] as? String else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
