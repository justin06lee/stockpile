import SwiftUI

@main
struct StockpileApp: App {
    @StateObject private var vm = ViewModel()

    private var menuBarIcon: Image {
        let url = Bundle.module.url(forResource: "stockpile_taskbar", withExtension: "png")
               ?? Bundle.main.url(forResource: "stockpile_taskbar", withExtension: "png")
        if let url, let nsImage = NSImage(contentsOf: url) {
            // Resize to menu-bar height and render as a template so macOS
            // tints it for light/dark menu bars instead of drawing the raw
            // 480x480 artwork at full size.
            let height: CGFloat = 18
            let aspect = nsImage.size.width / max(nsImage.size.height, 1)
            let resized = NSImage(size: NSSize(width: height * aspect, height: height))
            resized.lockFocus()
            nsImage.draw(in: NSRect(origin: .zero, size: resized.size))
            resized.unlockFocus()
            resized.isTemplate = true
            return Image(nsImage: resized)
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
