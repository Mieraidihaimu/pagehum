# ProgressStoring

## Purpose
SwiftData persistence of per-article resume state (`progressPercent`, `lastSentenceIndex`, `lastPlayed`, `status`) on `PlaylistItem` rows, plus the identity of the currently-active item. Owns the insert primitives and the status state-machine; owns no playback or UI state.

## Protocol
```swift
protocol ProgressStoring: AnyObject {
    var activeItemID: PersistentIdentifier? { get set }

    @discardableResult
    func insertActiveItem(title: String, sourceURL: String?, sourceType: String, fullText: String) -> PersistentIdentifier?

    @discardableResult
    func insertQueuedItem(title: String, sourceURL: String?, sourceType: String, fullText: String) -> PersistentIdentifier?

    func saveProgress(for id: PersistentIdentifier, progress: Double, sentenceIndex: Int)
    func saveActiveProgress(progress: Double, sentenceIndex: Int)
}
```
Concrete `DefaultProgressStore` is constructed by the composition root; `modelContext` is **late-injected** (nil until `Pagehum.swift` wires it after init) and an optional `now: () -> Date` clock is injectable for deterministic `lastPlayed`. Because it touches `ModelContext`/`@Model` `PlaylistItem`, the concrete type runs on `@MainActor` even though the protocol is not annotated (see Invariant 8).

## Inputs
- `modelContext: ModelContext?` — late-injected mutable SwiftData context; nil before wiring (ReaderModel.swift `modelContext` L58, injected from `Pagehum.swift`). All methods no-op while nil.
- `now: () -> Date` — injectable clock defaulting to `Date.init`; used for `dateAdded`/`lastPlayed` so tests are deterministic (replaces the raw `Date()` at `saveProgressNow` L369 and `PlaylistItem.init` L27-28).
- Per-item creation args (pre-mapped by the caller): `title`, `sourceURL: String?`, `sourceType: String`, `fullText`. The `ContentSource → (sourceType, sourceURL)` switch (L346-357) is **not** an input to this unit — the caller passes already-mapped strings.
- Per-save args: `progress: Double` and `sentenceIndex: Int`, pushed in by playback (formerly read from the model's `progress` L52 / `currentSentenceIndex` L49 inside `saveProgressNow` L367-368).
- `id: PersistentIdentifier` (for `saveProgress(for:)`), or the internal `activeItemID` (for `saveActiveProgress`).

## Outputs
- `insertActiveItem` returns the new `PersistentIdentifier?` **and** sets `activeItemID` to it (mirrors `currentPlaylistItemID = item.persistentModelID` L361). Returns nil when `modelContext` is nil.
- `insertQueuedItem` returns the new `PersistentIdentifier?` and leaves `activeItemID` **untouched** (the queued row is not the active one). Returns nil when `modelContext` is nil.
- `activeItemID` (get/set) is the flowed-out identity of the active row; the composition root reads it and the "open saved item" path writes it (matches `PlaylistView.swift` L133 `viewModel.currentPlaylistItemID = item.persistentModelID`).
- Mutated `PlaylistItem` rows persisted to SwiftData: `progressPercent`, `lastSentenceIndex`, `lastPlayed`, `status`.
- No `@Published` field is owned here. The former inline `updateNowPlayingInfo()` (L376) is **removed**; a save no longer emits now-playing — the caller (or a `didSaveProgress` hook on the root) drives NowPlayingController (Step 5). `savedConfirmation` (L305) is likewise set by the caller after `insertQueuedItem` returns non-nil, not by this unit.

## Invariants
1. Status state-machine (pins `saveProgressNow` L370-374): `progress >= 1.0` → `.completed`; else if current `status == .queued` → `.inProgress`; otherwise status is left unchanged. Status is never downgraded by a save. PIN.
2. Progress values are **always overwritten** on every save (`progressPercent`, `lastSentenceIndex`, `lastPlayed` at L367-369) even when status stays `.completed` — i.e. a later `saveActiveProgress(0.3)` on a completed item keeps `status == .completed` (Invariant 1) but still writes `progressPercent = 0.3`. This asymmetry (status monotonic, value not) is a current quirk — PIN.
3. `insertActiveItem` creates a `PlaylistItem` with the default `.inProgress` status (PlaylistItem.swift L21 default), sets `activeItemID`, and `textPreview == String(fullText.prefix(200))` (PlaylistItem.swift L25). PIN.
4. `insertQueuedItem` creates a `PlaylistItem` with `status: .queued` explicitly (mirrors `saveForLater` L301) and does **not** set `activeItemID`. PIN.
5. `activeItemID` maps to `currentPlaylistItemID` (L59); `saveActiveProgress` is exactly `saveProgress(for: activeItemID)` guarded on non-nil — no-op if `activeItemID == nil`.
6. `ctx.save()` errors are swallowed via `try?` (L360, L375, and `saveForLater` L304) — a save failure is silent. Documented quirk from plan section 5 — PIN (do not surface the error).
7. Every insert always creates a **new** row; there is no dedup by URL/title, so loading the same content twice yields two `PlaylistItem` rows (current `saveToPlaylist` L358-361 behavior). PIN.
8. All persistence runs on the main actor: `ModelContext` is main-actor-bound and every caller (playback, seek, sentence-started/finished handlers) is `@MainActor`. Concrete type is `@MainActor`.
9. No inference/MLX or audio work occurs here — pure SwiftData row mutation; irrelevant to the MLX-on-GCD and never-stop-engine invariants but must never block them (synchronous, main-actor, cheap).

## Failure modes
- `modelContext == nil` (before wiring): all methods are silent no-ops; inserts return nil (guards at L345, L365). PIN.
- `id` refers to a deleted/absent row: `ctx.model(for: id) as? PlaylistItem` fails the cast → `saveProgress` silently no-ops (L366). PIN.
- `saveActiveProgress` with `activeItemID == nil`: no-op (extends the L365 guard).
- `ctx.save()` throws: swallowed, in-memory mutation may still be visible on the object but not durably flushed (L375). PIN — decision recorded here to preserve, not fix.
- Regression on a `.completed` item: status preserved, but `progressPercent`/`lastSentenceIndex` regress in value (Invariant 2). PIN as-is; a future fix would guard value writes behind the same monotonic check.

## Non-goals
- Does not own listening-time accumulation (`listeningAccumulator`, per-day `ListeningRecord`, 30s flush, `rescale(speed:)`) — that is the sibling **ListeningStoring** (same Step 4, `ListeningStore.md`).
- Does not map `ContentSource → (sourceType, sourceURL)` nor perform URL/PDF/text extraction — that is **TextIngesting** (Step 7); this unit receives pre-mapped strings.
- Does not update lock-screen/now-playing metadata — the removed `updateNowPlayingInfo()` call is owned by **NowPlayingController** (Step 5).
- Does not own `progress`/`currentSentenceIndex` `@Published` state, does not read them from the model, and does not drive playback — those live on the composition root fed by **PlaybackControlling** (Step 10), which pushes values in as parameters.
- Does not set `savedConfirmation` or `isLoading`/`errorMessage` (the root / TextIngesting own those).

## Test manifest
(all [off-device]; in-memory `ModelContainer` via `ModelConfiguration(isStoredInMemoryOnly: true)` for `PlaylistItem`, injected `now` clock)
- `insertActiveItem` sets `activeItemID` to the returned id and the row's `textPreview == String(fullText.prefix(200))`, `status == .inProgress`. [off-device]
- `saveActiveProgress(progress: 0.5, sentenceIndex:)` on a queued active item promotes `queued → inProgress` and writes `progressPercent == 0.5`. [off-device]
- `saveActiveProgress(progress: 1.0, ...)` sets `status == .completed`. [off-device]
- A completed item is not status-regressed by a later `saveActiveProgress(progress: 0.3, ...)` (status stays `.completed`; `progressPercent` becomes 0.3, pinning Invariant 2). [off-device]
- `insertQueuedItem` creates a `.queued` row and leaves `activeItemID` untouched (nil if none set). [off-device]
- With `modelContext == nil`, `insertActiveItem`/`insertQueuedItem` return nil and `saveProgress`/`saveActiveProgress` are no-ops. [off-device]
- `saveProgress(for:)` with a deleted/unknown `PersistentIdentifier` is a silent no-op (no crash). [off-device]

