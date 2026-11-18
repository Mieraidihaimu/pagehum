# Library backup and iCloud

Settings → Library Backup is available on iPhone and Mac. Export snapshots the library and
flushes the active reading position and listening interval. The system save/open pickers
support local files and document providers, including iCloud Drive. Export to iCloud Drive
and import on the other device for a manual transfer. These actions do not enable automatic sync.

## Contents and format

The UTF-8 JSON document has `format: "pagehum-library"`, `version: 1`, `exportedAt`, `articles`,
and `listeningHistory`. All dates use milliseconds since the Unix epoch.

Each article contains `title`, optional `sourceURL`, `sourceType` (`url`, `pdf`, `text`),
`fullText`, `dateAdded`, `lastPlayed`, `progressPercent` (0–1), `lastSentenceIndex`, optional
`playbackTextOffset` (UTF-16), `status` (`queued`, `inProgress`, `completed`), and `isFavorite`.
Extracted PDF text and code markers are included; the original PDF is not.

Each history entry contains the original `dateString` (`yyyy-MM-dd`), `date`, and
`secondsListened`. The original day key is preserved across time zones.

There are no audio files, cache references, offline manifests, model files, original PDFs,
session queues, or device preferences in this format. No audio or other attachments are
read from disk during export. Backups are plain text and contain private saved content and URLs.

## Merge behavior

The importer validates the complete document before modifying the library, then saves the
merge once. Save failures roll back the import to the saved baseline. Unsupported versions,
invalid fields and files larger than 50 MiB are rejected. There are also limits of 20,000
article entries and 100,000 listening entries per file.

Articles match by a SHA-256 digest of the JSON-encoded source type, source URL/name and exact
article text. Existing store IDs and the SwiftData schema are unchanged. Different text
versions are separate articles, keeping sentence/text offsets attached to the correct body.
For matches, the newer `lastPlayed` wins for title, progress, resume position and status.
Equal timestamps retain the local progress. The earliest `dateAdded` and either favorite
flag are kept. Local articles missing from a backup remain in the library. Import cannot
propagate deletions or remove a favorite using an older backup.

Daily listening totals merge using the maximum value per day, making repeat imports
idempotent. This cannot distinguish overlapping history from independent listening on two
devices, so independent totals are not summed. The current store records daily aggregates,
not individual listening sessions.

## Personal Team and iCloud

Apple's [enrollment documentation](https://developer.apple.com/help/account/membership/program-enrollment/)
says integrating iCloud requires Apple Developer Program membership. A free Personal Team
can install an app using Xcode, with [provisioning profiles expiring after seven days](https://developer.apple.com/help/account/basics/about-your-developer-account).
Pagehum therefore adds no CloudKit/iCloud container entitlements and uses the system file
picker for manual iCloud Drive backups. The Mac sandbox has user-selected file read/write
access for importing and exporting selected files.

If paid membership becomes available, automatic sync needs its own implementation and
multi-device validation. A direct SwiftData/CloudKit conversion would require compatible
model defaults and removing the unique constraint on `ListeningRecord.dateString` (CloudKit
does not support unique constraints; see Apple's [SwiftData sync guidance](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)).
It would also need durable article IDs, conflict handling for progress/favorites/deletions,
and listening-event IDs or per-device counters to combine time without double-counting.
Audio caches should remain local. The portable backup provides a recovery/transfer path
without depending on those capabilities.
