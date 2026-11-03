// Modified for Pagehum: unified application and command-line naming.
import SwiftUI

/// A dedicated destination shared by Settings and the Add Content shortcut.
struct TechBlogImportSettingsView: View {
    @ObservedObject var viewModel: ReaderModel
    var openLibrary: (() -> Void)? = nil

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
        .background(AppTheme.canvas)
        .navigationTitle("Hacker News")
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Matching articles are saved to your library, ready to listen.")
                .font(.callout).foregroundStyle(AppTheme.textSecondary)

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
                            .monospacedDigit().foregroundStyle(AppTheme.textSecondary)
                    }
                }
                Divider()
                Stepper(value: $viewModel.techBlogSettings.minimumComments, in: 0...1000, step: 10) {
                    LabeledContent("Minimum comments") {
                        Text(viewModel.techBlogSettings.minimumComments == 0 ? "Any" : "\(viewModel.techBlogSettings.minimumComments)")
                            .monospacedDigit().foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
            .disabled(viewModel.isLoading)

            settingsSection("Import limits", subtitle: "Saved links are skipped. Scanning more stories may take longer.") {
                Stepper(value: $viewModel.techBlogSettings.importLimit, in: 1...50) {
                    LabeledContent("Maximum articles") {
                        Text("\(viewModel.techBlogSettings.importLimit)").monospacedDigit().foregroundStyle(AppTheme.textSecondary)
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
                TechBlogImportButton(viewModel: viewModel, openLibrary: openLibrary)
                Text("Preferences save automatically and apply to imports from Add Content.")
                    .font(.caption).foregroundStyle(AppTheme.textSecondary)
                if let message = viewModel.techBlogMessage {
                    Text(message).font(.callout).foregroundStyle(AppTheme.textSecondary)
                }
                URLImportStatusView(viewModel: viewModel, openLibrary: openLibrary)
                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.callout).foregroundStyle(AppTheme.warning)
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
                .themeCard(cornerRadius: 14)
            Text(subtitle).font(.caption).foregroundStyle(AppTheme.textSecondary)
        }
    }
}

struct TechBlogSettingsLabel: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "newspaper")
                .font(.title3).foregroundStyle(AppTheme.accentPrimary)
                .frame(width: 40, height: 40)
                .background(AppTheme.accentPrimarySubtle, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text("Hacker News").foregroundStyle(AppTheme.textPrimary)
                Text("Story filters and import limits")
                    .font(.caption).foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Streamlined Hacker News quick browse card on front page.
struct TechBlogQuickImportView: View {
    @ObservedObject var viewModel: ReaderModel
    var openLibrary: (() -> Void)? = nil
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
                        .foregroundStyle(AppTheme.accentPrimary)
                        .frame(width: 44, height: 44)
                        .background(AppTheme.accentPrimarySubtle, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Hacker News").font(.headline).foregroundStyle(AppTheme.textPrimary)
                        Text("Preview stories and choose what to import")
                            .font(.caption).foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(viewModel.techBlogSettings.feed.title)
                            .font(.caption.weight(.medium)).foregroundStyle(AppTheme.accentPrimary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.textSecondary)
                        .accessibilityHidden(true)
                }
                .padding(16)
                .themeCard(cornerRadius: 16)
                #else
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.accentPrimarySubtle)
                            .frame(width: 44, height: 44)
                        Image(systemName: "newspaper.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(AppTheme.accentPrimary)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("Hacker News")
                                .font(.headline)
                                .foregroundStyle(AppTheme.textPrimary)
                            Text(viewModel.techBlogSettings.feed.title)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(AppTheme.accentPrimary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppTheme.accentPrimarySubtle, in: Capsule())
                        }
                        Text("Preview stories and choose what to import")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    Spacer(minLength: 4)

                    HStack(spacing: 4) {
                        Text("Browse")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.accentPrimary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.accentPrimary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(AppTheme.accentPrimarySubtle, in: Capsule())
                }
                .padding(16)
                .themeCard(cornerRadius: 16)
                #endif
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)

            if let message = viewModel.techBlogMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showBrowser) { TechBlogBrowseView(viewModel: viewModel, openLibrary: openLibrary) }
    }
}

private struct TechBlogImportButton: View {
    @ObservedObject var viewModel: ReaderModel
    var prominent = true
    var openLibrary: (() -> Void)? = nil

    var body: some View {
        #if os(macOS)
        button.buttonStyle(DesktopButtonStyle(primary: prominent))
        #else
        if prominent {
            button.buttonStyle(ThemeButtonStyle()).controlSize(.large)
        } else {
            button.buttonStyle(ThemeButtonStyle(primary: false)).controlSize(.large)
        }
        #endif
    }

    private var button: some View {
        Button {
            Task {
                await viewModel.importLatestTechBlogs()
                if let result = viewModel.importResult, result.failures.isEmpty,
                   result.imported > 0 || result.skipped > 0 {
                    openLibrary?()
                }
            }
        } label: {
            Label("Import top \(viewModel.techBlogSettings.importLimit)", systemImage: "square.and.arrow.down")
        }
        .disabled(viewModel.isLoading)
    }
}
