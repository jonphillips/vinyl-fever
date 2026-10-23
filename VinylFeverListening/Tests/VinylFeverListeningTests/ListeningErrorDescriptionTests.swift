import Foundation
import Testing
import VinylFeverListening

@Suite("Listening error descriptions")
struct ListeningErrorDescriptionTests {
  @Test("includes Cocoa file details and the underlying POSIX error")
  func describesFileError() {
    let path = "/Users/test/Library/Listening/fetches.jsonl"
    let error = CocoaError(.fileWriteUnknown, userInfo: [
      NSFilePathErrorKey: path,
      NSUnderlyingErrorKey: POSIXError(.EPERM),
    ])

    let description = ListeningErrorDescription.describe(error)

    #expect(description.contains(error.localizedDescription))
    #expect(description.contains("NSCocoaErrorDomain 512"))
    #expect(description.contains(path))
    #expect(description.contains("NSPOSIXErrorDomain 1"))
  }

  @Test("leaves plain Swift errors at their description")
  func describesPlainSwiftError() {
    let error = PlainListeningError()
    #expect(ListeningErrorDescription.describe(error) == error.localizedDescription)
  }
}

private struct PlainListeningError: Error, LocalizedError {
  var errorDescription: String? { "A plain Swift error." }
}
