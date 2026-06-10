import SwiftUI

@main
struct StockpileApp: App {
    @StateObject private var vm = ViewModel()

    private var iconName: String {
        if vm.repairNeeded { return "externaldrive.badge.exclamationmark" }
        return vm.status.driveMounted
            ? "externaldrive.fill.badge.checkmark"
            : "externaldrive.badge.xmark"
    }

    var body: some Scene {
        MenuBarExtra("Stockpile", systemImage: iconName) {
            MenuView(vm: vm)
        }
        .menuBarExtraStyle(.window)
    }
}
