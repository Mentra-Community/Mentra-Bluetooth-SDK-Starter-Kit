import SwiftUI

@main
struct MentraWebRTCReceiverApp: App {
    @StateObject private var model = BluetoothViewModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}
