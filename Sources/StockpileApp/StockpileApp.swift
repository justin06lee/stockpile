import SwiftUI

@main
struct StockpileApp: App {
    @StateObject private var vm = ViewModel()

    private var menuBarIcon: Image {
        let url = Bundle.module.url(forResource: "stockpile_taskbar", withExtension: "png")
               ?? Bundle.main.url(forResource: "stockpile_taskbar", withExtension: "png")
        if let url, let nsImage = NSImage(contentsOf: url) {
            return Image(nsImage: nsImage)
        }
        return Image(systemName: "externaldrive")
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(vm: vm)
        } label: {
            menuBarIcon
        }
        .menuBarExtraStyle(.window)
    }
}
