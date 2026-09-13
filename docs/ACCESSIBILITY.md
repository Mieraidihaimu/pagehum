# Accessibility

Pagehum follows system accessibility settings in the native reader and playback controls.

- **VoiceOver and keyboard actions:** sentences and code headers are buttons that move playback to that position. Code copying and expansion remain separate buttons. Automatic sentence scrolling is suspended while VoiceOver is active.
- **Larger text:** the native reader, code blocks, and Settings preview scale with Dynamic Type in addition to the app's reader text-size setting. At accessibility text sizes, playback speed appears above the transport buttons. Playback controls reserve space below the article instead of covering it.
- **Web articles:** choose **Text view** above an article to read its extracted text using the native reader. **Web page** returns to the original site. Switching views preserves playback. The original site's accessibility remains under that site's control.
- **Reduced motion:** reader highlighting, code expansion, playback-control transitions, and the saved-content confirmation respect Reduce Motion.
- **Reduced transparency:** playback controls use an opaque background when Reduce Transparency is enabled.
- **Increased contrast:** the native reader keeps inactive prose at the primary text color instead of dimming it.

## Manual verification before release

These checks require on-device testing; a successful Xcode build does not establish VoiceOver or visual-layout correctness.

1. With VoiceOver enabled, navigate Home's Library, Settings, URL-clear button, and pasted-text editor. Confirm each announces its purpose.
2. Open pasted text or a PDF. Navigate sentences, activate one, and confirm playback moves there. During playback, explore another part of the article and confirm automatic scrolling does not move the reading position.
3. Open an article containing a long code block. Verify the seek, copy, and expand buttons are separate focus stops; copying must not seek. Expand the block and read the additional source.
4. Open a web article and switch between Text view and Web page, both while paused and playing. Confirm the position and playback state are preserved.
5. At the largest accessibility text size, check Home, Settings, a long native article, and playback controls in portrait and landscape. Confirm text wraps, actions remain reachable, and the final sentence can scroll above the controls.
6. Enable Reduce Motion and Reduce Transparency. Confirm controls use an opaque background and expansion/highlighting does not animate. Check native prose with Increase Contrast enabled.
7. On Mac, navigate reader sentences, code actions, and playback controls with keyboard navigation and VoiceOver.

The September 13 accessibility changes compile in the Mac app and test bundle. Live desktop accessibility inspection timed out; the manual checks above, including iPhone validation, remain pending.
