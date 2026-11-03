// Modified for Pagehum: unified application and command-line naming.
import SwiftUI

struct SettingsView: View {

    @ObservedObject var viewModel: ReaderModel
    var openReader: (() -> Void)? = nil
    var openLibrary: (() -> Void)? = nil
    @State private var cacheSize = AudioCacheManager.formattedSize()
    @State private var cacheFileCount = AudioCacheManager.fileCount()
    @State private var showClearConfirmation = false

    private let speeds: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0, 2.25, 2.5, 3.0]
    private let speedLabels = ["0.75x", "1x", "1.25x", "1.5x", "2x", "2.25x", "2.5x", "3x"]

    var body: some View {
        List {
            Section("Content") {
                NavigationLink {
                    TechBlogImportSettingsView(viewModel: viewModel, openLibrary: openLibrary)
                } label: {
                    TechBlogSettingsLabel()
                }
            }
            .listRowBackground(AppTheme.surface)
            Section {
                NavigationLink {
                    StatsView()
                } label: {
                    Label("Listening Stats", systemImage: "chart.bar.fill")
                }
            } header: {
                Text("Activity")
            }
            .listRowBackground(AppTheme.surface)

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Playback Speed", systemImage: "gauge.with.needle")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], spacing: 8) {
                        ForEach(Array(zip(speeds, speedLabels)), id: \.0) { spd, label in
                            Button {
                                withAnimation(.spring(response: 0.3)) { viewModel.speed = spd }
                            } label: {
                                Text(label)
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                                    .background(
                                        viewModel.speed == spd ? AppTheme.accentPrimarySubtle : AppTheme.elevated,
                                        in: RoundedRectangle(cornerRadius: 10)
                                    )
                                    .foregroundStyle(viewModel.speed == spd ? AppTheme.accentPrimary : AppTheme.textSecondary)
                                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(viewModel.speed == spd ? AppTheme.borderFocus : AppTheme.borderSubtle))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Playback")
            }
            .listRowBackground(AppTheme.surface)

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Text Size", systemImage: "textformat.size")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                        Spacer()
                        Text("\(Int(viewModel.textSize))pt")
                            .font(.subheadline.monospacedDigit().weight(.medium))
                            .foregroundStyle(AppTheme.accentPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(AppTheme.accentPrimarySubtle, in: Capsule())
                    }

                    HStack(spacing: 14) {
                        Button { viewModel.textSize = max(12, viewModel.textSize - 2) } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.hierarchical)
                        }
                        .foregroundStyle(AppTheme.textSecondary)

                        Slider(value: $viewModel.textSize, in: 12...32, step: 1)
                            .tint(AppTheme.accentPrimaryFill)

                        Button { viewModel.textSize = min(32, viewModel.textSize + 2) } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.hierarchical)
                        }
                        .foregroundStyle(AppTheme.textSecondary)
                    }

                    Text("The quick brown fox jumps over the lazy dog.")
                        .font(.system(size: CGFloat(viewModel.textSize), design: .serif))
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.canvas, in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(.vertical, 4)
            } header: {
                Text("Reader")
            }
            .listRowBackground(AppTheme.surface)

            Section {
                Picker("Selected Voice", selection: $viewModel.selectedVoice) {
                    ForEach(viewModel.voiceNames, id: \.self) { voice in
                        HStack {
                            Text(voiceFlag(voice))
                            Text(voiceDisplayName(voice))
                        }
                        .tag(voice)
                    }
                }
                #if os(iOS)
                .pickerStyle(.navigationLink)
                #endif
                VoiceModelDownloadView(viewModel: viewModel)
            } header: {
                Text("Voice")
            } footer: {
                if let notice = viewModel.speechEngineNotice { Text(notice) }
            }
            .listRowBackground(AppTheme.surface)

            Section {
                NavigationLink {
                    OfflineAudioListView(viewModel: viewModel, openPlayer: openReader)
                } label: {
                    OfflineAudioSettingsLabel()
                }
                LabeledContent("Cached Audio") {
                    Text(cacheSize)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                LabeledContent("Audio Files") {
                    Text("\(cacheFileCount)")
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Button(role: .destructive) {
                    showClearConfirmation = true
                } label: {
                    HStack {
                        Label("Clear Audio Cache", systemImage: "trash")
                        Spacer()
                        if cacheFileCount == 0 {
                            Text("Empty")
                                .foregroundStyle(AppTheme.textMuted)
                        }
                    }
                }
                .disabled(cacheFileCount == 0)
            } header: {
                Text("Storage")
            } footer: {
                Text("Generated audio files are stored locally for offline playback.")
            }
            .listRowBackground(AppTheme.surface)


            Section {
                LabeledContent("Version") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundStyle(AppTheme.textSecondary)
                }
                LabeledContent("TTS Engine") {
                    Text(viewModel.speechEngineNotice == nil ? "Kokoro 82M" : "System voices")
                        .foregroundStyle(AppTheme.textSecondary)
                }
                LabeledContent("Audio") {
                    Text("24 kHz, mono")
                        .foregroundStyle(AppTheme.textSecondary)
                }
            } header: {
                Text("About")
            }
            .listRowBackground(AppTheme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.canvas)
        .navigationTitle("Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .onAppear { refreshCacheInfo() }
        .confirmationDialog("Clear Audio Cache?", isPresented: $showClearConfirmation, titleVisibility: .visible) {
            Button("Delete All Audio Files", role: .destructive) {
                try? AudioCacheManager.clearAll()
                refreshCacheInfo()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete \(cacheFileCount) cached audio file\(cacheFileCount == 1 ? "" : "s") (\(cacheSize)). Articles will need to regenerate audio on next play.")
        }
    }

    private func refreshCacheInfo() {
        cacheSize = AudioCacheManager.formattedSize()
        cacheFileCount = AudioCacheManager.fileCount()
    }

    // MARK: - Voice helpers

    private func voiceDisplayName(_ voice: String) -> String {
        if let systemName = SystemSpeechEngine.displayName(for: voice) { return systemName }
        let parts = voice.split(separator: "_")
        guard parts.count == 2 else { return voice }
        let name = parts[1].capitalized
        let prefix = parts[0]

        let lang: String
        switch prefix.first {
        case "a": lang = "US"
        case "b": lang = "UK"
        case "j": lang = "JP"
        case "z": lang = "CN"
        case "e": lang = "ES"
        case "f": lang = "FR"
        case "h": lang = "HI"
        case "i": lang = "IT"
        case "p": lang = "PT"
        default: lang = ""
        }

        let gender = prefix.last == "f" ? "Female" : "Male"
        return "\(name) (\(lang) \(gender))"
    }

    private func voiceFlag(_ voice: String) -> String {
        guard let first = voice.first, SystemSpeechEngine.displayName(for: voice) == nil else { return "\u{1F5E3}" }
        switch first {
        case "a": return "\u{1F1FA}\u{1F1F8}"
        case "b": return "\u{1F1EC}\u{1F1E7}"
        case "j": return "\u{1F1EF}\u{1F1F5}"
        case "z": return "\u{1F1E8}\u{1F1F3}"
        case "e": return "\u{1F1EA}\u{1F1F8}"
        case "f": return "\u{1F1EB}\u{1F1F7}"
        case "h": return "\u{1F1EE}\u{1F1F3}"
        case "i": return "\u{1F1EE}\u{1F1F9}"
        case "p": return "\u{1F1E7}\u{1F1F7}"
        default: return "\u{1F30D}"
        }
    }
}
