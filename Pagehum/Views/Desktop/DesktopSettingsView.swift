// Modified for Pagehum: unified application and command-line naming.
#if os(macOS)
import SwiftUI

struct DesktopSettingsView: View {
    @ObservedObject var viewModel: ReaderModel
    var openStats: () -> Void
    var openTechBlogSettings: () -> Void
    @State private var cacheSize = AudioCacheManager.formattedSize()
    @State private var cacheCount = AudioCacheManager.fileCount()
    @State private var clearConfirmation = false
    @State private var cacheMessage: String?
    @State private var cacheError: String?

    var body: some View {
        DesktopPage(width: 640) {
            DesktopHeading(title: "Make it yours.", subtitle: "A comfortable voice. A comfortable pace.")
            sectionTitle("Content")
            row {
                Button(action: openTechBlogSettings) {
                    HStack {
                        TechBlogSettingsLabel()
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(DesktopStyle.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            sectionTitle("Playback")
            row {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Playback speed")
                    Text("Adjust anytime in the player.").font(.caption).foregroundStyle(DesktopStyle.secondary)
                }
                Spacer()
                Picker("Playback speed", selection: $viewModel.speed) {
                    ForEach(DesktopStyle.speeds, id: \.self) { speed in Text(DesktopStyle.speedLabel(speed)).tag(speed) }
                }.labelsHidden().frame(width: 100)
            }
            row {
                Text("Voice")
                Spacer()
                Picker("Voice", selection: $viewModel.selectedVoice) {
                    ForEach(viewModel.voiceNames, id: \.self) { voice in Text(DesktopStyle.voiceLabel(voice)).tag(voice) }
                }.labelsHidden().frame(maxWidth: 260)
            }
            sectionTitle("Reader")
            row {
                Text("Text size")
                Spacer()
                Text("\(Int(viewModel.textSize)) pt").font(.callout.monospacedDigit()).foregroundStyle(DesktopStyle.secondary)
                Slider(value: $viewModel.textSize, in: 12...32, step: 1) { Text("Reader text size") }
                    .labelsHidden().frame(maxWidth: 220)
            }
            Text("Sometimes all an idea needs is a little room to breathe.")
                .font(.system(size: viewModel.textSize, design: .serif)).lineSpacing(8)
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(DesktopStyle.panel, in: RoundedRectangle(cornerRadius: 10))
            sectionTitle("Storage")
            row {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cached audio")
                    Text("\(cacheSize) · \(cacheCount) files").font(.caption).foregroundStyle(DesktopStyle.secondary)
                }
                Spacer()
                Button { clearConfirmation = true } label: { Label("Clear cache", systemImage: "trash") }
                    .buttonStyle(DesktopButtonStyle()).disabled(cacheCount == 0)
            }
            if let cacheMessage { Text(cacheMessage).font(.caption).foregroundStyle(DesktopStyle.secondary) }
            sectionTitle("Activity")
            row {
                Button(action: openStats) {
                    HStack { Label("Listening stats", systemImage: "chart.bar"); Spacer(); Image(systemName: "chevron.right") }
                }.buttonStyle(.plain)
            }
            DisclosureGroup("About Pagehum") {
                VStack(spacing: 12) {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    LabeledContent("Voice engine", value: "Kokoro 82M")
                    LabeledContent("Audio", value: "24 kHz, mono")
                }.font(.callout).padding(.vertical, 12)
            }.foregroundStyle(DesktopStyle.secondary).padding(.top, 20)
        }
        .onAppear(perform: refreshCache)
        .confirmationDialog("Clear cached audio?", isPresented: $clearConfirmation, titleVisibility: .visible) {
            Button("Clear cache", role: .destructive) {
                do {
                    try AudioCacheManager.clearAll()
                    refreshCache()
                    cacheMessage = "Cache cleared. Your library is unchanged."
                } catch { cacheError = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This removes \(cacheSize) of generated audio. Articles will generate audio again when you listen.") }
        .alert("Couldn’t clear cache", isPresented: Binding(get: { cacheError != nil }, set: { if !$0 { cacheError = nil } })) {
            Button("OK") { cacheError = nil }
        } message: { Text(cacheError ?? "") }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.callout).foregroundStyle(DesktopStyle.secondary).padding(.top, 24).padding(.bottom, 8)
    }

    private func row<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 16, content: content).padding(.vertical, 16)
            .overlay(alignment: .top) { Rectangle().fill(DesktopStyle.border).frame(height: 1) }
    }

    private func refreshCache() {
        cacheSize = AudioCacheManager.formattedSize()
        cacheCount = AudioCacheManager.fileCount()
    }
}
#endif
