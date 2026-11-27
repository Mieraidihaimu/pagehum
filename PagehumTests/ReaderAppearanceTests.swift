import Foundation
import SwiftUI
import Testing
@testable import Pagehum

@MainActor
struct ReaderAppearanceTests {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "ReaderAppearanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test
    func resolvesColorSchemeFromSystemWhenUnset() {
        #expect(ReaderAppearance.system.colorScheme == nil)
        #expect(ReaderAppearance.system.resolvedColorScheme(system: .light) == .light)
        #expect(ReaderAppearance.system.resolvedColorScheme(system: .dark) == .dark)

        #expect(ReaderAppearance.light.resolvedColorScheme(system: .dark) == .light)
        #expect(ReaderAppearance.dark.resolvedColorScheme(system: .light) == .dark)
    }

    @Test
    func keysDifferentiateArticlesByURLOrTextID() {
        let urlA = URL(string: "https://pub.cba.mit.edu/863.26/site/")!
        let urlB = URL(string: "https://example.com/post")!
        let webA = ReadingContent(title: "A", body: "body", source: .url(urlA))
        let webB = ReadingContent(title: "B", body: "body", source: .url(urlB))
        let textA = ReadingContent(title: "T", body: "hello", source: .text("hello"))

        let keyA = ReaderAppearanceStore.key(for: webA, textID: "same")
        let keyB = ReaderAppearanceStore.key(for: webB, textID: "same")
        let keyText = ReaderAppearanceStore.key(for: textA, textID: "hash123")

        #expect(keyA == "url:https://pub.cba.mit.edu/863.26/site/")
        #expect(keyB == "url:https://example.com/post")
        #expect(keyA != keyB)
        #expect(keyText == "text:hash123")
        #expect(ReaderAppearanceStore.key(for: textA, textID: "") == nil)
    }

    @Test
    func storePersistsOverridesAndClearsSystemDefault() {
        let defaults = makeDefaults()
        let key = "url:https://pub.cba.mit.edu/863.26/site/"

        ReaderAppearanceStore.save([key: .light], to: defaults)
        #expect(ReaderAppearanceStore.load(from: defaults) == [key: .light])

        ReaderAppearanceStore.save([key: .system], to: defaults)
        #expect(ReaderAppearanceStore.load(from: defaults).isEmpty)
        #expect(defaults.dictionary(forKey: ReaderAppearanceStore.defaultsKey) == nil)
    }

    @Test
    func modelSwitchesAppearancePerArticleWithoutAffectingOthers() {
        let defaults = makeDefaults()
        let model = ReaderModel(loadModelOnInit: false, fallbackSpeechEngine: nil)
        let keyA = "url:https://pub.cba.mit.edu/863.26/site/"
        let keyB = "url:https://example.com/other"

        model.setArticleAppearance(.light, for: keyA, defaults: defaults)
        #expect(ReaderAppearanceStore.load(from: defaults)[keyA] == .light)
        #expect(ReaderAppearanceStore.load(from: defaults)[keyB] == nil)

        model.setArticleAppearance(.system, for: keyA, defaults: defaults)
        #expect(ReaderAppearanceStore.load(from: defaults)[keyA] == nil)
    }
}
