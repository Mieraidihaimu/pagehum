import SwiftUI

struct OfflineAudioProgressView: View {
    @ObservedObject var manager: OfflineAudioManager
    let id: String

    var body: some View {
        if let progress = manager.progress[id] {
            HStack(spacing: 6) {
                Image(systemName: progress.state == .ready ? "checkmark.circle.fill" : "arrow.down.circle")
                Text(progress.label).lineLimit(2)
                if progress.state == .saving {
                    ProgressView(value: progress.fraction).frame(width: 48)
                }
            }
            .font(.caption)
            .foregroundStyle(progress.state == .ready ? Color.green : Color.secondary)
            .accessibilityElement(children: .combine)
        }
    }
}

struct OfflineAudioMenuActions: View {
    @ObservedObject var manager: OfflineAudioManager
    let id: String
    var canSave = true
    var canRemove = true
    let save: () -> Void

    var body: some View {
        if let progress = manager.progress[id] {
            Text(progress.label)
            if progress.state == .ready {
                Button("Remove offline audio", systemImage: "trash", role: .destructive) { manager.remove(id) }
                    .disabled(!canRemove)
            } else if [.queued, .saving, .waitingForForeground].contains(progress.state) {
                Button("Pause offline save", systemImage: "pause") { manager.pause(id) }
            } else {
                Button("Resume offline save", systemImage: "arrow.down.circle", action: save).disabled(!canSave)
            }
        } else {
            Button("Save audio offline", systemImage: "arrow.down.circle", action: save).disabled(!canSave)
        }
    }
}

struct OfflineAudioButton: View {
    @ObservedObject var manager: OfflineAudioManager
    let id: String
    var canSave = true
    var canRemove = true
    let save: () -> Void

    var body: some View {
        if let progress = manager.progress[id] {
            Menu {
                OfflineAudioMenuActions(manager: manager, id: id, canSave: canSave, canRemove: canRemove, save: save)
            } label: {
                Image(systemName: progress.state == .ready ? "checkmark.circle.fill" : "arrow.down.circle")
                    .foregroundStyle(progress.state == .ready ? Color.green : Color.accentColor)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(progress.label)
        } else {
            Button(action: save) {
                Image(systemName: "arrow.down.circle").frame(minWidth: 44, minHeight: 44)
            }
            .disabled(!canSave)
            .accessibilityLabel("Save audio offline")
        }
    }
}
