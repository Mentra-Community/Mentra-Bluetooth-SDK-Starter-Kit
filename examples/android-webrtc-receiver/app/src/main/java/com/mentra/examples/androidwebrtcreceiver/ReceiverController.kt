package com.mentra.examples.androidwebrtcreceiver

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.content.Context
import android.graphics.Bitmap
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.mentra.core.GlassesStore
import com.mentra.core.MentraBluetoothError
import com.mentra.core.MentraBluetoothSdk
import com.mentra.core.MentraBluetoothSdkCallback
import com.mentra.core.MentraBluetoothStatusUpdate
import com.mentra.core.MentraDeviceModel
import com.mentra.core.MentraDiscoveredDevice
import com.mentra.core.MentraGlassesStatusUpdate
import com.mentra.core.MentraPairedDevice
import com.mentra.core.MentraStreamKeepAliveRequest
import com.mentra.core.MentraStreamRequest
import com.mentra.core.MentraStreamStatusEvent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.net.Inet4Address
import java.net.NetworkInterface
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

data class ReceiverEvent(
    val time: String,
    val tag: String,
    val text: String,
)

data class ReceiverState(
    val discoveredDevices: List<MentraDiscoveredDevice> = emptyList(),
    val selectedDevice: MentraDiscoveredDevice? = null,
    val bluetoothStatus: String = "SDK ready",
    val glassesStatus: String = "Disconnected",
    val glassesConnected: Boolean = false,
    val receiverRunning: Boolean = false,
    val streamStarting: Boolean = false,
    val streaming: Boolean = false,
    val streamId: String? = null,
    val localIp: String = bestLocalIpv4Address() ?: "127.0.0.1",
    val whipUrl: String = "Receiver not started",
    val videoStatus: String = "Waiting for WHIP publish",
    val videoFrame: Bitmap? = null,
    val events: List<ReceiverEvent> = listOf(receiverEvent("APP", "Ready. Scan for Mentra_Live_E613.")),
)

class ReceiverController(
    context: Context,
    private val autoTargetName: String? = null,
    private val autoStopAfterSeconds: Long? = null,
) : MentraBluetoothSdkCallback(), AutoCloseable {
    var state by mutableStateOf(ReceiverState())
        private set

    private val appContext = context.applicationContext
    private val sdk = MentraBluetoothSdk.create(appContext, this)
    private val scope = CoroutineScope(Dispatchers.Main + Job())
    private val receiver = GStreamerWhipReceiver(
        appContext,
        onStatus = { message ->
            append("GST", message)
            if (message.startsWith("Rendered ") || message.startsWith("Pipeline ")) {
                state = state.copy(videoStatus = message)
            }
        },
        onFrame = { bitmap ->
            state = state.copy(videoFrame = bitmap)
        },
    )
    private val proxy = WhipHeaderProxy { append("WHIP-PROXY", it) }
    private val glassesValues = mutableMapOf<String, Any>()
    private val bluetoothValues = mutableMapOf<String, Any>()
    private var activeStreamId: String? = null
    private var keepAliveJob: Job? = null
    private var autoConnectAttempted = false
    private var autoStreamAttempted = false
    private var autoStopJob: Job? = null
    private var teardownJob: Job? = null
    private var transportReady = false

    val videoReceiver: GStreamerWhipReceiver
        get() = receiver

    init {
        glassesValues.putAll(sdk.getGlassesStatus().values)
        bluetoothValues.putAll(sdk.getBluetoothStatus().values)
        state = state.copy(
            bluetoothStatus = summarize(bluetoothValues, "Bluetooth status pending"),
            glassesStatus = summarize(glassesValues, "Disconnected"),
            glassesConnected = isGlassesConnected(glassesValues),
        )
        if (!autoTargetName.isNullOrBlank()) {
            append("AUTO", "Auto-run enabled for $autoTargetName")
            seedBondedDeviceAddress(autoTargetName)
            sdk.connectByName(MentraDeviceModel.MENTRA_LIVE, autoTargetName)
            autoConnectAttempted = true
        }
    }

    fun startScan() {
        state = state.copy(discoveredDevices = emptyList(), selectedDevice = null)
        append("BLE", "Scanning for Mentra Live glasses")
        sdk.startScan(MentraDeviceModel.MENTRA_LIVE)
    }

    fun select(device: MentraDiscoveredDevice) {
        state = state.copy(selectedDevice = device)
        append("BLE", "Selected ${device.name}")
    }

    fun connectSelectedDevice() {
        val device = state.selectedDevice
        if (device == null) {
            append("BLE", "Scan and select a device first")
            return
        }
        append("BLE", "Connecting to ${device.name}")
        sdk.connect(device)
    }

    fun refreshLocalIp() {
        state = state.copy(localIp = bestLocalIpv4Address() ?: "127.0.0.1")
        append("NET", "Local WHIP host ${state.localIp}")
    }

    fun startDirectStream() {
        if (!state.glassesConnected) {
            append("STREAM", "Connect glasses before starting stream")
            return
        }
        teardownJob?.cancel()
        teardownJob = null
        refreshLocalIp()
        val host = state.localIp
        val ports = listOf(8190 to 8191, 8192 to 8193, 8194 to 8195)

        var lastError: Throwable? = null
        for ((publicPort, backendPort) in ports) {
            try {
                val url = receiver.start(host, publicPort, backendPort)
                proxy.start(publicPort, backendPort)
                val nextStreamId = "android-gst-${System.currentTimeMillis()}"
                activeStreamId = nextStreamId
                state = state.copy(
                    receiverRunning = true,
                    streamStarting = true,
                    streamId = nextStreamId,
                    whipUrl = url,
                    videoStatus = "WHIP server listening",
                )
                append("STREAM", "Receiver ready at $url; proxying to local GStreamer port $backendPort")
                scope.launch {
                    delay(1_000)
                    if (state.receiverRunning && state.streamStarting && activeStreamId == nextStreamId) {
                        sendStartStream(url, nextStreamId)
                    }
                }
                return
            } catch (error: Throwable) {
                lastError = error
                proxy.stop()
                receiver.stop()
                append("NET", "Port pair $publicPort->$backendPort unavailable: ${error.message}")
            }
        }
        append("GST", "Failed to start receiver: ${lastError?.message ?: "No local WHIP port pair was available"}")
    }

    fun stopDirectStream() {
        stopKeepAlive()
        autoStopJob?.cancel()
        autoStopJob = null
        teardownJob?.cancel()

        if (state.streaming || state.streamStarting || state.glassesConnected) {
            sdk.stopStream()
            append("STREAM", "Sent stopStream to glasses")
        }

        state = state.copy(
            streamStarting = false,
            streaming = false,
            streamId = null,
            videoStatus = if (state.receiverRunning) "Stopping" else "Stopped",
            videoFrame = null,
        )
        activeStreamId = null

        if (state.receiverRunning) {
            teardownJob = scope.launch {
                delay(1_000)
                finishLocalReceiverStop()
            }
        } else {
            finishLocalReceiverStop()
        }
    }

    fun setSurface(surface: android.view.Surface) {
        receiver.setSurface(surface)
    }

    fun clearSurface() {
        receiver.clearSurface()
    }

    override fun onDeviceDiscovered(device: MentraDiscoveredDevice) {
        if (state.discoveredDevices.none { it.name == device.name }) {
            state = state.copy(discoveredDevices = state.discoveredDevices + device)
        }
        if (state.selectedDevice == null || device.name == "Mentra_Live_E613") {
            state = state.copy(selectedDevice = device)
        }
        append("BLE", "Discovered ${device.name}")

        val target = autoTargetName
        if (!target.isNullOrBlank() && !autoConnectAttempted && device.name == target) {
            autoConnectAttempted = true
            sdk.stopScan()
            append("AUTO", "Target ${device.name} discovered; connecting")
            sdk.connect(device)
        }
    }

    override fun onGlassesStatusChanged(status: MentraGlassesStatusUpdate) {
        glassesValues.putAll(status.values)
        state = state.copy(
            glassesStatus = summarize(status.values, "Glasses status updated"),
            glassesConnected = isGlassesConnected(glassesValues),
        )
        append("GLASSES", state.glassesStatus)
        maybeStartAutoStream()
    }

    override fun onBluetoothStatusChanged(status: MentraBluetoothStatusUpdate) {
        bluetoothValues.putAll(status.values)
        state = state.copy(bluetoothStatus = summarize(status.values, "Bluetooth status updated"))
        append("BLE", state.bluetoothStatus)
    }

    override fun onDefaultDeviceChanged(device: MentraPairedDevice?) {
        if (device != null) {
            append("BLE", "Default device changed: ${device.name}")
        }
    }

    override fun onStreamStatus(event: MentraStreamStatusEvent) {
        append("STREAM", summarize(event.values, "Stream status update"))
        state = state.copy(videoStatus = summarize(event.values, "Stream status update"))
        applyStreamStatus(event.values)
    }

    override fun onLog(message: String) {
        append("SDK", message)
        if (!transportReady && message.contains("BLE reconnection fully ready", ignoreCase = true)) {
            transportReady = true
            state = state.copy(
                glassesStatus = "BLE transport ready for ${autoTargetName ?: "Mentra Live"}",
                glassesConnected = true,
            )
            append("GLASSES", state.glassesStatus)
            maybeStartAutoStream()
        }
    }

    override fun onError(error: MentraBluetoothError) {
        append("SDK", "${error.code}: ${error.message}")
    }

    override fun close() {
        stopKeepAlive()
        autoStopJob?.cancel()
        teardownJob?.cancel()
        sdk.stopStream()
        proxy.stop()
        receiver.close()
        sdk.close()
    }

    private fun sendStartStream(streamUrl: String, streamId: String) {
        sdk.startStream(
            MentraStreamRequest(
                streamUrl = streamUrl,
                streamId = streamId,
                keepAlive = true,
                keepAliveIntervalSeconds = 15,
            ),
        )
        state = state.copy(streamStarting = false, streaming = true)
        startKeepAlive(streamId)
        scheduleAutoStopIfRequested()
        append("STREAM", "Sent startStream to glasses: $streamUrl")
    }

    private fun applyStreamStatus(values: Map<String, Any>) {
        when (values["status"] as? String) {
            "streaming", "initializing", "starting" -> {
                activeStreamId = values["streamId"] as? String ?: activeStreamId
                state = state.copy(
                    streamStarting = false,
                    streaming = true,
                    streamId = activeStreamId ?: state.streamId,
                )
                if (activeStreamId != null && keepAliveJob == null) {
                    startKeepAlive(activeStreamId ?: return)
                }
                scheduleAutoStopIfRequested()
            }
            "stopped", "stopping", "error", "error_not_streaming" -> {
                stopKeepAlive()
                state = state.copy(streamStarting = false, streaming = false)
            }
        }
    }

    private fun startKeepAlive(streamId: String) {
        stopKeepAlive()
        keepAliveJob = scope.launch {
            while (isActive) {
                delay(15_000)
                if (activeStreamId == streamId && (state.streaming || state.streamStarting)) {
                    sdk.keepStreamAlive(
                        MentraStreamKeepAliveRequest(
                            streamId = streamId,
                            ackId = "ack-${System.currentTimeMillis()}",
                        ),
                    )
                    append("TX", "stream keep alive")
                }
            }
        }
    }

    private fun stopKeepAlive() {
        keepAliveJob?.cancel()
        keepAliveJob = null
    }

    private fun scheduleAutoStopIfRequested() {
        val seconds = autoStopAfterSeconds ?: return
        if (autoStopJob != null) return
        append("AUTO", "Auto-stop scheduled in $seconds seconds")
        autoStopJob = scope.launch {
            delay(seconds * 1_000)
            if (state.streaming || state.receiverRunning) {
                append("AUTO", "Auto-stop firing")
                stopDirectStream()
            }
        }
    }

    private fun maybeStartAutoStream() {
        if (!autoTargetName.isNullOrBlank() && !autoStreamAttempted && state.glassesConnected) {
            autoStreamAttempted = true
            append("AUTO", "Target connected; starting direct WHIP stream")
            startDirectStream()
        }
    }

    @SuppressLint("MissingPermission")
    private fun seedBondedDeviceAddress(targetName: String) {
        val bondedDevice = BluetoothAdapter.getDefaultAdapter()
            ?.bondedDevices
            ?.firstOrNull { it.name == targetName }
        if (bondedDevice == null) {
            append("AUTO", "No bonded Android device named $targetName; SDK will scan")
            return
        }

        GlassesStore.apply("core", "device_name", targetName)
        GlassesStore.apply("core", "device_address", bondedDevice.address)
        append("AUTO", "Seeded bonded address ${bondedDevice.address} for $targetName")
    }

    private fun finishLocalReceiverStop() {
        teardownJob?.cancel()
        teardownJob = null
        proxy.stop()
        receiver.stop()
        state = state.copy(
            receiverRunning = false,
            streamStarting = false,
            streaming = false,
            videoStatus = "Stopped",
            videoFrame = null,
        )
        append("STREAM", "Stopped stream and GStreamer receiver")
    }

    private fun append(tag: String, text: String) {
        state = state.copy(events = (listOf(receiverEvent(tag, text)) + state.events).take(50))
        println("[$tag] $text")
    }
}

private fun receiverEvent(tag: String, text: String): ReceiverEvent {
    val formatter = SimpleDateFormat("HH:mm:ss", Locale.US)
    return ReceiverEvent(formatter.format(Date()), tag, text)
}

private fun summarize(values: Map<String, Any>, fallback: String): String {
    if (values.isEmpty()) return fallback
    val preferredKeys = listOf(
        "deviceName",
        "name",
        "model",
        "connectionState",
        "connected",
        "streaming",
        "status",
        "statusDetail",
        "wifiLocalIp",
        "batteryLevel",
    )
    val pieces = preferredKeys.mapNotNull { key ->
        values[key]?.let { "$key=$it" }
    }
    if (pieces.isNotEmpty()) return pieces.joinToString(" ")
    return values.entries.sortedBy { it.key }.take(4).joinToString(" ") { "${it.key}=${it.value}" }
}

private fun bestLocalIpv4Address(): String? {
    val interfaces = NetworkInterface.getNetworkInterfaces().toList()
    var fallback: String? = null
    interfaces.forEach { networkInterface ->
        if (!networkInterface.isUp || networkInterface.isLoopback) return@forEach
        networkInterface.inetAddresses.toList().forEach { address ->
            if (address is Inet4Address && !address.isLoopbackAddress) {
                if (networkInterface.name == "wlan0") return address.hostAddress
                fallback = fallback ?: address.hostAddress
            }
        }
    }
    return fallback
}

private fun isGlassesConnected(values: Map<String, Any>): Boolean {
    val state = values["connectionState"] as? String
    val connected = values["connected"] as? Boolean
    return connected == true || state.equals("CONNECTED", ignoreCase = true)
}
