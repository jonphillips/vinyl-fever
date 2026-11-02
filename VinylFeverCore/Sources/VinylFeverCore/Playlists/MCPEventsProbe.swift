import CryptoKit
import Foundation
import MCPServerKit
import VinylFeverNotes

/// Deliberately opt-in MCP Events probe. The helper delegates here so the
/// ordinary MCPServerKit protocol and the unconfigured helper stay unchanged.
public enum MCPEventsProbe {
  private static let eventName = "playlist.finished"
  private static let subscriptionsURL = FileManager.default.homeDirectoryForCurrentUser
    .appending(path: "Library/Application Support/VinylFever/EventSubscriptions", directoryHint: .isDirectory)
  private static let ttl: TimeInterval = 30 * 24 * 60 * 60

  private struct Subscription: Codable {
    var id: String
    var name: String
    var url: URL
    var secret: String
    var expiresAt: Date
  }

  public static func isEnabled(environment: [String: String]) -> Bool { environment["VF_MCP_EVENTS_PROBE"] == "1" }

  public static func validSigningSecret(_ secret: String) -> Bool { validSecret(secret) }

  public static func standardSignature(secret: String, id: String, timestamp: String, body: Data) -> String? {
    guard validSecret(secret), let secretData = Data(base64Encoded: String(secret.dropFirst(6))) else { return nil }
    let signed = Data("\(id).\(timestamp).".utf8) + body
    let mac = HMAC<SHA256>.authenticationCode(for: signed, using: SymmetricKey(data: secretData))
    return "v1,\(Data(mac).base64EncodedString())"
  }

  public static func run(server: MCPServer, input: FileHandle = .standardInput, output: FileHandle = .standardOutput) async {
    do {
      var bytes = Data()
      for try await byte in input.bytes {
        if byte == 0x0A {
          let line = String(decoding: bytes, as: UTF8.self)
          bytes.removeAll(keepingCapacity: true)
          if let response = await handleRequest(line, server: server) {
            try output.write(contentsOf: Data((response + "\n").utf8))
          }
        } else { bytes.append(byte) }
      }
      if !bytes.isEmpty, let response = await handleRequest(String(decoding: bytes, as: UTF8.self), server: server) {
        try output.write(contentsOf: Data((response + "\n").utf8))
      }
    } catch { log("MCP Events probe stdio failed: \(error.localizedDescription)") }
  }

  public static func handleRequest(_ line: String, server: MCPServer) async -> String? {
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
      return rpcResult(id: id, result: ["events": [[
        "name": eventName,
        "description": "A playlist was marked Done listening in Vinyl Fever.",
        "delivery": ["webhook"],
        "inputSchema": ["type": "object", "properties": [String: Any](), "additionalProperties": false],
        "payloadSchema": ["type": "object", "properties": [
          "playlist": ["type": "string"], "host": ["type": "string"], "recordedAt": ["type": "string"]
        ], "required": ["playlist", "host", "recordedAt"], "additionalProperties": false]
      ]]])
    case "events/subscribe": return await subscribe(id: id, params: request["params"] as? [String: Any] ?? [:])
    case "events/unsubscribe": return unsubscribe(id: id, params: request["params"] as? [String: Any] ?? [:])
    default: return await server.handle(line: line)
    }
  }

  private static func subscribe(id: Any, params: [String: Any]) async -> String {
    guard params["name"] as? String == eventName,
      (params["arguments"] as? [String: Any] ?? [:]).isEmpty,
      let delivery = params["delivery"] as? [String: Any], delivery["mode"] as? String == "webhook",
      let urlText = delivery["url"] as? String, let url = URL(string: urlText), validCallback(url),
      let secret = delivery["secret"] as? String, validSecret(secret) else {
      return rpcError(id: id, code: -32602, message: "Invalid event subscription parameters")
    }
    let identity: [String: Any] = ["url": url.absoluteString, "name": eventName, "arguments": [String: Any]()]
    let identityBytes = (try? JSONSerialization.data(withJSONObject: identity, options: [.sortedKeys])) ?? Data()
    let subID = "sub_" + SHA256.hash(data: identityBytes).map { String(format: "%02x", $0) }.joined().prefix(32)
    do {
      let now = Date()
      var subscriptions = try readSubscriptions()
      let expiry = now.addingTimeInterval(ttl)
      let candidate = Subscription(id: subID, name: eventName, url: url, secret: secret, expiresAt: expiry)
      // Verify the destination before persisting or activating this subscription.
      let challenge = UUID().uuidString
      let body = try JSONSerialization.data(withJSONObject: ["type": "verification", "challenge": challenge], options: [.sortedKeys])
      let status = try await post(body: body, id: "msg_verification_\(UUID().uuidString)", subscription: candidate)
      guard (200..<300).contains(status.statusCode),
        let echoed = try? JSONSerialization.jsonObject(with: status.data) as? [String: String],
        constantTimeEqual(echoed["challenge"] ?? "", challenge) else {
        return rpcError(id: id, code: -32015, message: "CallbackEndpointError", data: ["reason": "challenge_failed"])
      }
      subscriptions.removeAll { $0.id == subID }
      subscriptions.append(candidate)
      try writeSubscriptions(subscriptions)
      return rpcResult(id: id, result: ["id": subID, "refreshBefore": iso8601(expiry), "cursor": NSNull(), "truncated": false])
    } catch {
      return rpcError(id: id, code: -32015, message: "CallbackEndpointError", data: ["reason": "timeout"])
    }
  }

  private static func unsubscribe(id: Any, params: [String: Any]) -> String {
    guard params["name"] as? String == eventName,
      let delivery = params["delivery"] as? [String: Any], let text = delivery["url"] as? String else {
      return rpcError(id: id, code: -32602, message: "Invalid event subscription parameters")
    }
    do {
      var subscriptions = try readSubscriptions()
      if let url = URL(string: text) { subscriptions.removeAll { $0.name == eventName && $0.url == url } }
      try writeSubscriptions(subscriptions)
      return rpcResult(id: id, result: [String: Any]())
    } catch { return rpcError(id: id, code: -32603, message: "Could not update subscriptions") }
  }

  public static func fireNewestFinished() async {
    let reviewFolder = FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "Library/Mobile Documents/com~apple~CloudDocs/Vinyl Fever/Taste Intelligence/playlist-reviews", directoryHint: .isDirectory)
    do {
      let files = try FileManager.default.contentsOfDirectory(at: reviewFolder, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "jsonl" }
      let result = PlaylistReviewsCodec.readFiles(try files.map { try Data(contentsOf: $0) })
      let states = PlaylistReviewsCodec.latestJonState(in: result.entries).values.filter { $0.kind == .finished }
      guard let newest = states.max(by: { $0.at < $1.at }) else { log("probe-fire: no finished playlist found"); return }
      let payload: [String: Any] = ["playlist": newest.playlist, "host": newest.host, "recordedAt": iso8601(newest.recordedAt)]
      let event: [String: Any] = ["eventId": "evt_\(UUID().uuidString)", "name": eventName,
        "timestamp": iso8601(newest.at), "data": payload, "cursor": NSNull()]
      let eventID = event["eventId"] as! String
      let body = try JSONSerialization.data(withJSONObject: event, options: [.sortedKeys])
      for subscription in try readSubscriptions() where subscription.expiresAt > Date() {
        do {
          let response = try await post(body: body, id: eventID, subscription: subscription)
          log("probe-fire \(subscription.id): HTTP \(response.statusCode) \(String(decoding: response.data, as: UTF8.self))")
        } catch { log("probe-fire \(subscription.id): \(error.localizedDescription)") }
      }
    } catch { log("probe-fire failed: \(error.localizedDescription)") }
  }

  private struct Response { var statusCode: Int; var data: Data }
  private static func post(body: Data, id: String, subscription: Subscription) async throws -> Response {
    let timestamp = String(Int(Date().timeIntervalSince1970))
    guard validSecret(subscription.secret) else { throw ProbeError.invalidSecret }
    let signature = standardSignature(secret: subscription.secret, id: id, timestamp: timestamp, body: body)!.dropFirst(3)
    var request = URLRequest(url: subscription.url, timeoutInterval: 10)
    request.httpMethod = "POST"
    request.httpBody = body
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(id, forHTTPHeaderField: "webhook-id")
    request.setValue(timestamp, forHTTPHeaderField: "webhook-timestamp")
    request.setValue("v1,\(signature)", forHTTPHeaderField: "webhook-signature")
    request.setValue(subscription.id, forHTTPHeaderField: "X-MCP-Subscription-Id")
    let (data, response) = try await URLSession(configuration: .ephemeral, delegate: RedirectBlocker(), delegateQueue: nil).data(for: request)
    return Response(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
  }

  private static func readSubscriptions() throws -> [Subscription] {
    guard FileManager.default.fileExists(atPath: subscriptionsURL.path) else { return [] }
    return try JSONDecoder().decode([Subscription].self, from: Data(contentsOf: subscriptionsURL))
  }
  private static func writeSubscriptions(_ values: [Subscription]) throws {
    try FileManager.default.createDirectory(at: subscriptionsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try JSONEncoder().encode(values)
    try data.write(to: subscriptionsURL, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: subscriptionsURL.path)
  }
  private static func validSecret(_ secret: String) -> Bool {
    guard secret.hasPrefix("whsec_"), let bytes = Data(base64Encoded: String(secret.dropFirst(6))) else { return false }
    return (24...64).contains(bytes.count)
  }
  private static func validCallback(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
      !host.isEmpty, host != "localhost", !host.hasSuffix(".local"), !host.hasSuffix(".internal") else { return false }
    // Reject address literals. ChatGPT's callback is a public hostname, and
    // literals could bypass hostname-level checks (especially IPv6 loopback).
    guard !host.contains(":"), IPv4Address(host) == nil else { return false }
    return true
  }
  private static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
    let a = Array(lhs.utf8), b = Array(rhs.utf8)
    var diff = UInt8(truncatingIfNeeded: a.count ^ b.count)
    for index in 0..<max(a.count, b.count) { diff |= (index < a.count ? a[index] : 0) ^ (index < b.count ? b[index] : 0) }
    return diff == 0
  }
  private static func iso8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }
  private static func encode(_ value: Any) -> String { guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys]) else { return "{}" }; return String(decoding: data, as: UTF8.self) }
  private static func rpcResult(id: Any, result: [String: Any]) -> String { encode(["jsonrpc": "2.0", "id": id, "result": result]) }
  private static func rpcError(id: Any, code: Int, message: String, data: [String: Any]? = nil) -> String {
    var error: [String: Any] = ["code": code, "message": message]; if let data { error["data"] = data }
    return encode(["jsonrpc": "2.0", "id": id, "error": error])
  }
  private static func log(_ text: String) { try? FileHandle.standardError.write(contentsOf: Data((text + "\n").utf8)) }
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
