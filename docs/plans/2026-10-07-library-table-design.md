# Mac Library Table

## Decision

Use a native SwiftUI table for the Mac library instead of article cards. The table fills the content pane and owns its scrolling; the iPhone library and the Mac home-screen article card stay unchanged.

## Behavior

- Sort Title, Source, Progress, or Added by clicking the column header. Default to newest added first.
- Combine full-text search, starred-only filtering, and All / In progress / Saved / Completed filters.
- Sort sources by their displayed hostname and treat completed status as complete progress, even for older records.
- Use native single and multiple selection. Double-click opens an article; the selection bar and context menu expose opening, queueing, and removal.
- Enqueue selected articles in the displayed sort order, excluding articles already queued or actively playing.
- Confirm removal, remove queued entries consistently, and retain the current article to protect subsequent progress saves.

## Layout

Use 32-point cell content with native row spacing, producing 40-point rows. Titles and sources truncate with full values in tooltips. Initial column widths adapt to the available pane so actions remain visible at narrow sizes. Search and favorites share one row on Mac, and only selected rows reveal the bulk-action bar.

## Verification

`LibraryFilterTests` covers existing search and persistence behavior plus status and all four sort keys. `ListeningQueueTests` covers playback ordering and queue lifecycle. `DesktopLibraryViewTests` hosts an in-memory library at 584- and 1000-point widths, checks compact rows, sortable headers, visible actions, and multiple selection, and writes previews to the test app's temporary directory.

The Mac build and these focused tests pass. Light and dark previews were inspected. This change does not claim a measured scrolling or speech-performance speedup.