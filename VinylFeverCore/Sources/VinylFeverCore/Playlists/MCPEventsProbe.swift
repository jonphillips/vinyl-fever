import CryptoKit
import Foundation
import MCPServerKit
import VinylFeverNotes

/// Deliberately opt-in MCP Events probe. The helper delegates here so the
/// ordinary MCPServerKit protocol and the unconfigured helper stay unchanged.
public enum MCPEventsProbe {
  private static let eventName = "playlist.finished"
  private static let ttl: TimeInterval = 30 * 24 * 60 * 60

  public struct DeliveryRequest: Sendable {
    public var url: URL
    public var body: Data
    public var webhookID: String
    public var webhookTimestamp: String
    public var webhookSignature: String
    public var subscriptionID: String
  }

  public struct DeliveryResponse: Sendable {
    public var statusCode: Int
    public var data: Data
    public init(statusCode: Int, data: Data = Data()) {
      self.statusCode = statusCode
      self.data = data
    }
  }

  public struct Dependencies: Sendable {
    public var subscriptionsFolder: URL
    public var tasteRootURL: URL
    public var now: @Sendable () -> Date
    public var send: @Sendable (DeliveryRequest) async throws -> DeliveryResponse

    public init(subscriptionsFolder: URL, tasteRootURL: URL,
      now: @escaping @Sendable () -> Date,
      send: @escaping @Sendable (DeliveryRequest) async throws -> DeliveryResponse) {
      self.subscriptionsFolder = subscriptionsFolder
      self.tasteRootURL = tasteRootURL
      self.now = now
      self.send = send
    }

    public static var live: Self {
      Self(
        subscriptionsFolder: FileManager.default.homeDirectoryForCurrentUser
          .appending(path: "Library/Application Support/VinylFever/EventSubscriptions", directoryHint: .isDirectory),
        tasteRootURL: LibraryMCPServer.defaultTasteRootURL,
        now: { Date() },
        send: { try await MCPEventsProbe.sendLive($0) }
      )
    }
  }

  private struct Subscription: Codable {
    var id: String
    var name: String
    var url: URL
    var secret: String
    var expiresAt: Date
  }

  private struct LogEntry: Encodable {
    var at: String
    var method: String
    var callbackHost: String?
    var subscriptionID: String?
    var outcome: String
    var httpStatus: Int?
  }

  public static func isEnabled(environment: [String: String]) -> Bool { environment["VF_MCP_EVENTS_PROBE"] == "1" }

  public static func validSigningSecret(_ secret: String) -> Bool { validSecret(secret) }

  public static func standardSignature(secret: String, id: String, timestamp: String, body: Data) -> String? {
    guard validSecret(secret), let secretData = Data(base64Encoded: String(secret.dropFirst(6))) else { return nil }
    let signed = Data("\(id).\(timestamp).".utf8) + body
    let mac = HMAC<SHA256>.authenticationCode(for: signed, using: SymmetricKey(data: secretData))
    return "v1,\(Data(mac).base64EncodedString())"
  }

  public static func run(server: MCPServer, input: FileHandle = .standardInput, output: FileHandle = .standardOutput,
    dependencies: Dependencies = .live) async {
    do {
      var bytes = Data()
      for try await byte in input.bytes {
        if byte == 0x0A {
          let line = String(decoding: bytes, as: UTF8.self)
          bytes.removeAll(keepingCapacity: true)
          if let response = await handleRequest(line, server: server, dependencies: dependencies) {
            try output.write(contentsOf: Data((response + "\n").utf8))
          }
        } else { bytes.append(byte) }
      }
      if !bytes.isEmpty, let response = await handleRequest(String(decoding: bytes, as: UTF8.self), server: server,
        dependencies: dependencies) {
        try output.write(contentsOf: Data((response + "\n").utf8))
      }
    } catch { logStderr("MCP Events probe stdio failed: \(error.localizedDescription)") }
  }

  public static func handleRequest(_ line: String, server: MCPServer,
    dependencies: Dependencies = .live) async -> String? {
    guard let data = line.data(using: .utf8),
      let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let method = request["method"] as? String else { return await server.handle(line: line) }
    let id = request["id"] ?? NSNull()
    guard request["id"] != nil else { return await server.handle(line: line) }
    if method == "initialize" {
      guard let response = await server.handle(line: line),
        let responseData = response.data(using: .utf8),
        var rpc = (try? JSONSerialization.jsonObject(with: responseData)) as? [String: Any],
        var result = rpc["result"] as? [String: Any],
        var capabilities = result["capabilities"] as? [String: Any] else { return await server.handle(line: line) }
      capabilities["events"] = [String: Any]()
      result["capabilities"] = capabilities
      rpc["result"] = result
      return encode(rpc)
    }
    switch method {
    case "server/discover":
      return rpcResult(id: id, result: ["resultType": "complete", "supportedVersions": ["2026-07-28"],
        "capabilities": ["tools": [String: Any](), "events": [String: Any]()]] as [String: Any])
    case "events/list":
      appendLog(method: method, dependencies: dependencies, outcome: "listed")
      return rpcResult(id: id, result: ["events": [[
        "name": eventName,
        "description": "A playlist was marked Done listening in Vinyl Fever.",
        "delivery": ["webhook"],
        "inputSchema": ["type": "object", "properties": [String: Any](), "additionalProperties": false],
        "payloadSchema": ["type": "object", "properties": [
          "playlist": ["type": "string"], "host": ["type": "string"], "recordedAt": ["type": "string"]
        ], "required": ["playlist", "host", "recordedAt"], "additionalProperties": false]
      ]]])
    case "events/subscribe":
      return await subscribe(id: id, params: request["params"] as? [String: Any] ?? [:], dependencies: dependencies)
    case "events/unsubscribe":
      return unsubscribe(id: id, params: request["params"] as? [String: Any] ?? [:], dependencies: dependencies)
    default:
      return await server.handle(line: line)
    }
  }

  public static func fireNewestFinished(dependencies: Dependencies = .live) async {
    let newest: PlaylistReviewEntry?
    do {
      newest = try await LibraryMCPServer.newestFinishedPlaylist(tasteRootURL: dependencies.tasteRootURL)
    } catch {
      appendLog(method: "--probe-fire", dependencies: dependencies, outcome: "taste_read_error: \(error.localizedDescription)")
      logStderr("probe-fire failed to read playlist reviews: \(error.localizedDescription)")
      return
    }
    guard let newest else {
      appendLog(method: "--probe-fire", dependencies: dependencies, outcome: "no_finished_playlist")
      logStderr("probe-fire: no finished playlist found")
      return
    }
    let subscriptions: [Subscription]
    do {
      subscriptions = try readSubscriptions(in: dependencies.subscriptionsFolder)
    } catch {
      appendLog(method: "--probe-fire", dependencies: dependencies, outcome: "subscription_read_error: \(error.localizedDescription)")
      logStderr("probe-fire failed to read subscriptions: \(error.localizedDescription)")
      return
    }
    guard !subscriptions.isEmpty else {
      appendLog(method: "--probe-fire", dependencies: dependencies, outcome: "no_subscriptions")
      logStderr("probe-fire: no subscriptions found")
      return
    }

    let eventID = "evt_\(UUID().uuidString)"
    let event: [String: Any] = ["eventId": eventID, "name": eventName,
      "timestamp": iso8601(newest.at),
      "data": ["playlist": newest.playlist, "host": newest.host, "recordedAt": iso8601(newest.recordedAt)],
      "cursor": NSNull()]
    guard let body = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]) else {
      appendLog(method: "--probe-fire", dependencies: dependencies, subscriptionID: nil, outcome: "event_encode_error")
      logStderr("probe-fire failed to encode event")
      return
    }
    for subscription in subscriptions where subscription.expiresAt > dependencies.now() {
      do {
        let request = try makeDeliveryRequest(body: body, id: eventID, subscription: subscription, now: dependencies.now())
        let response = try await dependencies.send(request)
        let outcome = (200..<300).contains(response.statusCode) ? "delivered" : "delivery_rejected"
        appendLog(method: "--probe-fire", dependencies: dependencies, callbackHost: subscription.url.host,
          subscriptionID: subscription.id, outcome: outcome, httpStatus: response.statusCode)
        logStderr("probe-fire \(subscription.id): HTTP \(response.statusCode) \(String(decoding: response.data, as: UTF8.self))")
      } catch {
        let outcome = urlErrorCategory(error) ?? "delivery_error: \(error.localizedDescription)"
        appendLog(method: "--probe-fire", dependencies: dependencies, callbackHost: subscription.url.host,
          subscriptionID: subscription.id, outcome: outcome)
        logStderr("probe-fire \(subscription.id): \(error.localizedDescription)")
      }
    }
  }

  private static func subscribe(id: Any, params: [String: Any], dependencies: Dependencies) async -> String {
    let delivery = params["delivery"] as? [String: Any] ?? [:]
    let urlText = delivery["url"] as? String
    let url = urlText.flatMap(URL.init(string:))
    let callbackHost = url?.host
    guard params["name"] as? String == eventName,
      (params["arguments"] as? [String: Any] ?? [:]).isEmpty,
      delivery["mode"] as? String == "webhook",
      let url, validCallback(url),
      let secret = delivery["secret"] as? String, validSecret(secret) else {
      appendLog(method: "events/subscribe", dependencies: dependencies, callbackHost: callbackHost, outcome: "invalid_parameters")
      return rpcError(id: id, code: -32602, message: "Invalid event subscription parameters")
    }
    let subID = subscriptionID(for: url)
    var subscriptions: [Subscription]
    do {
      subscriptions = try readSubscriptions(in: dependencies.subscriptionsFolder)
    } catch {
      appendLog(method: "events/subscribe", dependencies: dependencies, callbackHost: callbackHost,
        subscriptionID: String(subID), outcome: "subscription_read_error: \(error.localizedDescription)")
      return rpcError(id: id, code: -32603, message: "Could not read subscriptions")
    }

    let now = dependencies.now()
    let expiry = now.addingTimeInterval(ttl)
    let candidate = Subscription(id: String(subID), name: eventName, url: url, secret: secret, expiresAt: expiry)
    let challenge = UUID().uuidString
    guard let body = try? JSONSerialization.data(withJSONObject: ["type": "verification", "challenge": challenge], options: [.sortedKeys]) else {
      appendLog(method: "events/subscribe", dependencies: dependencies, callbackHost: callbackHost,
        subscriptionID: candidate.id, outcome: "challenge_encode_error")
      return rpcError(id: id, code: -32603, message: "Could not create callback challenge")
    }
    do {
      let request = try makeDeliveryRequest(body: body, id: "msg_verification_\(UUID().uuidString)",
        subscription: candidate, now: now)
      let response = try await dependencies.send(request)
      guard (200..<300).contains(response.statusCode),
        let echoed = try? JSONSerialization.jsonObject(with: response.data) as? [String: String],
        constantTimeEqual(echoed["challenge"] ?? "", challenge) else {
        appendLog(method: "events/subscribe", dependencies: dependencies, callbackHost: callbackHost,
          subscriptionID: candidate.id, outcome: "challenge_failed", httpStatus: response.statusCode)
        return rpcError(id: id, code: -32015, message: "CallbackEndpointError",
          data: ["reason": "challenge_failed"])
      }
    } catch {
      let reason = urlErrorCategory(error) ?? "unreachable"
      appendLog(method: "events/subscribe", dependencies: dependencies, callbackHost: callbackHost,
        subscriptionID: candidate.id, outcome: reason)
      return rpcError(id: id, code: -32015, message: "CallbackEndpointError", data: ["reason": reason])
    }

    subscriptions.removeAll { $0.id == candidate.id }
    subscriptions.append(candidate)
    do {
      try writeSubscriptions(subscriptions, in: dependencies.subscriptionsFolder)
    } catch {
      appendLog(method: "events/subscribe", dependencies: dependencies, callbackHost: callbackHost,
        subscriptionID: candidate.id, outcome: "subscription_write_error: \(error.localizedDescription)")
      return rpcError(id: id, code: -32603, message: "Could not save subscription")
    }
    appendLog(method: "events/subscribe", dependencies: dependencies, callbackHost: callbackHost,
      subscriptionID: candidate.id, outcome: "subscribed", httpStatus: 200)
    return rpcResult(id: id, result: ["id": candidate.id, "refreshBefore": iso8601(expiry), "cursor": NSNull(), "truncated": false])
  }

  private static func unsubscribe(id: Any, params: [String: Any], dependencies: Dependencies) -> String {
    guard params["name"] as? String == eventName,
      let delivery = params["delivery"] as? [String: Any], let text = delivery["url"] as? String else {
      appendLog(method: "events/unsubscribe", dependencies: dependencies, outcome: "invalid_parameters")
      return rpcError(id: id, code: -32602, message: "Invalid event subscription parameters")
    }
    do {
      var subscriptions = try readSubscriptions(in: dependencies.subscriptionsFolder)
      let before = subscriptions.count
      let url = URL(string: text)
      let removed = subscriptions.first { $0.name == eventName && $0.url == url }
      if let url { subscriptions.removeAll { $0.name == eventName && $0.url == url } }
      try writeSubscriptions(subscriptions, in: dependencies.subscriptionsFolder)
      appendLog(method: "events/unsubscribe", dependencies: dependencies, callbackHost: URL(string: text)?.host,
        subscriptionID: removed?.id ?? url.map(subscriptionID(for:)),
        outcome: subscriptions.count < before ? "unsubscribed" : "already_absent")
      return rpcResult(id: id, result: [String: Any]())
    } catch {
      appendLog(method: "events/unsubscribe", dependencies: dependencies, callbackHost: URL(string: text)?.host,
        outcome: "subscription_store_error: \(error.localizedDescription)")
      return rpcError(id: id, code: -32603, message: "Could not update subscriptions")
    }
  }

  private static func makeDeliveryRequest(body: Data, id: String, subscription: Subscription,
    now: Date) throws -> DeliveryRequest {
    let timestamp = String(Int(now.timeIntervalSince1970))
    guard let signature = standardSignature(secret: subscription.secret, id: id,
      timestamp: timestamp, body: body) else { throw ProbeError.invalidSecret }
    return DeliveryRequest(url: subscription.url, body: body, webhookID: id,
      webhookTimestamp: timestamp, webhookSignature: signature, subscriptionID: subscription.id)
  }

  private static func sendLive(_ delivery: DeliveryRequest) async throws -> DeliveryResponse {
    var request = URLRequest(url: delivery.url, timeoutInterval: 10)
    request.httpMethod = "POST"
    request.httpBody = delivery.body
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(delivery.webhookID, forHTTPHeaderField: "webhook-id")
    request.setValue(delivery.webhookTimestamp, forHTTPHeaderField: "webhook-timestamp")
    request.setValue(delivery.webhookSignature, forHTTPHeaderField: "webhook-signature")
    request.setValue(delivery.subscriptionID, forHTTPHeaderField: "X-MCP-Subscription-Id")
    let session = URLSession(configuration: .ephemeral, delegate: RedirectBlocker(), delegateQueue: nil)
    let (data, response) = try await session.data(for: request)
    return DeliveryResponse(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
  }

  private static func readSubscriptions(in folder: URL) throws -> [Subscription] {
    let file = folder.appending(path: "subscriptions.json")
    guard FileManager.default.fileExists(atPath: file.path) else { return [] }
    return try JSONDecoder().decode([Subscription].self, from: Data(contentsOf: file))
  }

  private static func writeSubscriptions(_ values: [Subscription], in folder: URL) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appending(path: "subscriptions.json")
    let data = try JSONEncoder().encode(values)
    try data.write(to: file, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
  }

  private static func appendLog(method: String, dependencies: Dependencies, callbackHost: String? = nil,
    subscriptionID: String? = nil, outcome: String, httpStatus: Int? = nil) {
    let entry = LogEntry(at: iso8601(dependencies.now()), method: method, callbackHost: callbackHost,
      subscriptionID: subscriptionID, outcome: outcome, httpStatus: httpStatus)
    guard var data = try? JSONEncoder().encode(entry) else { return }
    data.append(0x0A)
    let file = dependencies.subscriptionsFolder.appending(path: "probe.log")
    do {
      try FileManager.default.createDirectory(at: dependencies.subscriptionsFolder, withIntermediateDirectories: true)
      let coordinator = NSFileCoordinator(filePresenter: nil)
      var coordinationError: NSError?
      var writeError: Error?
      coordinator.coordinate(writingItemAt: file, options: .forMerging, error: &coordinationError) { target in
        do {
          if !FileManager.default.fileExists(atPath: target.path) {
            _ = FileManager.default.createFile(atPath: target.path, contents: nil)
          }
          let handle = try FileHandle(forWritingTo: target)
          defer { try? handle.close() }
          try handle.seekToEnd()
          try handle.write(contentsOf: data)
          try handle.synchronize()
        } catch { writeError = error }
      }
      if let coordinationError { throw coordinationError }
      if let writeError { throw writeError }
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    } catch { logStderr("MCP Events probe could not append probe.log: \(error.localizedDescription)") }
  }

  private static func validSecret(_ secret: String) -> Bool {
    guard secret.hasPrefix("whsec_"), let bytes = Data(base64Encoded: String(secret.dropFirst(6))) else { return false }
    return (24...64).contains(bytes.count)
  }

  private static func subscriptionID(for url: URL) -> String {
    let identity: [String: Any] = ["url": url.absoluteString, "name": eventName, "arguments": [String: Any]()]
    let identityBytes = (try? JSONSerialization.data(withJSONObject: identity, options: [.sortedKeys])) ?? Data()
    return "sub_" + SHA256.hash(data: identityBytes).map { String(format: "%02x", $0) }.joined().prefix(32)
  }

  private static func validCallback(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
      !host.isEmpty, host != "localhost", !host.hasSuffix(".local"), !host.hasSuffix(".internal") else { return false }
    guard !host.contains(":"), IPv4Address(host) == nil else { return false }
    return true
  }

  private static func urlErrorCategory(_ error: Error) -> String? {
    guard let urlError = error as? URLError else { return nil }
    return urlError.code == .timedOut ? "timeout" : "unreachable"
  }

  private static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
    let a = Array(lhs.utf8), b = Array(rhs.utf8)
    var diff = UInt8(truncatingIfNeeded: a.count ^ b.count)
    for index in 0..<max(a.count, b.count) { diff |= (index < a.count ? a[index] : 0) ^ (index < b.count ? b[index] : 0) }
    return diff == 0
  }

  private static func iso8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }

  private static func encode(_ value: Any) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys]) else { return "{}" }
    return String(decoding: data, as: UTF8.self)
  }

  private static func rpcResult(id: Any, result: [String: Any]) -> String {
    encode(["jsonrpc": "2.0", "id": id, "result": result])
  }

  private static func rpcError(id: Any, code: Int, message: String, data: [String: Any]? = nil) -> String {
    var error: [String: Any] = ["code": code, "message": message]
    if let data { error["data"] = data }
    return encode(["jsonrpc": "2.0", "id": id, "error": error])
  }

  private static func logStderr(_ text: String) {
    try? FileHandle.standardError.write(contentsOf: Data((text + "\n").utf8))
  }

  private enum ProbeError: Error { case invalidSecret }
}

private struct IPv4Address {
  init?(_ string: String) {
    let parts = string.split(separator: ".")
    guard parts.count == 4, parts.allSatisfy({ part in
      guard let value = Int(part), (0...255).contains(value) else { return false }
      return true
    }) else { return nil }
  }
}

private final class RedirectBlocker: NSObject, URLSessionTaskDelegate {
  func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
