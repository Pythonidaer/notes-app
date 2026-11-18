# Feature architecture plans

Status: proposed designs, reviewed against main commit `0059c809b456f571b07a881b2a5c1011b7dd7ca4` on November 18, 2026. These documents do not implement features or authorize changing the live library.

## Read in this order

| Plan | Outcome |
| --- | --- |
| [Voice recorder and audio](voice-recorder.md) | Record, import, insert, remove, split, export, and optionally transcribe audio |
| [Laugh analysis](laugh-analysis.md) | Label audience reactions, evaluate local detection, and compare minutes |
| [Memorize by Heart](memorize-by-heart.md) | Practice a note by typing each word's initial |
| [iOS and nearby sync](ios-and-sync.md) | Keep a local library on each device and reconcile changes safely |

## What exists today

- SwiftUI/AppKit UI in `macos/Notes`; `LibraryStore` is a main-actor UI store.
- SQLite in `macos/NotesCore/LibraryDatabase*.swift`; the existing library must already exist. Opening refuses to create/import/migrate it.
- `LibraryModels.swift` currently imports AppKit. The directory called NotesCore is not yet a portable Swift package.
- TipTap source in `macos/editor`; generated editor assets in `macos/Notes/Editor`. Edit source, then rebuild assets through the existing build.
- `noteAudio` in `extensions.js` already round-trips audio figures and their storage metadata. Paragraphs support `data-nn-transcript-for`.
- `EditorBridge`, `ReadingHTML`, audio scheme handling, and `AudioLocator` supply existing integration points.
- Imported audio resolves from a hardcoded Mac export directory. Duplicate Note copies audio into app-owned `note-audio` beside the database. Deleting notes currently leaves audio on disk.

The root README describes current features as out of scope. These plans intentionally describe future work; they do not change current behavior.

## Architectural boundaries

Views display state and send actions. Feature coordinators own workflows. Small services own recording, export, transcription, detection, and persistence. Do not put these workflows into LibraryStore or a WKWebView coordinator.

Proposed domain types are Foundation-only. Keep AppKit clipboard, colors, and drag/drop in macOS adapters; keep AVFoundation, WebKit, and network adapters separate from pure metric/game/sync rules. Extract shared code incrementally rather than moving the entire app first.

Use a serialized repository/database owner for future asynchronous writes; never share the current raw SQLite handle across tasks. Decode/model inference/file conversion run outside the main actor. Deliver progress and UI updates on the main actor. Cancellation is explicit.

## Data evolution

Do not create, migrate, import, or experiment on the user's current `notes.sqlite` or Notes Nursery export. Implement schema work against disposable fixtures and a backed-up copy first. A future, separately reviewed migration must include a version, backup/restore procedure, old-library compatibility checks, and failure recovery.

Until that migration exists, prototypes use an isolated library root and sidecar metadata. Production iOS fresh-library creation is a future requirement, not permission to change the current Mac opener.

Persist identifiers and relative managed paths, never machine-specific absolute paths, as the portable contract. Audio originals and accepted transcripts are durable user data. Waveform caches and unaccepted model predictions are reproducible.

## Suggested implementation sequence

1. Audio ownership, import, insert/remove, and reference tracking on fixtures.
2. Record/stop and recoverable saving; M4A export and split clips.
3. Optional local transcription with review before formatting changes.
4. Memorization engine and native Mac practice screen; can proceed independently of audio.
5. Manual reaction labels and exact metric calculations; then pretrained detection and measured fine-tuning.
6. Shared portable domain/persistence code and an independent iOS library.
7. Versioned nearby sync with conflicts and resumable audio transfer.
8. Real-device tests and TestFlight.

Each feature plan includes acceptance checks. Documentation-only changes need link/content checks; runtime validation belongs to the later implementation.
