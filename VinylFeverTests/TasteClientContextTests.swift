import Testing
import VinylFeverCore

struct TasteClientContextTests {
  @Test("only live contexts install live taste clients")
  func liveTasteClientContextGuard() {
    #expect(installsLiveTasteClients(.live))
    #expect(!installsLiveTasteClients(.test))
    #expect(!installsLiveTasteClients(.preview))
  }
}
