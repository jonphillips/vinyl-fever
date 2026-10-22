import Foundation
import Testing
import VinylFeverCore

@Suite("Installed build check")
struct InstalledBuildCheckTests {
  @Test("current, missing, newer, tolerance and stale installed-copy cases")
  func resultCases() {
    let running = URL(fileURLWithPath: "/tmp/VinylFever-copy.app")
    let installed = URL(fileURLWithPath: "/Applications/VinylFever.app")
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(InstalledBuildCheck.result(runningBundleURL: installed, runningBuildDate: now, installedBundleURL: installed, installedBuildDate: now) == .current)
    #expect(InstalledBuildCheck.result(runningBundleURL: running, runningBuildDate: now, installedBundleURL: nil, installedBuildDate: nil) == .current)
    #expect(InstalledBuildCheck.result(runningBundleURL: running, runningBuildDate: now.addingTimeInterval(1), installedBundleURL: installed, installedBuildDate: now) == .current)
    #expect(InstalledBuildCheck.result(runningBundleURL: running, runningBuildDate: now.addingTimeInterval(-60), installedBundleURL: installed, installedBuildDate: now) == .current)
    #expect(InstalledBuildCheck.result(runningBundleURL: running, runningBuildDate: now.addingTimeInterval(-61), installedBundleURL: installed, installedBuildDate: now) == .olderThanInstalled(installedDate: now))
  }

  @Test("build date is the newest file modification time in Contents/MacOS")
  func buildDateUsesNewestExecutableFile() throws {
    let bundle = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let executableDirectory = bundle.appending(path: "Contents/MacOS", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: executableDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: bundle) }

    let olderDate = Date(timeIntervalSince1970: 1_700_000_000)
    let newerDate = Date(timeIntervalSince1970: 1_700_000_100)
    let first = executableDirectory.appending(path: "VinylFever")
    let second = executableDirectory.appending(path: "VinylFever.debug.dylib")
    try Data().write(to: first)
    try Data().write(to: second)
    try FileManager.default.setAttributes([.modificationDate: olderDate], ofItemAtPath: first.path)
    try FileManager.default.setAttributes([.modificationDate: newerDate], ofItemAtPath: second.path)

    #expect(InstalledBuildCheck.buildDate(in: bundle) == newerDate)
  }

  @Test("missing Contents/MacOS has no build date")
  func missingExecutableDirectoryHasNoDate() throws {
    let bundle = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: bundle) }
    #expect(InstalledBuildCheck.buildDate(in: bundle) == nil)
  }
}
