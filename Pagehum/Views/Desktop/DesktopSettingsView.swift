// Modified for Pagehum: unified application and command-line naming.
#if os(macOS)
import SwiftUI

struct DesktopSettingsView: View {
    @ObservedObject var viewModel: ReaderModel
    var openStats: () -> Void
    var openTechBlogSettings: () -> Void
    var openOfflineAudio: () -> Void
    var openReader: () -> Void
    @State private var cacheSize = AudioCacheManager.formattedSize()
    @State private var cacheCount = AudioCacheManager.fileCount()
    @State private var clearConfirmation = false
    @State private var cacheMessage: String?
    @State private var cacheError: String?
    @State private var showLibraryBackup = false

    var body: some View {
        DesktopPage(width: 660) {
            DesktopHeading(title: "Make it yours.", subtitle: "A comfortable voice. A comfortable pace.")

            sectionTitle("Background progress")
            settingsGroup {
                settingsRow { SettingsProgressView(viewModel: viewModel, openReader: openReader) }
            }

            sectionTitle("Content")
            settingsGroup {
                SettingsNavRow(trailingIcon: "chevron.right", action: openTechBlogSettings) {
                    TechBlogSettingsLabel()
                }
            }

            sectionTitle("Playback")
            settingsGroup {
                settingsRow {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Playback speed")
                        Text("Adjust anytime in the player.").font(.caption).foregroundStyle(DesktopStyle.secondary)
                    }
                    Spacer()
                    Picker("Playback speed", selection: $viewModel.speed) {
                        ForEach(PlaybackSpeed.settingsOptions, id: \.self) { speed in Text(PlaybackSpeed.label(speed)).tag(speed) }
                    }.labelsHidden().frame(width: 100)
                }
                groupDivider
                settingsRow {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Voice")
                        if let notice = viewModel.speechEngineNotice {
                            Text(notice).font(.caption).foregroundStyle(DesktopStyle.secondary)
                        }
                    }
                    Spacer()
                    Picker("Voice", selection: $viewModel.selectedVoice) {
                        ForEach(viewModel.voiceNames, id: \.self) { voice in Text(DesktopStyle.voiceLabel(voice)).tag(voice) }
                    }.labelsHidden().frame(maxWidth: 260)
                }
                if viewModel.canDownloadVoiceModel {
                    groupDivider
                    settingsRow { VoiceModelDownloadView(viewModel: viewModel) }
                }
            }

            sectionTitle("Audio-Clean")
            settingsGroup {
                settingsRow {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Speech style")
                        Text(viewModel.audioCleanMode.description).font(.caption).foregroundStyle(DesktopStyle.secondary)
                    }
                    Spacer()
                    Picker("Speech style", selection: $viewModel.audioCleanMode) {
                        ForEach(AudioCleanMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }.labelsHidden().frame(width: 140)
                }
            }

            sectionTitle("Reader")
            settingsGroup {
                settingsRow {
                    Text("Text size")
                    Spacer()
                    Text("\(Int(viewModel.textSize)) pt").font(.callout.monospacedDigit()).foregroundStyle(DesktopStyle.secondary)
                    Slider(value: $viewModel.textSize, in: 12...32, step: 1) { Text("Reader text size") }
                        .labelsHidden().frame(maxWidth: 220)
                }
                groupDivider
                Text("Sometimes all an idea needs is a little room to breathe.")
                    .font(.system(size: viewModel.textSize, design: .serif)).lineSpacing(8)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            }

            sectionTitle("Storage")
            settingsGroup {
                SettingsNavRow(trailingIcon: "chevron.right", action: openOfflineAudio) {
                    OfflineAudioSettingsLabel()
                }
                groupDivider
                settingsRow {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cached audio")
                        Text("\(cacheSize) · \(cacheCount) files").font(.caption).foregroundStyle(DesktopStyle.secondary)
                    }
                    Spacer()
                    Button { clearConfirmation = true } label: { Label("Clear cache", systemImage: "trash") }
                        .buttonStyle(DesktopButtonStyle()).disabled(cacheCount == 0)
                }
            }
            if let cacheMessage {
                Text(cacheMessage).font(.caption).foregroundStyle(DesktopStyle.secondary).padding(.top, 8)
            }

            sectionTitle("Data")
            settingsGroup {
                SettingsNavRow(trailingIcon: "arrow.up.right.square", action: { showLibraryBackup = true }) {
                    Label("Library backup", systemImage: "externaldrive")
                }
            }

            sectionTitle("Activity")
            settingsGroup {
                SettingsNavRow(trailingIcon: "arrow.up.right.square", action: openStats) {
                    Label("Listening stats", systemImage: "chart.bar")
                }
            }

            settingsGroup {
                DisclosureGroup("About Pagehum") {
                    VStack(spacing: 12) {
                        LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        LabeledContent("Voice engine", value: viewModel.speechEngineNotice == nil ? "Kokoro 82M" : "System voices")
                        LabeledContent("Audio", value: "24 kHz, mono")
                    }
                    .font(.callout)
                    .foregroundStyle(DesktopStyle.secondary)
                    .padding(.top, 12)
                }
                .padding(14)
            }
            .padding(.top, 24)
        }
        .onAppear(perform: refreshCache)
        .sheet(isPresented: $showLibraryBackup) {
            NavigationStack {
                LibraryBackupView(viewModel: viewModel)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showLibraryBackup = false }
                                .keyboardShortcut(.cancelAction)
                        }
                    }
            }
            .frame(minWidth: 540, idealWidth: 580, minHeight: 520, idealHeight: 560)
        }
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

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title).font(.callout.weight(.medium)).foregroundStyle(DesktopStyle.secondary).padding(.top, 24).padding(.bottom, 8)
    }

    private func settingsGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .themeCard(cornerRadius: 12)
    }

    private var groupDivider: some View {
        Rectangle()
            .fill(AppTheme.borderSubtle)
            .frame(height: 1)
            .padding(.horizontal, 14)
    }

    private func settingsRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 16, content: content)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func refreshCache() {
        cacheSize = AudioCacheManager.formattedSize()
        cacheCount = AudioCacheManager.fileCount()
    }
}

private struct SettingsNavRow<Label: View>: View {
    var trailingIcon = "chevron.right"
    let action: () -> Void
    @ViewBuilder var label: Label
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                label
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: trailingIcon)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DesktopStyle.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovering ? AppTheme.elevated.opacity(0.55) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
#endif
