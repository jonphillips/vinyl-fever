import VinylFeverCore

@main
enum VinylFeverMCPMain {
  static func main() async {
    await LibraryMCPServer.make().run()
  }
}
