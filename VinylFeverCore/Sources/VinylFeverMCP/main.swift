import VinylFeverCore
import VinylFeverListening

@main
enum VinylFeverMCPMain {
  static func main() async {
    await LibraryMCPServer.make(hostName: { ListeningStore.liveHostName() }).run()
  }
}
