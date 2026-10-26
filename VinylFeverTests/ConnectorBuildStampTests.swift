import Testing
import VinylFeverCore

@testable import VinylFever

struct ConnectorBuildStampTests {
  @Test("Settings can show a known and an unknown connector build")
  func settingsDisplayValue() {
    let stamp = ConnectorBuildStamp.from(infoDictionary: [
      "VFConnectorBuild": "c8fa5db",
      "VFConnectorDirty": "false",
      "VFConnectorBuiltAt": "2026-10-26T13:00:00Z",
    ])
    #expect(stamp.displayValue == "c8fa5db · clean · 2026-10-26T13:00:00Z")
    #expect(ConnectorBuildStamp.from(infoDictionary: [:]).displayValue == "unknown")
  }
}
