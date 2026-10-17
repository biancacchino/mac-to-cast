import Foundation
import Network

/// A Chromecast found on the local network.
/// TXT values come from any device on the LAN, so they are trimmed and capped before display.
struct CastDevice: Identifiable {
    static let maxNameLength = 64

    /// The TXT `id`, stable across renames. Falls back to the Bonjour instance name.
    let id: String
    /// The TXT `fn` (the name set in Google Home), for display only.
    let name: String
    let endpoint: NWEndpoint

    init(instanceName: String, txt: [String: String], endpoint: NWEndpoint) {
        id = Self.clean(txt["id"]) ?? instanceName
        name = Self.clean(txt["fn"]) ?? instanceName
        self.endpoint = endpoint
    }

    init?(result: NWBrowser.Result) {
        guard case .service(let instanceName, _, _, _) = result.endpoint else { return nil }
        var txt: [String: String] = [:]
        if case .bonjour(let record) = result.metadata { txt = record.dictionary }
        self.init(instanceName: instanceName, txt: txt, endpoint: result.endpoint)
    }

    /// Sorted by name; a repeated `id` (for example one device seen on Wi-Fi and Ethernet) collapses to one row.
    /// This does not prove a device is genuine: anything on the LAN can copy another device's `id`.
    static func list(_ devices: [CastDevice]) -> [CastDevice] {
        var seen = Set<String>()
        return devices
            .sorted { ($0.name, $0.endpoint.debugDescription) < ($1.name, $1.endpoint.debugDescription) }
            .filter { seen.insert($0.id).inserted }
    }

    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxNameLength))
    }
}
