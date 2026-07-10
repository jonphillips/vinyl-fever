import Foundation
import Testing

@testable import VinylFever

@Suite
struct LiveProcessRunnerTests {
  @Test
  func cancellationBeforeLaunchDoesNotTerminateAnUnlaunchedProcess() {
    let process = Process()
    let controller = ProcessLaunchController(process: process)

    controller.cancel()

    #expect(throws: CancellationError.self) {
      try controller.run()
    }
    #expect(!process.isRunning)
  }
}
