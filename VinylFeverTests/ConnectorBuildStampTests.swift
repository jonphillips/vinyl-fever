import Foundation
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

  @Test("a symlinked helper launch resolves the containing app bundle")
  func resolvesSymlinkedHelperBundle() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let appURL = root.appending(path: "Fixture.app", directoryHint: .isDirectory)
    let helperDirectory = appURL.appending(path: "Contents/Helpers", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: helperDirectory, withIntermediateDirectories: true)
    let info: [String: String] = [
      "CFBundlePackageType": "APPL",
      "VFConnectorBuild": "abc1234",
      "VFConnectorDirty": "false",
      "VFConnectorBuiltAt": "2026-10-26T13:00:00Z",
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try data.write(to: appURL.appending(path: "Contents/Info.plist"))
    let helperURL = helperDirectory.appending(path: "vf-mcp")
    try Data().write(to: helperURL)
    let aliasURL = root.appending(path: "current-vf-mcp")
    try FileManager.default.createSymbolicLink(at: aliasURL, withDestinationURL: helperURL)

    let resolvedURL = aliasURL.resolvingSymlinksInPath().standardizedFileURL
    let infoURL = appURL.appending(path: "Contents/Info.plist")
    let readInfo = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoURL), options: [], format: nil) as? [String: Any]
    #expect(resolvedURL == helperURL.standardizedFileURL, "Resolved helper path: \(resolvedURL.path)")
    #expect(ConnectorBuildStamp.from(infoDictionary: readInfo ?? [:]).build == "abc1234")
    let hostBundleURL = root.appending(path: "Host.app", directoryHint: .isDirectory)
    let hostContents = hostBundleURL.appending(path: "Contents", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: hostContents, withIntermediateDirectories: true)
    let hostInfo = try PropertyListSerialization.data(
      fromPropertyList: ["CFBundlePackageType": "APPL"], format: .xml, options: 0)
    try hostInfo.write(to: hostContents.appending(path: "Info.plist"))
    let hostBundle = try #require(Bundle(url: hostBundleURL))
    let stamp = ConnectorBuildStamp.fromMainAppBundle(mainBundle: hostBundle, executableURL: aliasURL)
    #expect(stamp.build == "abc1234", "Resolved helper path: \(resolvedURL.path); stamp: \(stamp)")
  }
}
