import Foundation
import MCPServerKit
import Testing
import VinylFeverCore

struct MCPEventsProbeTests {
  @Test("event support stays disabled unless explicitly enabled")
  func optInGate() {
    #expect(!MCPEventsProbe.isEnabled(environment: [:]))
    #expect(!MCPEventsProbe.isEnabled(environment: ["VF_MCP_EVENTS_PROBE": "0"]))
    #expect(MCPEventsProbe.isEnabled(environment: ["VF_MCP_EVENTS_PROBE": "1"]))
  }

  @Test("subscription secrets require the Standard Webhooks prefix and key length")
  func validatesSecret() {
    #expect(MCPEventsProbe.validSigningSecret("whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw"))
    #expect(!MCPEventsProbe.validSigningSecret("wrong_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw"))
    #expect(!MCPEventsProbe.validSigningSecret("whsec_YWJj"))
  }

  @Test("Standard Webhooks published HMAC test vector")
  func standardWebhookVector() throws {
    let signature = try #require(MCPEventsProbe.standardSignature(
      secret: "whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw",
      id: "msg_p5jXN8AQM9LWM0D4loKWxJek",
      timestamp: "1614265330",
      body: Data(#"{"test": 2432232314}"#.utf8)
    ))
    #expect(signature == "v1,g0hM9SsE+OTPJTGt/tmIKtSyZlE3uFJELVlNIOLJ1OE=")
  }

  @Test("event catalog advertises the finished playlist payload")
  func eventCatalog() async throws {
    let server = LibraryMCPServer.make(snapshotURL: URL(fileURLWithPath: "/tmp/missing-snapshot.json"))
    let discovery = try #require(await MCPEventsProbe.handleRequest(#"{"jsonrpc":"2.0","id":0,"method":"server/discover"}"#, server: server))
    let discoveryRPC = try #require(JSONSerialization.jsonObject(with: Data(discovery.utf8)) as? [String: Any])
    let discoveryResult = try #require(discoveryRPC["result"] as? [String: Any])
    let capabilities = try #require(discoveryResult["capabilities"] as? [String: Any])
    #expect(capabilities["events"] != nil)
    let response = try #require(await MCPEventsProbe.handleRequest(#"{"jsonrpc":"2.0","id":1,"method":"events/list","params":{}}"#, server: server))
    let data = try #require(response.data(using: .utf8))
    let rpc = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let result = try #require(rpc["result"] as? [String: Any])
    let events = try #require(result["events"] as? [[String: Any]])
    #expect(events.first?["name"] as? String == "playlist.finished")
    let payload = try #require(events.first?["payloadSchema"] as? [String: Any])
    #expect(payload["required"] as? [String] == ["playlist", "host", "recordedAt"])
  }

  @Test("invalid subscription input is rejected before callback verification")
  func rejectsInvalidSubscription() async throws {
    let server = LibraryMCPServer.make(snapshotURL: URL(fileURLWithPath: "/tmp/missing-snapshot.json"))
    let response = try #require(await MCPEventsProbe.handleRequest(#"{"jsonrpc":"2.0","id":2,"method":"events/subscribe","params":{"name":"playlist.finished","arguments":{},"delivery":{"mode":"webhook","url":"https://example.com/callback","secret":"bad"}}}"#, server: server))
    #expect(response.contains("-32602"))
  }
}
