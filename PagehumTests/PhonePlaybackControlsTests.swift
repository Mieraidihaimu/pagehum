#if os(iOS)
import SwiftUI
import Testing
@testable import Pagehum

@MainActor
struct PhonePlaybackControlsTests {
    @Test(arguments: [320, 375, 440])
    func playerFitsOneRowAtStandardTextSize(phoneWidth: Int) {
        let model = ReaderModel(loadModelOnInit: false)
        defer { model.cleanup() }
        model.isModelLoaded = true
        model.sentences = Array(repeating: "An article with enough text for a timeline.", count: 600)

        let width = CGFloat(phoneWidth - 24) // Reader's horizontal margins
        let view = PhonePlaybackControls(viewModel: model)
            .environment(\.dynamicTypeSize, .large)
        let host = UIHostingController(rootView: view)
        host.safeAreaRegions = []
        let size = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        #expect(size.width <= width)
        #expect((44...50).contains(size.height))

        host.overrideUserInterfaceStyle = .dark
        host.view.backgroundColor = UIColor(AppTheme.canvas)
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.layoutIfNeeded()
        let preview = UIGraphicsImageRenderer(size: size).pngData { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        Attachment.record(preview, named: "player-\(phoneWidth)pt-\(Int(size.height))pt-tall.png")
    }
}
#endif
