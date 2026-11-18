# Memorize by Heart

Status: proposed. A native practice feature; no audio or LLM dependency.

## Experience from the supplied references

The screenshots show a title/back button, progress bar, sequential active word with blue initial/underline, completed words in bold, masked future text, keyboard entry, and a More menu with Restart, How to play, Settings, and See target words. Completion shows recall percentage, mistakes, points, elapsed time, Play again, and Harder level.

Rebuild those interactions in Mac conventions: native practice sheet or dedicated window, physical keyboard first, accessible text size, system typography, menu commands, and visible focus. Use the screenshots as behavior/layout references, not copied artwork or an exact reconstruction of the other app's scoring. No on-screen phone keyboard on Mac. iOS can reuse the engine with a native keyboard.

## Source and session

Practice a note or selected passage. Extract readable text from structured HTML; exclude audio filenames, hidden metadata, toolbar text, and non-text attachments. Preserve paragraph breaks and punctuation for display. Capture an immutable source snapshot/hash and noteID at session start. Editing the source note later must not change a running exercise. Offer Start new version.

Proposed types:
- PracticeSource: noteID, sourceHash, plainText, tokenizationVersion.
- PracticeToken: stable index, displayText, expectedInitial, paragraphIndex, punctuation.
- PracticeSession: UUID, source snapshot/hash, difficulty, currentIndex, attempts, hintUses, activeElapsedTime, status.
- PracticeAttempt: tokenIndex, submittedCharacter, correct, hintUsed.
- PracticeResult: completedAt, wordCount, mistakes, firstAttemptCorrectCount, hints, duration, scoringVersion.

Keep PracticeEngine and tokenization Foundation-only. MemorizationCoordinator owns persistence and lifecycle. Mac and iOS views render engine state. Practice storage is separate from note body HTML.

## Explicit difficulty contract

| Level | Hint presentation |
| --- | --- |
| Easy | All words visible; emphasize the next word's initial |
| Medium | Active word visible in full; future words show first letter plus masked remaining letters |
| Hard | Future and active words masked; punctuation/paragraph boundaries remain visible |

Accepted words reveal in full and appear completed on every level. These are proposed product rules because screenshots alone do not specify every difficulty. Keep hint policy configurable without changing answer validation. See target words temporarily reveals text and records assistance; it does not advance progress.

## Tokenization and typing

MVP supports English prose. Normalize for matching without changing the displayed source. Treat contractions such as “don't” and “it’s” as one word; internal apostrophes/hyphens stay inside a word. Strip leading quotation/punctuation when finding the initial. A number token such as “2026” expects “2”. Skip punctuation-only tokens. Normalize straight/curly apostrophes and case; accented letters use a documented diacritic-insensitive comparison. Unicode graphemes must not be split into bytes.

One committed character is compared with the next expected initial. Ignore modifiers, navigation keys, and IME preedit; only committed input is an attempt. Ignore auto-repeat. A wrong initial records a mistake and leaves the position unchanged. A correct initial reveals the word and advances once. Space/Return are unnecessary and ignored. Paste is disabled for the answer control. Backspace does not erase the source or rewrite history in MVP.

Pause the elapsed timer while the app is inactive or session paused. Restart creates a new attempt after confirmation if progress exists. Escape closes/pauses; restore unfinished sessions from persisted state. Completing an empty/punctuation-only passage is prevented with a useful message.

## Progress and scoring

Progress = accepted token count / target token count. Report “first-try accuracy” = tokens answered correctly before any wrong attempt / token count × 100. Show total wrong attempts and hint uses separately. All words eventually accepted is not 100% unaided recall.

MVP points = first-try correct tokens; no hidden bonuses. A perfect recall celebration requires completion, no wrong attempts, and no hints. Do not copy inconsistent point totals from reference screenshots. Result fields and scoringVersion permit later changes without rewriting history.

## Integration and acceptance

Add Practice to a note action menu after flushing pending editor autosave or extracting the current editor snapshot. Open a separate view rather than replacing the editor document with masked text. Returning to the note restores selection and never writes practice rendering into HTML.

Test contractions, punctuation, numbers, newlines, diacritics, emoji-only text, and HTML extraction. Test same-initial consecutive words, key repeat, wrong-answer retry, hint accounting, pause/resume, source edits during practice, restart, and exact scoring. Verify keyboard navigation, VoiceOver announcements of current word/progress, Reduce Motion, light/dark mode, and large text. First-letter entry is a rehearsal aid, not proof of full word-for-word recall.
