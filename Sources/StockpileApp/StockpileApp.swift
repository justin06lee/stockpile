import SwiftUI

@main
struct StockpileApp: App {
    @StateObject private var vm = ViewModel()

    var body: some Scene {
        MenuBarExtra("Stockpile", systemImage: vm.status.driveMounted
                     ? "externaldrive.fill.badge.checkmark"
                     : "externaldrive.badge.xmark") {
            MenuView(vm: vm)
        }
        .menuBarExtraStyle(.window)
    }
}
