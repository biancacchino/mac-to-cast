import Network
import Testing
@testable import MacToCast

let endpoint = NWEndpoint.hostPort(host: "192.168.1.20", port: 8009)

@Test func readsIdAndFriendlyName() {
    let device = CastDevice(
        instanceName: "Chromecast-dca719a23335631b1b72cf68db3cbb89",
        txt: ["id": "dca719a23335631b1b72cf68db3cbb89", "fn": "Living Room TV", "md": "Chromecast"],
        endpoint: endpoint
    )
    #expect(device.id == "dca719a23335631b1b72cf68db3cbb89")
    #expect(device.name == "Living Room TV")
}

@Test func fallsBackToInstanceNameWhenTxtIsMissing() {
    let device = CastDevice(instanceName: "Chromecast-abc", txt: [:], endpoint: endpoint)
    #expect(device.id == "Chromecast-abc")
    #expect(device.name == "Chromecast-abc")
}

@Test func blankFriendlyNameFallsBack() {
    let device = CastDevice(instanceName: "Chromecast-abc", txt: ["fn": "  \n "], endpoint: endpoint)
    #expect(device.name == "Chromecast-abc")
}

@Test func friendlyNameIsTrimmedAndCapped() {
    let long = String(repeating: "x", count: 500)
    let device = CastDevice(instanceName: "Chromecast-abc", txt: ["fn": "  \(long)  "], endpoint: endpoint)
    #expect(device.name == String(repeating: "x", count: CastDevice.maxNameLength))
}

@Test func devicesAreDedupedByIdAndSortedByName() {
    let devices = CastDevice.list([
        CastDevice(instanceName: "b", txt: ["id": "2", "fn": "Living Room TV 3"], endpoint: endpoint),
        CastDevice(instanceName: "a", txt: ["id": "1", "fn": "Living Room TV"], endpoint: endpoint),
        CastDevice(instanceName: "c", txt: ["id": "1", "fn": "Spoofed copy"], endpoint: endpoint),
    ])
    #expect(devices.map(\.id) == ["1", "2"])
    #expect(devices.map(\.name) == ["Living Room TV", "Living Room TV 3"])
}
