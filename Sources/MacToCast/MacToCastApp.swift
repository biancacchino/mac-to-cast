import SwiftUI

@main
struct MacToCastApp: App {
    var body: some Scene {
        WindowGroup(AppInfo.name) {
            DeviceListView()
                .frame(minWidth: 400, minHeight: 300)
        }
    }
}

struct DeviceListView: View {
    @State private var browser = DeviceBrowser()

    var body: some View {
        Group {
            if let message = browser.errorMessage {
                ContentUnavailableView("Can't search the network", systemImage: "wifi.exclamationmark", description: Text(message))
            } else if browser.devices.isEmpty {
                ProgressView("Looking for Chromecasts…")
            } else {
                List(browser.devices) { Label($0.name, systemImage: "tv") }
            }
        }
        .task { browser.start() }
    }
}
