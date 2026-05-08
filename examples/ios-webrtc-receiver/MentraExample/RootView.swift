import SwiftUI
import UIKit

struct RootView: View {
    @ObservedObject var model: BluetoothViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    receiverPreview
                    deviceSection
                    streamSection
                    eventLog
                }
                .padding(18)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("WHIP Receiver")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                model.startAutoRunIfRequested()
            }
        }
    }

    private var receiverPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(model.receiverRunning ? "Receiver running" : "Receiver stopped", systemImage: model.receiverRunning ? "dot.radiowaves.left.and.right" : "pause.circle")
                    .font(.headline)
                Spacer()
                Text(model.streamStarted ? "Streaming" : (model.streamStartPending ? "Starting" : "Idle"))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(model.streamStarted ? Color.green.opacity(0.16) : (model.streamStartPending ? Color.orange.opacity(0.16) : Color.secondary.opacity(0.12)))
                    .clipShape(Capsule())
            }

            GStreamerVideoView(receiver: model.receiver)
                .frame(height: 210)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .bottomLeading) {
                    Text(model.videoStatus)
                        .font(.caption.monospaced())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.58))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(8)
                }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Device")
                .font(.title3.weight(.semibold))

            statusRow(label: "Bluetooth", value: model.bluetoothStatus)
            statusRow(label: "Glasses", value: model.glassesStatus)

            HStack(spacing: 10) {
                Button {
                    model.startScan()
                } label: {
                    Label("Scan", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.glassesConnected)

                Button {
                    model.connectSelectedDevice()
                } label: {
                    Label(model.glassesConnected ? "Connected" : "Connect", systemImage: "link")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.glassesConnected || model.selectedDevice == nil)
            }

            if model.discoveredDevices.isEmpty {
                Text("No Mentra Live devices discovered yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(model.discoveredDevices.enumerated()), id: \.offset) { _, device in
                        Button {
                            model.select(device)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(device.name)
                                        .font(.body.weight(.semibold))
                                    Text(device.name == "Mentra_Live_E613" ? "Requested hardware target" : "Nearby Mentra Live device")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if model.isSelected(device) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                            .padding(10)
                            .background(Color(uiColor: .tertiarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var streamSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stream")
                .font(.title3.weight(.semibold))

            statusRow(label: "Local IP", value: model.localIPAddress)
            statusRow(label: "WHIP URL", value: model.whipURL)
            statusRow(label: "Stream ID", value: model.streamId ?? "none")

            HStack(spacing: 10) {
                Button {
                    model.refreshLocalIPAddress()
                } label: {
                    Label("Refresh IP", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.receiverRunning)

                Button {
                    model.startDirectStream()
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.glassesConnected || model.streamStartPending || model.streamStarted)
            }

            Button(role: .destructive) {
                model.stopDirectStream()
            } label: {
                Label("Stop stream and receiver", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!model.streamStarted && !model.receiverRunning)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var eventLog: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Events")
                .font(.title3.weight(.semibold))

            ForEach(model.events) { event in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(event.tag)
                            .font(.caption.monospaced().weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(event.time)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Text(event.text)
                        .font(.footnote)
                        .textSelection(.enabled)
                }
                .padding(10)
                .background(Color(uiColor: .tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func statusRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct GStreamerVideoView: UIViewRepresentable {
    let receiver: GStreamerWhipReceiver

    func makeUIView(context: Context) -> UIView {
        receiver.videoView
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
