// Modified for Pagehum: unified application and command-line naming.
#if os(macOS)
import SwiftUI

struct DesktopQueueView: View {
    @ObservedObject var viewModel: ReaderModel
    @ObservedObject var queue: ListeningQueue

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Up next").font(.title3.weight(.medium))
                Spacer()
                if !queue.upcoming.isEmpty {
                    Button("Clear upcoming") { queue.clearUpcoming() }.buttonStyle(.borderless)
                }
            }
            if !queue.isActive {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your queue is empty. Select articles in Library to listen continuously.")
                        .font(.callout)
                        .foregroundStyle(DesktopStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)
            } else {
                Text("Continues automatically · Resume saved positions")
                    .font(.caption).foregroundStyle(DesktopStyle.secondary)
                if let current = queue.current {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(queue.failure == nil ? "Current article" : "Needs attention")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(queue.failure == nil ? DesktopStyle.accent : AppTheme.destructiveText)
                        Text(current.title).lineLimit(2)
                        if let failure = queue.failure {
                            Text(failure)
                                .font(.caption)
                                .foregroundStyle(AppTheme.destructiveText)
                                .lineLimit(2)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(queue.failure == nil ? AppTheme.elevated : AppTheme.destructiveSubtle,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                if queue.upcoming.isEmpty {
                    Text("This is the last article. Playback stops when it finishes.")
                        .font(.callout).foregroundStyle(DesktopStyle.secondary).padding(.vertical, 12)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(queue.upcoming.enumerated()), id: \.element.id) { index, entry in
                                HStack(spacing: 12) {
                                    Text("\(index + 1)")
                                        .font(.callout.monospacedDigit())
                                        .foregroundStyle(DesktopStyle.secondary)
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.title).lineLimit(2)
                                        Text(ListeningQueue.durationLabel(characters: entry.remainingCharacters, speed: viewModel.speed))
                                            .font(.caption).foregroundStyle(DesktopStyle.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    Button { queue.move(entry.id, by: -1) } label: { Image(systemName: "arrow.up") }
                                        .disabled(index == 0).help("Move earlier").accessibilityLabel("Move \(entry.title) earlier")
                                    Button { queue.move(entry.id, by: 1) } label: { Image(systemName: "arrow.down") }
                                        .disabled(index == queue.upcoming.count - 1).help("Move later").accessibilityLabel("Move \(entry.title) later")
                                    Button { queue.remove(entry.id) } label: { Image(systemName: "xmark") }
                                        .help("Remove from queue; keep in Library").accessibilityLabel("Remove \(entry.title) from queue")
                                }
                                .buttonStyle(.borderless)
                                .padding(.vertical, 14)
                                Divider()
                            }
                        }
                    }.frame(maxHeight: 420)
                }
            }
        }
        .padding(20).frame(width: 380)
        .background(AppTheme.playerSurface).foregroundStyle(DesktopStyle.text)
        .presentationBackground(AppTheme.playerSurface)
    }
}
#endif
