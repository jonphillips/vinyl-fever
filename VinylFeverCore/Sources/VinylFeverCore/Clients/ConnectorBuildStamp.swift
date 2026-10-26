import Foundation

public struct ConnectorBuildStamp: Codable, Equatable, Sendable {
  public var build: String
  public var dirty: Bool
  public var builtAt: String

  public init(build: String, dirty: Bool, builtAt: String) {
    self.build = build
    self.dirty = dirty
    self.builtAt = builtAt
  }

  public static let unknown = Self(build: "unknown", dirty: false, builtAt: "unknown")

  public var displayValue: String {
    guard build != "unknown" else { return "unknown" }
    return "\(build) · \(dirty ? "dirty" : "clean") · \(builtAt)"
  }

  public static func from(infoDictionary: [String: Any]) -> Self {
    guard let build = infoDictionary["VFConnectorBuild"] as? String,
      let dirtyValue = infoDictionary["VFConnectorDirty"] as? String,
      let builtAt = infoDictionary["VFConnectorBuiltAt"] as? String,
      !build.isEmpty, !builtAt.isEmpty,
      dirtyValue == "true" || dirtyValue == "false"
    else { return .unknown }

    return Self(build: build, dirty: dirtyValue == "true", builtAt: builtAt)
  }

  public static func fromMainAppBundle(
    mainBundle: Bundle = .main,
    executableURL: URL? = nil
  ) -> Self {
    let mainBundleStamp = from(infoDictionary: mainBundle.infoDictionary ?? [:])
    if mainBundleStamp != .unknown { return mainBundleStamp }

    let launchedExecutable = executableURL
      ?? mainBundle.executableURL
      ?? URL(fileURLWithPath: CommandLine.arguments.first ?? "")
    var candidate = launchedExecutable.resolvingSymlinksInPath().standardizedFileURL
    while candidate.path != "/" {
      if candidate.pathExtension == "app", let bundle = Bundle(url: candidate) {
        let stamp = from(infoDictionary: bundle.infoDictionary ?? [:])
        if stamp != .unknown { return stamp }
      }
      candidate.deleteLastPathComponent()
    }
    return .unknown
  }
}
