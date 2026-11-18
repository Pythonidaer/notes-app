# VoiceRecorder and audio attachments

Status: proposed. See [architecture overview](README.md) for current code and database restrictions.

## User experience

Attachment menu → Record Audio opens a native recording panel with Record, elapsed time, input level, and Stop. Record starts capture only after permission. Stop finalizes a playable file. The user can insert it into the original note, keep it in the audio library, or discard it. Switching notes must not attach the result to a different note.

Import Audio copies a selected WAV/MP3/M4A into managed storage; insert an existing item without making another unnecessary copy. An embedded component shows name, duration, play/pause, seek, and a menu for transcription, split, export, and removal. A separate Audio Library lists managed items and their note references.

Removing a component detaches it from that note. Deleting the underlying managed file is a distinct action showing all affected references; offer trash/restore. Never delete imported legacy originals automatically.

## Services and state

| Proposed component | Responsibility |
| --- | --- |
| VoiceRecorderCoordinator | Recording state, originating note ID, insertion, user-visible errors |
| AudioRecordingService | AVFoundation capture and microphone permission |
| AudioAssetRepository | Managed files, metadata, reference tracking, trash |
| AudioExportService | Decode/transcode and export a selected time range |
| TranscriptionService | Timestamped verbatim transcript and model metadata |
| TranscriptFormattingService | Optional readable formatting as a separate revision |

State: idle → requestingPermission → recording → finalizing → ready; failures include permissionDenied, inputUnavailable, diskFull, and interrupted. Repeated Stop is safe. Capture callbacks cannot touch UI or the SQLite handle. Persist a temporary recording manifest, finalize by atomic rename, and recover interrupted sessions on launch where the container permits recovery. Do not promise recovery of every interrupted compressed file.

Use AVAudioRecorder for a small Record/Stop MVP; use AVAudioEngine only if metering/streaming requirements justify it. iOS also needs an AVAudioSession adapter for route changes and interruptions. Include microphone usage descriptions and sandbox/audio-input entitlements as required by the eventual target.

## Durable model (proposed)

- AudioAsset: UUID, relativePath, originalName, MIME/container/codec, byteCount, durationMilliseconds, sampleRate, channels, contentHash, createdAt, ownership (managed/legacyExternal), availability.
- AudioAttachment: UUID, noteID, assetID, order or editor-node identity.
- AudioClip: UUID, sourceAssetID, startMilliseconds, endMilliseconds, optional materializedAssetID.
- Transcript: UUID, assetID/clipID, sourceHash, language, engine/modelVersion, raw text, timestamped segments, review status.
- TranscriptRevision: original transcript ID, formatted text, formatting options, acceptedAt.

An asset and an attachment are different: several notes can use the same asset. Clip ranges use the original timeline; exported clips have their own timeline plus a source offset. Validate 0 ≤ start < end ≤ duration.

File and database commits are not one transaction: stage/copy → verify hash and playable duration → commit metadata → attach in an undoable editor transaction. Keep a recovery journal and remove unreferenced staged files after a grace period. A failed insertion must leave a recoverable asset, not a silent loss.

## Fit the existing editor

Extend the existing `noteAudio` figure rather than inventing a second embed. Add stable assetID and attachmentID while retaining legacy storagePath parsing. Use UUID filenames for new files, preserve display names separately, and keep AudioLocator's containment and symlink checks.

Add a narrow typed bridge operation such as `insertAudioAttachment(_:in:)`. Validate payload, note identity, and editor readiness; serialize JSON instead of interpolating filenames into JavaScript. Insert/remove through TipTap transactions so undo/redo and autosave work. Update ReadingHTML parsing, sanitization allowlists, read mode, and search together. A missing asset renders a recoverable placeholder.

Legacy figures without IDs remain playable. Do not silently rewrite all imported HTML. A separately reviewed compatibility mapping can associate legacy paths with portable IDs. Undo history and other open windows count as retention references before any file purge.

## Formats and splitting

Prefer AAC in an M4A container for ordinary recording/storage. Preserve imported originals. WAV is a useful lossless working/export format but consumes more space. Renaming an extension is not conversion.

Use AVFoundation export for compatible M4A destinations and validate supported output types at runtime. MP3 encoding is a separate capability: do not assume AVAssetExportSession provides it. Isolate an optional embedded encoder (for example a reviewed LAME-based implementation) behind AudioExportService; verify licensing, build/signing, and actual device support before adopting it. No system-installed ffmpeg dependency in the shipped iOS app. Unsupported MP3 export should be explained, with M4A available.

Split UI: waveform, keyboard-accessible range controls, add split point, preview selection, and Export selected clips. Splitting creates multiple non-destructive ranges first; export each to a distinct managed asset only on request. Retain the original. Handle cancellation and disk exhaustion without partial attachments. Decode/re-encode when sample-accurate boundaries are required; compressed passthrough may not cut exactly at the selected sample.

## Optional transcription and formatting

Off by default; allow Transcribe after recording and per-file Transcribe. Prototype a local whisper.cpp backend on Mac, then benchmark memory, battery, language quality, and latency before selecting an iOS model. Model download needs explicit user action, progress, storage estimate, and integrity checking; transcription works offline after required assets are installed. An Apple Speech adapter is another option only when its on-device support is confirmed for the device/language; never silently fall back to server recognition.

Keep verbatim timestamped text separate from formatting. Start with punctuation/paragraph cleanup, offer a preview/diff, and require Apply before replacing note text. Preserve jokes, profanity, timing markers, and original wording; generative cleanup may change meaning. Capture note revision when the job starts; if it changes, offer insertion or a new revision rather than overwriting it. An LLM formatter is optional and independent of laugh detection. Silence/music can produce transcription hallucinations; review remains necessary.

## Acceptance checks

- Permission denied, unavailable microphone, repeated Stop, interruption, cancel, and full disk have clear outcomes.
- A recording survives restart; switching notes during capture attaches only to the chosen destination.
- Import/insert/remove/undo/save/reopen round-trip without losing audio metadata.
- Legacy playback, copied-note independent audio, malicious paths, and symlink escape regression checks pass.
- Several clips export in the right order; boundaries and source offsets match playback.
- Detach from one note keeps other references playable; purging never deletes the legacy export.
- Transcription cancellation leaves the original intact; formatting cannot silently overwrite newer edits.

## Sources and implementation references

- AVFoundation export/trimming: https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/AVFoundationPG/Articles/05_Export.html
- Export session capability checks: https://developer.apple.com/documentation/avfoundation/avassetexportsession
- Local transcription backend: https://github.com/ggml-org/whisper.cpp
