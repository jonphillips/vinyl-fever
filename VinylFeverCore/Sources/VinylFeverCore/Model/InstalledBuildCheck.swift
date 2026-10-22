import Foundation

public enum InstalledBuildCheck: Equatable, Sendable {
  case current
  case olderThanInstalled(installedDate: Date)

  public static func result(
    runningBundleURL: URL,
    runningBuildDate: Date?,
    installedBundleURL: URL?,
    installedBuildDate: Date?,
    tolerance: TimeInterval = 60
  ) -> Self {
    guard let installedBundleURL, let installedBuildDate,
      runningBundleURL.resolvingSymlinksInPath().standardizedFileURL
        != installedBundleURL.resolvingSymlinksInPath().standardizedFileURL,
      let runningBuildDate
    else { return .current }
    return runningBuildDate.addingTimeInterval(tolerance) < installedBuildDate
      ? .olderThanInstalled(installedDate: installedBuildDate)
      : .current
  }

  public static func buildDate(in bundleURL: URL) -> Date? {
    let executableDirectory = bundleURL.appending(path: "Contents/MacOS", directoryHint: .isDirectory)
    guard let files = try? FileManager.default.contentsOfDirectory(
      at: executableDirectory, includingPropertiesForKeys: [.contentModificationDateKey])
    else { return nil }
    return files.compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
      .max()
  }
}
