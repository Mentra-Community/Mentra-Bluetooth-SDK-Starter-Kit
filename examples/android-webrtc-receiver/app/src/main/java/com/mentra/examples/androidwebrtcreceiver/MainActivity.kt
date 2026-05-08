package com.mentra.examples.androidwebrtcreceiver

import android.Manifest
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.app.ActivityCompat

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING)
        requestRuntimePermissions()

        val autorun = intent.getBooleanExtra("autorun", false) ||
            intent.getStringExtra("autorun").equals("true", ignoreCase = true)
        val targetName = if (autorun) {
            intent.getStringExtra("target") ?: "Mentra_Live_E613"
        } else {
            null
        }
        val autoStopAfter = intent.getLongExtra("autoStopAfter", 0).takeIf { it > 0 }

        setContent {
            MaterialTheme {
                val context = LocalContext.current.applicationContext
                val controller = remember {
                    ReceiverController(
                        context = context,
                        autoTargetName = targetName,
                        autoStopAfterSeconds = autoStopAfter,
                    )
                }
                DisposableEffect(controller) {
                    onDispose { controller.close() }
                }
                ReceiverApp(controller)
            }
        }
    }

    private fun requestRuntimePermissions() {
        val permissions = buildList {
            add(Manifest.permission.CAMERA)
            add(Manifest.permission.RECORD_AUDIO)
            add(Manifest.permission.ACCESS_FINE_LOCATION)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                add(Manifest.permission.BLUETOOTH_SCAN)
                add(Manifest.permission.BLUETOOTH_CONNECT)
            }
            if (Build.VERSION.SDK_INT >= 33) {
                add(Manifest.permission.POST_NOTIFICATIONS)
            }
        }.toTypedArray()
        ActivityCompat.requestPermissions(this, permissions, 100)
    }
}

@Composable
private fun ReceiverApp(controller: ReceiverController) {
    val state = controller.state
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFFF4F7F8))
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Text("WHIP Receiver", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold)
        PreviewSection(controller)
        DeviceSection(controller)
        StreamSection(controller)
        EventSection(state.events)
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun PreviewSection(controller: ReceiverController) {
    val state = controller.state
    Section {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                if (state.receiverRunning) "Receiver running" else "Receiver stopped",
                modifier = Modifier.weight(1f),
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                if (state.streaming) "Streaming" else if (state.streamStarting) "Starting" else "Idle",
                color = if (state.streaming) Color(0xFF0B7D45) else Color(0xFF59666D),
                fontWeight = FontWeight.SemiBold,
            )
        }
        Spacer(Modifier.height(10.dp))
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(220.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(Color.Black),
        ) {
            state.videoFrame?.let { frame ->
                Image(
                    bitmap = frame.asImageBitmap(),
                    contentDescription = null,
                    modifier = Modifier.fillMaxSize(),
                    contentScale = ContentScale.Fit,
                )
            }
            Text(
                state.videoStatus,
                color = Color.White,
                fontFamily = FontFamily.Monospace,
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .padding(8.dp)
                    .clip(RoundedCornerShape(6.dp))
                    .background(Color.Black.copy(alpha = 0.58f))
                    .padding(horizontal = 10.dp, vertical = 6.dp),
            )
        }
    }
}

@Composable
private fun DeviceSection(controller: ReceiverController) {
    val state = controller.state
    Section {
        Text("Device", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        StatusRow("Bluetooth", state.bluetoothStatus)
        StatusRow("Glasses", state.glassesStatus)
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
            Button(
                onClick = controller::startScan,
                enabled = !state.glassesConnected,
                modifier = Modifier.weight(1f),
            ) {
                Icon(Icons.Default.Search, contentDescription = null, modifier = Modifier.size(18.dp))
                Text("Scan", modifier = Modifier.padding(start = 6.dp))
            }
            OutlinedButton(
                onClick = controller::connectSelectedDevice,
                enabled = !state.glassesConnected && state.selectedDevice != null,
                modifier = Modifier.weight(1f),
            ) {
                Icon(Icons.Default.Link, contentDescription = null, modifier = Modifier.size(18.dp))
                Text(if (state.glassesConnected) "Connected" else "Connect", modifier = Modifier.padding(start = 6.dp))
            }
        }
        if (state.discoveredDevices.isEmpty()) {
            Text("No Mentra Live devices discovered yet.", color = Color(0xFF6E7A80))
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                state.discoveredDevices.forEach { device ->
                    val selected = state.selectedDevice?.name == device.name
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(8.dp))
                            .background(if (selected) Color(0xFFE4F4EB) else Color.White)
                            .clickable { controller.select(device) }
                            .padding(12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(device.name, fontWeight = FontWeight.SemiBold)
                            Text(
                                if (device.name == "Mentra_Live_E613") "Requested hardware target" else "Nearby Mentra Live device",
                                color = Color(0xFF6E7A80),
                            )
                        }
                        if (selected) Text("Selected", color = Color(0xFF0B7D45), fontWeight = FontWeight.SemiBold)
                    }
                }
            }
        }
    }
}

@Composable
private fun StreamSection(controller: ReceiverController) {
    val state = controller.state
    Section {
        Text("Stream", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        StatusRow("Local IP", state.localIp)
        StatusRow("WHIP URL", state.whipUrl)
        StatusRow("Stream ID", state.streamId ?: "none")
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
            OutlinedButton(
                onClick = controller::refreshLocalIp,
                enabled = !state.receiverRunning,
                modifier = Modifier.weight(1f),
            ) {
                Icon(Icons.Default.Refresh, contentDescription = null, modifier = Modifier.size(18.dp))
                Text("Refresh IP", modifier = Modifier.padding(start = 6.dp))
            }
            Button(
                onClick = controller::startDirectStream,
                enabled = state.glassesConnected && !state.streamStarting && !state.streaming,
                modifier = Modifier.weight(1f),
            ) {
                Icon(Icons.Default.PlayArrow, contentDescription = null, modifier = Modifier.size(18.dp))
                Text("Start", modifier = Modifier.padding(start = 6.dp))
            }
        }
        Button(
            onClick = controller::stopDirectStream,
            enabled = state.receiverRunning || state.streaming || state.streamStarting,
            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFC73A33)),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Icon(Icons.Default.Stop, contentDescription = null, modifier = Modifier.size(18.dp))
            Text("Stop stream and receiver", modifier = Modifier.padding(start = 6.dp))
        }
    }
}

@Composable
private fun EventSection(events: List<ReceiverEvent>) {
    Section {
        Text("Events", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        events.forEach { event ->
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(8.dp))
                    .background(Color(0xFFF4F7F8))
                    .padding(10.dp),
            ) {
                Row {
                    Text(event.tag, modifier = Modifier.weight(1f), fontFamily = FontFamily.Monospace, fontWeight = FontWeight.SemiBold)
                    Text(event.time, fontFamily = FontFamily.Monospace, color = Color(0xFF6E7A80))
                }
                Text(event.text)
            }
        }
    }
}

@Composable
private fun Section(content: @Composable ColumnScope.() -> Unit) {
    Surface(
        tonalElevation = 0.dp,
        shadowElevation = 0.dp,
        shape = RoundedCornerShape(8.dp),
        color = Color.White,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            content = content,
        )
    }
}

@Composable
private fun StatusRow(label: String, value: String) {
    Row(verticalAlignment = Alignment.Top) {
        Text(label, modifier = Modifier.weight(0.32f), color = Color(0xFF6E7A80), fontWeight = FontWeight.SemiBold)
        Text(value, modifier = Modifier.weight(0.68f), fontFamily = FontFamily.Monospace)
    }
}
