import Dependencies
import Foundation

public struct PlaylistAlertClient: Sendable {
  public var phoneNumber: @Sendable () -> String
  public var savePhoneNumber: @Sendable (String) -> Void
  public var hasAttempted: @Sendable (String) -> Bool
  public var markAttempted: @Sendable (String) -> Void
  public var send: @Sendable (_ phoneNumber: String, _ message: String) async throws -> Void

  public init(
    phoneNumber: @escaping @Sendable () -> String,
    savePhoneNumber: @escaping @Sendable (String) -> Void,
    hasAttempted: @escaping @Sendable (String) -> Bool,
    markAttempted: @escaping @Sendable (String) -> Void,
    send: @escaping @Sendable (String, String) async throws -> Void
  ) {
    self.phoneNumber = phoneNumber
    self.savePhoneNumber = savePhoneNumber
    self.hasAttempted = hasAttempted
    self.markAttempted = markAttempted
    self.send = send
  }

  public static let liveValue: Self = {
    return Self(
      phoneNumber: { UserDefaults.standard.string(forKey: "playlist-alert-phone-number") ?? "" },
      savePhoneNumber: { UserDefaults.standard.set($0, forKey: "playlist-alert-phone-number") },
      hasAttempted: { (UserDefaults.standard.stringArray(forKey: "playlist-alert-attempts") ?? []).contains($0) },
      markAttempted: { key in
        var keys = UserDefaults.standard.stringArray(forKey: "playlist-alert-attempts") ?? []
        guard !keys.contains(key) else { return }
        keys.append(key)
        UserDefaults.standard.set(keys, forKey: "playlist-alert-attempts")
      },
      send: { phoneNumber, message in
        try await Task.detached {
          let process = Process()
          process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
          process.arguments = ["-", phoneNumber, message]
          let input = Pipe()
          let output = Pipe()
          process.standardInput = input
          process.standardError = output
          let script = """
          on run argv
            set targetHandle to item 1 of argv
            set messageText to item 2 of argv
            tell application "Messages"
              set targetService to first service whose service type is iMessage
              set targetBuddy to buddy targetHandle of targetService
              send messageText to targetBuddy
            end tell
          end run
          """
          try process.run()
          input.fileHandleForWriting.write(Data(script.utf8))
          try input.fileHandleForWriting.close()
          process.waitUntilExit()
          guard process.terminationStatus == 0 else {
            let detail = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw PlaylistAlertError.sendFailed(detail.isEmpty ? "Messages returned an error." : detail)
          }
        }.value
      }
    )
  }()
}

extension PlaylistAlertClient: TestDependencyKey, DependencyKey {
  public static let testValue = Self(
    phoneNumber: { "" }, savePhoneNumber: { _ in }, hasAttempted: { _ in false },
    markAttempted: { _ in }, send: { _, _ in }
  )
}

extension DependencyValues {
  public var playlistAlertClient: PlaylistAlertClient {
    get { self[PlaylistAlertClient.self] }
    set { self[PlaylistAlertClient.self] = newValue }
  }
}

private enum PlaylistAlertError: LocalizedError {
  case sendFailed(String)
  var errorDescription: String? {
    switch self {
    case let .sendFailed(message): message
    }
  }
}
