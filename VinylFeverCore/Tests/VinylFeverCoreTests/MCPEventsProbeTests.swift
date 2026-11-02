import Foundation
import MCPServerKit
import Testing
import VinylFeverCore
import VinylFeverNotes

struct MCPEventsProbeTests {
  private let secret = "whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw"
  private let instant = Date(timeIntervalSince1970: 1_800_000_000)

  @Test("event support stays disabled unless explicitly enabled")
  func optInGate() {
    #expect(!MCPEventsProbe.isEnabled(environment: [:]))
    #expect(!MCPEventsProbe.isEnabled(environment: ["VF_MCP_EVENTS_PROBE": "0"]))
    #expect(MCPEventsProbe.isEnabled(environment: ["VF_MCP_EVENTS_PROBE": "1"]))
  }

  @Test("subscription secrets require the Standard Webhooks prefix and key length")
  func validatesSecret() {
    #expect(MCPEventsProbe.validSigningSecret(secret))
    #expect(!MCPEventsProbe.validSigningSecret("wrong_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw"))
    #expect(!MCPEventsProbe.validSigningSecret("whsec_YWJj"))
  }

  @Test("Standard Webhooks published HMAC test vector")
  func standardWebhookVector() throws {
    let signature = try #require(MCPEventsProbe.standardSignature(
      secret: secret,
      id: "msg_p5jXN8AQM9LWM0D4loKWxJek",
      timestamp: "1614265330",
      body: Data(#"{"test": 2432232314}"#.utf8)
    ))
    #expect(signature == "v1,g0hM9SsE+OTPJTGt/tmIKtSyZlE3uFJELVlNIOLJ1OE=")
  }

  @Test("event catalog advertises the finished playlist payload and logs listing")
  func eventCatalogAndLog() async throws {
    let sandbox = try Sandbox()
    let dependencies = sandbox.dependencies { _ in .init(statusCode: 204) }
    let server = LibraryMCPServer.make(snapshotURL: URL(fileURLWithPath: "/tmp/missing-snapshot.json"))
    let discovery = try #require(await MCPEventsProbe.handleRequest(
      #"{"jsonrpc":"2.0","id":0,"method":"server/discover"}"#, server: server, dependencies: dependencies))
    let discoveryRPC = try #require(JSONSerialization.jsonObject(with: Data(discovery.utf8)) as? [String: Any])
    let discoveryResult = try #require(discoveryRPC["result"] as? [String: Any])
    let capabilities = try #require(discoveryResult["capabilities"] as? [String: Any])
    #expect(capabilities["events"] != nil)
    let response = try #require(await MCPEventsProbe.handleRequest(
      #"{"jsonrpc":"2.0","id":1,"method":"events/list","params":{}}"#, server: server,
      dependencies: dependencies))
    let rpc = try #require(JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any])
    let result = try #require(rpc["result"] as? [String: Any])
    let events = try #require(result["events"] as? [[String: Any]])
    #expect(events.first?["name"] as? String == "playlist.finished")
    let payload = try #require(events.first?["payloadSchema"] as? [String: Any])
    #expect(payload["required"] as? [String] == ["playlist", "host", "recordedAt"])
    #expect(try sandbox.logLines().last?["method"] as? String == "events/list")
  }

  @Test("successful subscribe signs verification, stores once, and refresh reuses the id")
  func successfulSubscribeAndRefresh() async throws {
    let sandbox = try Sandbox()
    let sender = EchoingSender()
    let dependencies = sandbox.dependencies { request in await sender.send(request) }
    let server = LibraryMCPServer.make(snapshotURL: URL(fileURLWithPath: "/tmp/missing-snapshot.json"))

    let first = try #require(await MCPEventsProbe.handleRequest(subscribeRequest(id: 1), server: server,
      dependencies: dependencies))
    let firstResult = try rpcResult(first)
    let firstID = try #require(firstResult["id"] as? String)
    let requestsAfterFirst = await sender.requests()
    #expect(requestsAfterFirst.count == 1)
    let verification = try #require(JSONSerialization.jsonObject(with: requestsAfterFirst[0].body) as? [String: String])
    #expect(verification["type"] == "verification")
    #expect(requestsAfterFirst[0].subscriptionID == firstID)
    #expect(requestsAfterFirst[0].webhookSignature == MCPEventsProbe.standardSignature(
      secret: secret, id: requestsAfterFirst[0].webhookID,
      timestamp: requestsAfterFirst[0].webhookTimestamp, body: requestsAfterFirst[0].body))
    #expect(try sandbox.savedSubscriptions().count == 1)

    let second = try #require(await MCPEventsProbe.handleRequest(subscribeRequest(id: 2), server: server,
      dependencies: dependencies))
    #expect(try rpcResult(second)["id"] as? String == firstID)
    #expect(try sandbox.savedSubscriptions().count == 1)
    #expect(await sender.requests().count == 2)
    let log = try sandbox.logLines()
    #expect(log.filter { $0["method"] as? String == "events/subscribe" }.count == 2)
    #expect(log.last?["callbackHost"] as? String == "callback.example")
    #expect(log.last?["subscriptionID"] as? String == firstID)
    #expect(log.last?["outcome"] as? String == "subscribed")
  }

  @Test("callback failures distinguish unreachable from timeout and bad challenges")
  func callbackFailureReasons() async throws {
    let sandbox = try Sandbox()
    let server = LibraryMCPServer.make(snapshotURL: URL(fileURLWithPath: "/tmp/missing-snapshot.json"))
    let unreachable = sandbox.dependencies { _ in throw URLError(.cannotFindHost) }
    let unreachableResponse = try #require(await MCPEventsProbe.handleRequest(subscribeRequest(id: 1), server: server,
      dependencies: unreachable))
    #expect(try rpcErrorData(unreachableResponse)["reason"] as? String == "unreachable")

    let timeout = sandbox.dependencies { _ in throw URLError(.timedOut) }
    let timeoutResponse = try #require(await MCPEventsProbe.handleRequest(subscribeRequest(id: 2), server: server,
      dependencies: timeout))
    #expect(try rpcErrorData(timeoutResponse)["reason"] as? String == "timeout")

    let wrongEcho = sandbox.dependencies { _ in .init(statusCode: 200, data: Data(#"{"challenge":"wrong"}"#.utf8)) }
    let wrongEchoResponse = try #require(await MCPEventsProbe.handleRequest(subscribeRequest(id: 3), server: server,
      dependencies: wrongEcho))
    #expect(try rpcErrorData(wrongEchoResponse)["reason"] as? String == "challenge_failed")
    let rejected = sandbox.dependencies { _ in .init(statusCode: 503, data: Data(#"{"challenge":"ignored"}"#.utf8)) }
    let rejectedResponse = try #require(await MCPEventsProbe.handleRequest(subscribeRequest(id: 4), server: server,
      dependencies: rejected))
    #expect(try rpcErrorData(rejectedResponse)["reason"] as? String == "challenge_failed")
    #expect(try sandbox.savedSubscriptions().isEmpty)
    let log = try sandbox.logLines()
    #expect(log.contains { $0["outcome"] as? String == "unreachable" })
    #expect(log.contains { $0["outcome"] as? String == "timeout" })
    #expect(log.contains { $0["outcome"] as? String == "challenge_failed" && $0["httpStatus"] as? Int == 200 })
    #expect(log.contains { $0["outcome"] as? String == "challenge_failed" && $0["httpStatus"] as? Int == 503 })
  }

  @Test("subscription storage failures return internal errors")
  func subscriptionStorageFailure() async throws {
    let sandbox = try Sandbox()
    try Data("not a directory".utf8).write(to: sandbox.subscriptionsFolder)
    let dependencies = sandbox.dependencies { request in await EchoingSender().send(request) }
    let server = LibraryMCPServer.make(snapshotURL: URL(fileURLWithPath: "/tmp/missing-snapshot.json"))
    let response = try #require(await MCPEventsProbe.handleRequest(subscribeRequest(id: 1), server: server,
      dependencies: dependencies))
    let rpc = try rpcObject(response)
    #expect((rpc["error"] as? [String: Any])?["code"] as? Int == -32603)
  }

  @Test("invalid subscription input is rejected before callback verification")
  func rejectsInvalidSubscription() async throws {
    let sandbox = try Sandbox()
    let sender = EchoingSender()
    let dependencies = sandbox.dependencies { request in await sender.send(request) }
    let server = LibraryMCPServer.make(snapshotURL: URL(fileURLWithPath: "/tmp/missing-snapshot.json"))
    let request = #"{"jsonrpc":"2.0","id":2,"method":"events/subscribe","params":{"name":"playlist.finished","arguments":{},"delivery":{"mode":"webhook","url":"https://callback.example/callback","secret":"bad"}}}"#
    let response = try #require(await MCPEventsProbe.handleRequest(request, server: server, dependencies: dependencies))
    #expect(response.contains("-32602"))
    #expect(await sender.requests().isEmpty)
  }

  @Test("unsubscribe removes the subscription and repeated unsubscribe succeeds")
  func unsubscribeIsIdempotent() async throws {
    let sandbox = try Sandbox()
    let sender = EchoingSender()
    let dependencies = sandbox.dependencies { request in await sender.send(request) }
    let server = LibraryMCPServer.make(snapshotURL: URL(fileURLWithPath: "/tmp/missing-snapshot.json"))
    let subscribed = try #require(await MCPEventsProbe.handleRequest(subscribeRequest(id: 1), server: server,
      dependencies: dependencies))
    let subscriptionID = try #require(try rpcResult(subscribed)["id"] as? String)
    let unsubscribe = #"{"jsonrpc":"2.0","id":3,"method":"events/unsubscribe","params":{"name":"playlist.finished","delivery":{"url":"https://callback.example/callback"}}}"#
    let first = try #require(await MCPEventsProbe.handleRequest(unsubscribe, server: server, dependencies: dependencies))
    #expect(try rpcResult(first).isEmpty)
    #expect(try sandbox.savedSubscriptions().isEmpty)
    let second = try #require(await MCPEventsProbe.handleRequest(unsubscribe, server: server, dependencies: dependencies))
    #expect(try rpcResult(second).isEmpty)
    let log = try sandbox.logLines()
    #expect(log.contains { $0["method"] as? String == "events/unsubscribe" && $0["outcome"] as? String == "unsubscribed" })
    #expect(log.contains { $0["method"] as? String == "events/unsubscribe" && $0["outcome"] as? String == "already_absent" })
    #expect(log.contains { $0["subscriptionID"] as? String == subscriptionID })
  }

  @Test("fire reads coordinated finished state, skips expired subscriptions, and logs delivery")
  func fireNewestFinished() async throws {
    let sandbox = try Sandbox()
    let reviewFolder = sandbox.tasteRootURL.appending(path: "playlist-reviews", directoryHint: .isDirectory)
    try PlaylistReviewsCodec.append(review(source: .jon, kind: .finished, id: "one", playlist: "First", at: 1),
      writer: "device", folder: reviewFolder)
    try PlaylistReviewsCodec.append(review(source: .jon, kind: .finished, id: "two", playlist: "Second", at: 2),
      writer: "device", folder: reviewFolder)
    try PlaylistReviewsCodec.append(review(source: .jon, kind: .reopened, id: "two", playlist: "Second", at: 3),
      writer: "device", folder: reviewFolder)
    try PlaylistReviewsCodec.append(review(source: .jon, kind: .finished, id: "three", playlist: "Third", at: 4),
      writer: "device", folder: reviewFolder)
    try writeFixtureSubscriptions([
      FixtureSubscription(id: "active", name: "playlist.finished", url: URL(string: "https://callback.example/active")!,
        secret: secret, expiresAt: instant.addingTimeInterval(60)),
      FixtureSubscription(id: "expired", name: "playlist.finished", url: URL(string: "https://callback.example/expired")!,
        secret: secret, expiresAt: instant.addingTimeInterval(-60))
    ], to: sandbox.subscriptionsFolder)

    let sender = EchoingSender()
    let dependencies = sandbox.dependencies { request in await sender.send(request) }
    await MCPEventsProbe.fireNewestFinished(dependencies: dependencies)
    let requests = await sender.requests()
    #expect(requests.count == 1)
    #expect(requests[0].subscriptionID == "active")
    #expect(requests[0].webhookID == ((try JSONSerialization.jsonObject(with: requests[0].body) as? [String: Any])?["eventId"] as? String))
    let event = try #require(JSONSerialization.jsonObject(with: requests[0].body) as? [String: Any])
    let payload = try #require(event["data"] as? [String: Any])
    #expect(payload["playlist"] as? String == "Third")
    #expect(payload["host"] as? String == "device")
    #expect(try sandbox.logLines().contains {
      $0["method"] as? String == "--probe-fire" && $0["subscriptionID"] as? String == "active" &&
        $0["outcome"] as? String == "delivered" && $0["httpStatus"] as? Int == 200
    })
  }

  private func subscribeRequest(id: Int) -> String {
    #"{"jsonrpc":"2.0","id":\#(id),"method":"events/subscribe","params":{"name":"playlist.finished","arguments":{},"delivery":{"mode":"webhook","url":"https://callback.example/callback","secret":"\#(secret)"}}}"#
  }

  private func review(source: PlaylistReviewSource, kind: PlaylistReviewKind, id: String, playlist: String,
    at offset: TimeInterval) -> PlaylistReviewEntry {
    PlaylistReviewEntry(source: source, kind: kind, host: "device", recordedAt: instant,
      playlistID: id, playlist: playlist, at: instant.addingTimeInterval(offset), device: "iPhone")
  }

  private func rpcObject(_ response: String) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any])
  }

  private func rpcResult(_ response: String) throws -> [String: Any] {
    try #require(try rpcObject(response)["result"] as? [String: Any])
  }

  private func rpcErrorData(_ response: String) throws -> [String: Any] {
    let rpc = try rpcObject(response)
    let error = try #require(rpc["error"] as? [String: Any])
    return try #require(error["data"] as? [String: Any])
  }
}

private actor EchoingSender {
  private var captured: [MCPEventsProbe.DeliveryRequest] = []
  func requests() -> [MCPEventsProbe.DeliveryRequest] { captured }
  func send(_ request: MCPEventsProbe.DeliveryRequest) -> MCPEventsProbe.DeliveryResponse {
    captured.append(request)
    if let body = try? JSONSerialization.jsonObject(with: request.body) as? [String: String],
      let challenge = body["challenge"] {
      return .init(statusCode: 200, data: Data(#"{"challenge":"\#(challenge)"}"#.utf8))
    }
    return .init(statusCode: 200, data: Data())
  }
}

private struct FixtureSubscription: Encodable {
  var id: String
  var name: String
  var url: URL
  var secret: String
  var expiresAt: Date
}

private struct Sandbox {
  let root: URL
  let subscriptionsFolder: URL
  let tasteRootURL: URL
  let now: Date

  init() throws {
    root = FileManager.default.temporaryDirectory.appending(path: "mcp-events-\(UUID().uuidString)", directoryHint: .isDirectory)
    subscriptionsFolder = root.appending(path: "EventSubscriptions", directoryHint: .isDirectory)
    tasteRootURL = root.appending(path: "Taste Intelligence", directoryHint: .isDirectory)
    now = Date(timeIntervalSince1970: 1_800_000_000)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  func dependencies(send: @escaping @Sendable (MCPEventsProbe.DeliveryRequest) async throws -> MCPEventsProbe.DeliveryResponse) -> MCPEventsProbe.Dependencies {
    MCPEventsProbe.Dependencies(subscriptionsFolder: subscriptionsFolder, tasteRootURL: tasteRootURL,
      now: { now }, send: send)
  }

  func savedSubscriptions() throws -> [[String: Any]] {
    let url = subscriptionsFolder.appending(path: "subscriptions.json")
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
  }

  func logLines() throws -> [[String: Any]] {
    let url = subscriptionsFolder.appending(path: "probe.log")
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map {
      try #require(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
    }
  }
}

private func writeFixtureSubscriptions(_ values: [FixtureSubscription], to folder: URL) throws {
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  let data = try JSONEncoder().encode(values)
  try data.write(to: folder.appending(path: "subscriptions.json"))
}
