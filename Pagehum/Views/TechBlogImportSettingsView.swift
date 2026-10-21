// Modified for Pagehum: unified application and command-line naming.
import SwiftUI

/// A dedicated destination shared by Settings and the Add Content shortcut.
struct TechBlogImportSettingsView: View {
    @ObservedObject var viewModel: ReaderModel

    var body: some View {
        #if os(macOS)
        DesktopPage(width: 640) {
            DesktopHeading(title: "Hacker News", subtitle: "Filters for browsing stories and one-tap imports.")
            settingsContent
        }
        #else
        ScrollView {
            settingsContent.padding(20)
        }
        .background(Color.platformGroupedBackground)
        .navigationTitle("Hacker News")
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Matching articles are saved to your library, ready to listen.")
                .font(.callout).foregroundStyle(.secondary)

            settingsSection("Story filters", subtitle: "Freshness is based on the Hacker News submission date. The article itself may be older.") {
                LabeledContent("Stories") {
                    Picker("Stories", selection: $viewModel.techBlogSettings.feed) {
                        ForEach(TechBlogFeed.allCases) { feed in Text(feed.title).tag(feed) }
                    }.labelsHidden().frame(maxWidth: .infinity, alignment: .trailing)
                }
                Divider()
                LabeledContent("Submitted within") {
                    Picker("Submitted within", selection: $viewModel.techBlogSettings.freshnessDays) {
                        Text("24 hours").tag(1)
                        Text("3 days").tag(3)
                        Text("7 days").tag(7)
                    }.labelsHidden().frame(maxWidth: .infinity, alignment: .trailing)
                }
                Divider()
                Stepper(value: $viewModel.techBlogSettings.minimumScore, in: 0...1000, step: 10) {
                    LabeledContent("Minimum HN score") {
                        Text(viewModel.techBlogSettings.minimumScore == 0 ? "Any score" : "\(viewModel.techBlogSettings.minimumScore)")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                Divider()
                Stepper(value: $viewModel.techBlogSettings.minimumComments, in: 0...1000, step: 10) {
                    LabeledContent("Minimum comments") {
                        Text(viewModel.techBlogSettings.minimumComments == 0 ? "Any" : "\(viewModel.techBlogSettings.minimumComments)")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(viewModel.isLoading)

            settingsSection("Import limits", subtitle: "Saved links are skipped. Scanning more stories may take longer.") {
                Stepper(value: $viewModel.techBlogSettings.importLimit, in: 1...50) {
                    LabeledContent("Maximum articles") {
                        Text("\(viewModel.techBlogSettings.importLimit)").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                Divider()
                LabeledContent("Stories to scan") {
                    Picker("Stories to scan", selection: $viewModel.techBlogSettings.storyCount) {
                        ForEach([100, 200, 500], id: \.self) { count in Text("\(count)").tag(count) }
                    }.labelsHidden().frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .disabled(viewModel.isLoading)

            VStack(alignment: .leading, spacing: 12) {
                TechBlogImportButton(viewModel: viewModel)
                Text("Preferences save automatically and apply to imports from Add Content.")
                    .font(.caption).foregroundStyle(.secondary)
                if let message = viewModel.techBlogMessage {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                }
                URLImportStatusView(viewModel: viewModel)
                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.callout).foregroundStyle(.orange)
                }
            }
        }
        .pickerStyle(.menu)
    }

    private func settingsSection<Content: View>(_ title: LocalizedStringKey, subtitle: LocalizedStringKey,
                                               @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 14, content: content)
                .padding(18)
                .background(techBlogPanelColor, in: RoundedRectangle(cornerRadius: 14))
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct TechBlogSettingsLabel: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "newspaper")
                .font(.title3).foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text("Hacker News").foregroundStyle(.primary)
                Text("Story filters and import limits")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Streamlined Hacker News quick browse card on front page.
struct TechBlogQuickImportView: View {
    @ObservedObject var viewModel: ReaderModel
    @State private var showBrowser = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showBrowser = true
            } label: {
                #if os(iOS)
                HStack(spacing: 12) {
                    Image(systemName: "newspaper.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                        .frame(width: 44, height: 44)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Hacker News").font(.headline).foregroundStyle(.primary)
                        Text("Preview stories and choose what to import")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(viewModel.techBlogSettings.feed.title)
                            .font(.caption.weight(.medium)).foregroundStyle(.orange)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .padding(16)
                .background(techBlogPanelColor, in: RoundedRectangle(cornerRadius: 16))
                #else
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.orange.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: "newspaper.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.orange)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("Hacker News")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(viewModel.techBlogSettings.feed.title)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.12), in: Capsule())
                        }
                        Text("Preview stories and choose what to import")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 4)

                    HStack(spacing: 4) {
                        Text("Browse")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
                .padding(16)
                .background(techBlogPanelColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
                #endif
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)

            if let message = viewModel.techBlogMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showBrowser) { TechBlogBrowseView(viewModel: viewModel) }
    }
}

private struct TechBlogImportButton: View {
    @ObservedObject var viewModel: ReaderModel
    var prominent = true

    var body: some View {
        #if os(macOS)
        button.buttonStyle(DesktopButtonStyle(primary: prominent))
        #else
        if prominent {
            button.buttonStyle(.borderedProminent).controlSize(.large)
        } else {
            button.buttonStyle(.bordered).controlSize(.large)
        }
        #endif
    }

    private var button: some View {
        Button {
            Task { await viewModel.importLatestTechBlogs() }
        } label: {
            Label("Import top \(viewModel.techBlogSettings.importLimit)", systemImage: "square.and.arrow.down")
        }
        .disabled(viewModel.isLoading)
    }
}

private var techBlogPanelColor: Color {
    #if os(macOS)
    DesktopStyle.panel
    #else
    Color.secondaryGroupedBackground
    #endif
}
