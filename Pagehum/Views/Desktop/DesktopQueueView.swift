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
            Text("Continues automatically · Resume saved positions")
                .font(.caption).foregroundStyle(DesktopStyle.secondary)
            if let current = queue.current {
                VStack(alignment: .leading, spacing: 4) {
                    Text(queue.failure == nil ? "Current article" : "Needs attention")
                        .font(.caption).foregroundStyle(DesktopStyle.accent)
                    Text(current.title).lineLimit(2)
                }
            }
            if queue.upcoming.isEmpty {
                Text("This is the last article. Playback stops when it finishes.")
                    .font(.callout).foregroundStyle(DesktopStyle.secondary).padding(.vertical, 12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(queue.upcoming.enumerated()), id: \.element.id) { index, entry in
                            HStack(spacing: 12) {
                                Text("\(index + 1)").foregroundStyle(DesktopStyle.secondary).frame(width: 20)
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
                }.frame(maxHeight: 320)
            }
        }
        .padding(24).frame(width: 480)
        .background(DesktopStyle.canvas).foregroundStyle(DesktopStyle.text)
        .preferredColorScheme(.dark)
    }
}
#endif
