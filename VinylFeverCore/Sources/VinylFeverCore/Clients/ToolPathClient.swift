import Dependencies
import DependenciesMacros

@DependencyClient
public struct ToolPathClient: Sendable {
  public var resolveTools: @Sendable (_ overrides: ToolPathOverrides) async throws -> [ToolStatus]
}

extension ToolPathClient: TestDependencyKey {
  public static var testValue: Self {
    Self()
  }
}

extension DependencyValues {
  public var toolPathClient: ToolPathClient {
    get { self[ToolPathClient.self] }
    set { self[ToolPathClient.self] = newValue }
  }
}
