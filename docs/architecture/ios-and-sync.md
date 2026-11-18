# iOS companion, local storage, and nearby sync

Status: proposed. This is the same library format and feature domain with an iOS-specific interface, not a direct build of the AppKit app.

## What must change first

Current NotesCore imports AppKit, the editor wraps NSViewRepresentable, drag/drop uses NSPasteboard, audio has a hardcoded Mac path, and LibraryDatabase requires an existing imported database. Those pieces cannot simply compile unchanged on iOS.

Extract Foundation-only note/folder/audio models, practice rules, metrics, repository interfaces, and a versioned sync protocol into a shared Swift package. Move colors/clipboard/drag behavior to macOS adapters. Add a UIViewRepresentable WKWebView adapter and an iOS recorder/audio-session adapter. Reuse TipTap source and its round-trip contract; package generated resources for both targets. Keep native Mac and iOS navigation separate.

Do not combine this extraction with a wholesale UI rewrite. Choose supported OS versions after checking the existing Xcode target settings and actual phone; use availability checks for newer APIs.

## How each device stores data

| Data | Mac | iPhone |
| --- | --- | --- |
| Notes/folders/metadata | Existing local SQLite; future evolution reviewed separately | Independent SQLite in app Application Support |
| Managed audio | App-owned audio directory beside library | App-owned directory within sandbox |
| Imported legacy audio | Existing export stays intact | Copy requested assets into sandbox; no access to Mac absolute paths |
| Waveforms/model caches | Rebuildable local cache | Rebuildable local cache, evictable |
| Device keys | Keychain | Keychain |

The phone starts with a new empty library through a future versioned factory. Do not weaken the current Mac guard that refuses database creation/migration. Use a separate test library and reviewed migration path.

Each device works offline. Sync transfers records/files, never the live SQLite file or its WAL. Device sandbox paths differ; stable UUIDs and relative paths resolve locally. Mark audio as available/downloading/missing so metadata sync can finish before large files. Define backup inclusion explicitly: user audio/notes are durable; redownloadable models and waveform caches can be excluded. Uninstall may remove local data; sync is not a backup.

## Bluetooth: feasibility and tradeoffs

The goal is nearby synchronization without a server. Recommend Network framework with Bonjour discovery and peer-to-peer Wi-Fi enabled as the first transport spike. This can work without an internet connection; confirm discovery/transfer on the actual Mac/phone and selected OS versions.

Apple now documents Multipeer Connectivity as deprecated (2026) and recommends Network framework. Its Mac transport description does not offer the same Bluetooth transport as iOS. Do not advertise it as Bluetooth-only Mac–iPhone synchronization.

| Approach | Pros | Costs/limits |
| --- | --- | --- |
| Network framework + local/peer-to-peer Wi-Fi | Local, no cloud account, practical candidate for large audio | Both apps typically open; permissions, pairing, reconnect, protocol, and conflict handling are app work |
| Core Bluetooth custom BLE service | Explicit BLE transport; possible small-record experiment | Low throughput for audio, chunking/backpressure and roles required, background restrictions; not automatic database sync |
| CloudKit (optional later) | Remote-device and background sync opportunities | Apple account/network dependency; custom SQLite integration still needs design |
| Manual file export/import | Simple backup and recovery path | User steps; not automatic reconciliation |

If Bluetooth-only is essential, implement a small separate feasibility test before choosing it. Measure throughput and reliability with real set-sized recordings, screen locked, distance changes, and reconnect. Do not promise reliable continuous background synchronization on iOS. Default MVP is an explicit Sync now with both apps foregrounded; automatic sync while connected can follow.

## Protocol and conflict policy

Proposed SyncEngine depends on LocalRepository, AttachmentTransfer, and SyncTransport interfaces. Transport moves versioned messages; the engine owns reconciliation. Pair devices with a user-confirmed code or QR identity flow, store trust keys in Keychain, encrypt/authenticate sessions, and support forgetting a device. Never accept every nearby advertiser.

Use libraryID, deviceID, protocolVersion, schemaVersion, messageID, and per-device monotonically increasing change sequence. Track each entity revision and its parent revision(s); wall-clock timestamps are display fields, not conflict truth.

1. Handshake authenticates paired devices and checks compatible library/schema/protocol versions.
2. Exchange per-peer checkpoints and bounded change manifests.
3. Fetch missing entity revisions; duplicate message application is idempotent.
4. Resolve non-conflicting changes transactionally; retain concurrent changes.
5. Transfer missing audio by asset ID/hash in bounded chunks with resume checkpoints.
6. Verify bytes/hash and atomic rename before marking an asset available.
7. Acknowledge only durable commits; advance checkpoints after persistence.

A single note HTML document is the MVP conflict unit. Concurrent note edits create a visible conflict copy/version; never silently select the newest timestamp. Folder moves must revalidate ancestry and avoid cycles. Simultaneous deletion/edit preserves recoverable content with an explicit resolution. Use durable tombstones and deletion revisions so offline devices cannot resurrect deleted items. Do not discard tombstones until all paired peers acknowledge or a peer is explicitly retired and must resync.

Capture outgoing changes and the change-log entry in one local transaction. New metadata tables need a separately reviewed migration. Incoming writes must flush/coordinate current editor autosave so stale editor buffers cannot overwrite synchronized content; show a conflict if the open note diverged.

Attachments reference immutable asset IDs; replacing audio creates a new asset. Partial downloads use temporary files; malformed messages, excessive sizes, path traversal, duplicate identifiers, and mismatched hashes are rejected. Unsupported protocol versions explain the required upgrade without modifying data. Regenerate waveforms locally; model files are installed locally, not transferred by default.

## iOS scope and Apple Notes import

First iOS milestone: browse/create/edit notes offline and play an imported attachment. Then recording and practice. Keep training on Mac; mobile inference is a later benchmark decision.

This custom app's sync does not automatically read Apple's Notes database or Apple Notes iCloud data. Importing existing iPhone Notes needs its own supported user-driven export/import investigation. Do not promise a public API that exposes the entire Apple Notes library. Keep that work outside the sync MVP.

## TestFlight steps

1. Add an iOS app target with its own bundle ID and shared package/resources.
2. Configure signing/team and verify the current Apple Developer membership.
3. Run on a physical iPhone; exercise offline persistence, microphone denial, audio route changes, and nearby-network permissions.
4. Create the App Store Connect app record; archive a Release build in Xcode, validate, and upload.
5. Complete required app/beta metadata, privacy disclosures, and export-compliance answers based on actual encryption.
6. Add the processed build to an internal testing group, invite the account tester, and install through TestFlight.
7. For external testers, supply beta review information and submit for review as required.
8. Collect feedback and upload incremented builds.

TestFlight builds expire after 90 days. Internal testers are App Store Connect users with access; ordinary friends use external testing. Current Apple documentation allows up to 100 internal and 10,000 external testers. Do not infer that TestFlight installation keeps the app alive in the background.

## Acceptance matrix

Use two real devices with disposable libraries. Test independent offline edits, both editing one note, delete/edit races, folder cycles, clock skew, repeated/out-of-order messages, incompatible versions, permission denial, cancelled pairing, revoked trust, app termination mid-transfer, full disk, corrupt hashes, and a large audio asset. Restart both devices and confirm persistence. Sync repeatedly and verify no duplicates or lost changes. Check that a fresh phone cannot overwrite the Mac library and no test touches the live imported database.

Before implementation, record: phone model/OS, minimum supported Mac/iOS versions, whether Bluetooth-only is required, maximum expected recording length, and whether remote/cloud sync is desired. These are product decisions, not blockers to documenting this recommended foreground local-sync design.

## Primary references (checked November 18, 2026)

- Current networking guidance: https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api
- Multipeer deprecation and platform transports: https://developer.apple.com/documentation/multipeerconnectivity
- TestFlight: https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/
