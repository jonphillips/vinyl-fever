import Dependencies
import DependenciesMacros

@DependencyClient
public struct TasteCurationClient: Sendable {
  public var append: @Sendable (_ change: CurationChange, _ host: String) async throws -> Void
}

extension TasteCurationClient: TestDependencyKey {
  public static var testValue: Self { Self(append: { _, _ in }) }
}
extension TasteCurationClient: DependencyKey {
  public static var liveValue: Self { testValue }
}

extension DependencyValues {
  public var tasteCurationClient: TasteCurationClient {
    get { self[TasteCurationClient.self] }
    set { self[TasteCurationClient.self] = newValue }
  }
}
