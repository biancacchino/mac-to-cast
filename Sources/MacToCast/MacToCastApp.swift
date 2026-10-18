import AppKit
import SwiftUI

/// A menu bar app, like AirPlay: pick a TV, then a window.
@main
struct MacToCastApp: App {
    @State private var caster = Caster()

    var body: some Scene {
        MenuBarExtra {
            CastMenu(caster: caster)
        } label: {
            Image(systemName: caster.device == nil ? "tv" : "tv.fill")
                .accessibilityLabel(AppInfo.name)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// A plain menu, as the HIG asks for menu bar extras. Items stay put and are disabled when they do nothing.
struct CastMenu: View {
    let caster: Caster

    var body: some View {
        Section("Cast a Window To") {
            if let message = caster.browser.errorMessage {
                Text(message)
            } else if caster.browser.devices.isEmpty {
                Text("Looking for Chromecasts…")
            }
            ForEach(caster.browser.devices) { device in
                Toggle(device.name, isOn: Binding(
                    get: { caster.device?.id == device.id },
                    set: { _ in caster.cast(to: device) }
                ))
            }
        }
        if let status = caster.statusText {
            Divider()
            Text(status)
        }
        Divider()
        Button("Stop Casting") { Task { await caster.stop() } }
            .keyboardShortcut(".")
            .disabled(caster.device == nil)
        Divider()
        Button("Quit \(AppInfo.name)") {
            // Send STOP first so the TV goes back to idle.
            Task {
                await caster.stop()
                NSApp.terminate(nil)
            }
        }
        .keyboardShortcut("q")
    }
}
