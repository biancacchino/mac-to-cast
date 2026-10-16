import SwiftUI

@main
struct MacToCastApp: App {
    var body: some Scene {
        WindowGroup(AppInfo.name) {
            Text(AppInfo.name)
                .frame(minWidth: 400, minHeight: 300)
        }
    }
}
