import Network
import Observation
import dnssd
import os

private let log = Logger(subsystem: "com.biancacchino.MacToCast", category: "discovery")

/// Keeps `devices` in sync with the Chromecasts advertising `_googlecast._tcp` on the LAN.
@MainActor @Observable
final class DeviceBrowser {
    private(set) var devices: [CastDevice] = []
    private(set) var errorMessage: String?
    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_googlecast._tcp", domain: nil), using: .tcp)
        // The browser hands over the full current set each time, so the list is rebuilt, not patched.
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated {
                let devices = CastDevice.list(results.compactMap(CastDevice.init(result:)))
                log.info("Found \(devices.count) Chromecasts: \(devices.map(\.name), privacy: .public)")
                self?.devices = devices
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                switch state {
                case .waiting(let error):
                    log.error("Browser waiting: \(error, privacy: .public)")
                    self?.errorMessage = Self.message(for: error)
                case .failed(let error):
                    // A failed browser never recovers (for example after mDNSResponder restarts), so start a new one.
                    log.error("Browser failed, restarting: \(error, privacy: .public)")
                    self?.errorMessage = Self.message(for: error)
                    self?.restart()
                case .ready: self?.errorMessage = nil
                default: break
                }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    private func restart() {
        browser?.cancel()
        browser = nil
        Task {
            try? await Task.sleep(for: .seconds(2))
            start()
        }
    }

    private static func message(for error: NWError) -> String {
        if case .dns(let code) = error, code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied) {
            return "Local Network access is off. Turn it on in System Settings > Privacy & Security > Local Network."
        }
        return error.localizedDescription
    }
}
