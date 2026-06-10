import SwiftUI
import AppKit
import StockpileCore

struct MenuView: View {
    @ObservedObject var vm: ViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Divider()
            if vm.entries.isEmpty {
                Text("No folders stashed.").foregroundStyle(.secondary)
            } else {
                ForEach(vm.entries, id: \.original) { entry in
                    row(entry)
                }
            }
            Divider()
            drivePicker
            Button("Stash a folder…") { stashFolder() }
                .disabled(vm.busy || !vm.status.driveMounted)
            if vm.busy {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Working…") }
                    .foregroundStyle(.secondary)
            }
            if let err = vm.lastError {
                Text(err).font(.caption).foregroundStyle(.red).lineLimit(3)
            }
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 320)
        .task { await vm.refresh() }
    }

    private var header: some View {
        let freedGB = Double(vm.status.freedBytes) / 1_000_000_000
        return Text(vm.status.driveMounted
            ? String(format: "Drive ✓ · %d stashed · %.1f GB freed",
                     vm.status.stashedCount, freedGB)
            : "Drive missing · \(vm.status.stashedCount) folders offline")
            .font(.headline)
            .foregroundStyle(vm.status.driveMounted ? Color.primary : Color.red)
    }

    private func row(_ entry: Entry) -> some View {
        HStack {
            Text((entry.original as NSString).lastPathComponent)
            Spacer()
            Button("Disintegrate") {
                let name = (entry.original as NSString).lastPathComponent
                let size = ByteCountFormatter.string(fromByteCount: entry.bytes,
                                                     countStyle: .file)
                if confirm("Bring “\(name)” back?",
                           "\(size) will move back to this Mac and be removed "
                           + "from the drive.",
                           action: "Disintegrate") {
                    Task { await vm.disintegrate(URL(fileURLWithPath: entry.original)) }
                }
            }
            .disabled(vm.busy || !vm.status.driveMounted)
        }
    }

    /// First-run / change-of-drive selection.
    private var drivePicker: some View {
        Menu("Use drive…") {
            ForEach(vm.availableVolumes(), id: \.uuid) { vol in
                Button("\(vol.name) (\(vol.url.lastPathComponent))") {
                    Task { await vm.chooseDrive(vol) }
                }
            }
        }
        .disabled(vm.busy)
    }

    private func stashFolder() {
        NSApp.activate(ignoringOtherApps: true)   // accessory app: bring panel frontmost
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true   // ⇧-click / ⌘-click to pick several at once
        panel.message = "Pick one or more folders — hold ⇧ or ⌘ to select several."
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        guard !urls.isEmpty else { return }

        let title: String
        let info: String
        if urls.count == 1 {
            let url = urls[0]
            title = "Stash “\(url.lastPathComponent)” on the drive?"
            info = "The folder moves to the SSD; a link stays at\n\(url.path)\n"
                 + "so apps keep finding it. Unplugging the drive makes it "
                 + "unavailable until replugged."
        } else {
            let names = urls.map { "• \($0.lastPathComponent)" }.joined(separator: "\n")
            title = "Stash \(urls.count) folders on the drive?"
            info = names + "\n\nEach folder moves to the SSD; a link stays behind so "
                 + "apps keep finding it. Unplugging the drive makes them "
                 + "unavailable until replugged."
        }
        if confirm(title, info, action: "Stash") {
            Task { await vm.integrate(urls) }
        }
    }

    private func confirm(_ message: String, _ info: String, action: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
