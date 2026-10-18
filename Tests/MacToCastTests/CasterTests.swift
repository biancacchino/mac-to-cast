import Network
import Testing
@testable import MacToCast

@Test func statusLineNamesTheTV() {
    #expect(Caster.statusText(.connecting, device: "Bedroom TV") == "Connecting to Bedroom TV…")
    #expect(Caster.statusText(.launching, device: "Bedroom TV") == "Starting on Bedroom TV…")
    #expect(Caster.statusText(.loading, device: "Bedroom TV") == "Starting on Bedroom TV…")
    #expect(Caster.statusText(.media("IDLE"), device: "Bedroom TV") == "Starting on Bedroom TV…")
    #expect(Caster.statusText(.media("BUFFERING"), device: "Bedroom TV") == "Buffering on Bedroom TV…")
    #expect(Caster.statusText(.media("PLAYING"), device: "Bedroom TV") == "Casting to Bedroom TV")
    #expect(Caster.statusText(.failed("The Chromecast closed the connection"), device: "Bedroom TV") == "The Chromecast closed the connection")
}

@Test func readsIPv4FromEndpoints() {
    #expect(CastSession.ipv4(.hostPort(host: "192.168.0.104", port: 8009)) == IPv4Address("192.168.0.104"))
    #expect(CastSession.ipv4(.hostPort(host: "::ffff:192.168.0.7", port: 8009)) == IPv4Address("192.168.0.7"))
    #expect(CastSession.ipv4(.hostPort(host: "fe80::1", port: 8009)) == nil)
    #expect(CastSession.ipv4(nil) == nil)
    #expect(IPv4Address("192.168.0.7")!.dotted == "192.168.0.7")
}
