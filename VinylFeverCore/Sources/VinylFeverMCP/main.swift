import VinylFeverCore
import VinylFeverListening
import Foundation

@main
enum VinylFeverMCPMain {
  static func main() async {
    let server = LibraryMCPServer.make(hostName: { ListeningStore.liveHostName() },
      requestSnapshotRefresh: {
        DistributedNotificationCenter.default().postNotificationName(
          Notification.Name("com.jonphillips.vinylfever.refreshSnapshot"), object: nil, deliverImmediately: true)
      })
    if CommandLine.arguments.contains("--probe-fire") {
      await MCPEventsProbe.fireNewestFinished()
      return
    }
    guard MCPEventsProbe.isEnabled(environment: ProcessInfo.processInfo.environment) else {
      await server.run()
      return
    }
    await MCPEventsProbe.run(server: server)
  }
}
