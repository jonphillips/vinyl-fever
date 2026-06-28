import Dependencies
import DependenciesMacros

@DependencyClient
public struct ScriptClient: Sendable {
  public var run: @Sendable (_ command: ScriptCommand) async throws -> ScriptResult
}

extension ScriptClient: TestDependencyKey {
  public static var testValue: Self {
    Self()
  }
}

extension DependencyValues {
  public var scriptClient: ScriptClient {
    get { self[ScriptClient.self] }
    set { self[ScriptClient.self] = newValue }
  }
}
