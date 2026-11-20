// Modified for Pagehum: unified application and command-line naming.
import SwiftUI

/// A dedicated destination shared by Settings and the Add Content shortcut.
struct TechBlogImportSettingsView: View {
    @ObservedObject var viewModel: ReaderModel
    var openReader: (() -> Void)? = nil
    var openLibrary: (() -> Void)? = nil

    private var source: TechBlogSource { viewModel.techBlogSettings.source }

    var body: some View {
        #if os(macOS)
        DesktopPage(width: 640) {
            DesktopHeading(title: "Tech blogs", subtitle: "Sources, filters, and import limits.")
            settingsContent
        }
        #else
        ScrollView {
            settingsContent.padding(20)
        }
        .background(AppTheme.canvas)
        .navigationTitle("Tech blogs")
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsSection("Discovery", subtitle: "Your source applies to browsing and one-tap imports.") {
                Picker("Source", selection: $viewModel.techBlogSettings.source) {
                    ForEach(TechBlogSource.allCases) { source in Text(source.title).tag(source) }
                }
            }
            .disabled(viewModel.isImportBusy)

            if source == .blogFeeds {
                settingsSection("Blog feeds", subtitle: "The five latest posts from each blog are ordered by publication date.") {
                    Text("GitHub Engineering, Cloudflare Engineering, Julia Evans, and Martin Fowler")
                        .font(.callout)
                }
            } else {
                communityFilters
            }

            settingsSection("Import limits", subtitle: "Saved links are skipped.") {
                Stepper(value: $viewModel.techBlogSettings.importLimit, in: 1...50) {
                    LabeledContent("Maximum articles") {
                        Text("\(viewModel.techBlogSettings.importLimit)").monospacedDigit().foregroundStyle(AppTheme.textSecondary)
                    }
                }
                if source == .hackerNews {
                    Divider()
                    LabeledContent("Stories to scan") {
                        Picker("Stories to scan", selection: $viewModel.techBlogSettings.storyCount) {
                            ForEach([100, 200, 500], id: \.self) { count in Text("\(count)").tag(count) }
                        }.labelsHidden().frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
            .disabled(viewModel.isImportBusy)

            VStack(alignment: .leading, spacing: 12) {
                TechBlogImportButton(viewModel: viewModel, openLibrary: openLibrary)
                if let message = viewModel.techBlogMessage {
                    Text(message).font(.callout).foregroundStyle(AppTheme.textSecondary)
                }
                URLImportStatusView(viewModel: viewModel, scope: openReader == nil ? .single : .all,
                                    openReader: openReader, openLibrary: openLibrary)
                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.callout).foregroundStyle(AppTheme.warning)
                }
            }
        }
        .pickerStyle(.menu)
    }

    private var communityFilters: some View {
        let step = source == .hackerNews ? 10 : 1
        let settings = $viewModel.techBlogSettings
        let score = source == .hackerNews ? settings.minimumScore : settings.lobstersMinimumScore
        let comments = source == .hackerNews ? settings.minimumComments : settings.lobstersMinimumComments
        return settingsSection("Story filters", subtitle: "Freshness uses the submission date. The article itself may be older.") {
            LabeledContent("Stories") {
                Picker("Stories", selection: settings.feed) {
                    ForEach(TechBlogFeed.allCases) { feed in Text(feed.title).tag(feed) }
                }.labelsHidden().frame(maxWidth: .infinity, alignment: .trailing)
            }
            Divider()
            LabeledContent("Submitted within") {
                Picker("Submitted within", selection: settings.freshnessDays) {
                    Text("24 hours").tag(1)
                    Text("3 days").tag(3)
                    Text("7 days").tag(7)
                }.labelsHidden().frame(maxWidth: .infinity, alignment: .trailing)
            }
            Divider()
            Stepper(value: score, in: 0...1000, step: step) {
                LabeledContent("Minimum points") {
                    Text(score.wrappedValue == 0 && source == .hackerNews ? "Any score" : "\(score.wrappedValue)")
                        .monospacedDigit().foregroundStyle(AppTheme.textSecondary)
                }
            }
            Divider()
            Stepper(value: comments, in: 0...1000, step: step) {
                LabeledContent("Minimum comments") {
                    Text(comments.wrappedValue == 0 ? "Any" : "\(comments.wrappedValue)")
                        .monospacedDigit().foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
        .disabled(viewModel.isImportBusy)
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
                Text("Tech blogs").foregroundStyle(AppTheme.textPrimary)
                Text("Sources, filters, and import limits")
                    .font(.caption).foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Opens the article browser from Add Content.
struct TechBlogQuickImportView: View {
    @ObservedObject var viewModel: ReaderModel
    var openReader: (() -> Void)? = nil
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
                        Text("Tech blogs").font(.headline).foregroundStyle(AppTheme.textPrimary)
                        Text("Preview stories and choose what to import")
                            .font(.caption).foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(viewModel.techBlogSettings.source.title)
                            .font(.caption.weight(.medium)).foregroundStyle(AppTheme.accentText)
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
                            Text("Tech blogs")
                                .font(.headline)
                                .foregroundStyle(AppTheme.textPrimary)
                            Text(viewModel.techBlogSettings.source.title)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(AppTheme.accentText)
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
                            .foregroundStyle(AppTheme.accentText)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.accentText)
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
            .disabled(viewModel.isImportBusy)

            if let message = viewModel.techBlogMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showBrowser) {
            TechBlogBrowseView(viewModel: viewModel, openReader: openReader, openLibrary: openLibrary)
        }
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
                if let result = viewModel.importResult, result.singleItem != nil, result.failures.isEmpty {
                    openLibrary?()
                }
            }
        } label: {
            Label("Import up to \(viewModel.techBlogSettings.importLimit) articles", systemImage: "square.and.arrow.down")
        }
        .disabled(viewModel.isImportBusy)
    }
}
