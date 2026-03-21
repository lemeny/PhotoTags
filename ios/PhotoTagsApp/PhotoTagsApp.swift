import SwiftUI
import PhotoTagsCore

@main
struct PhotoTagsApp: App {
    @StateObject private var vm = PhotoTagsViewModel.makeDefault()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: vm)
        }
    }
}
