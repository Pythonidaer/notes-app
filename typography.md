## Reference

Match Apple Notes on the target macOS release. Record the macOS version, Notes **Default text size** setting, and appearance used for the comparison. Use Apple’s macOS Human Interface Guidelines as the fallback for any role that still needs measurement.

## Typeface and roles

Use the native macOS system font through SwiftUI `Font.system` or AppKit `NSFont.systemFont`. For a monospaced role, use the system monospaced design where the reference calls for it. Keep the system’s default character spacing unless a controlled comparison shows a consistent difference.

| Surface | Roles to document | What to compare |
|---|---|---|
| Note editor | Title, Heading, Subheading, Body, and Monospaced if supported | Point size, weight, line height, paragraph spacing, and wrapping |
| Note list | Note title, preview, date, and section label | Size, weight, hierarchy, truncation, and selected state |
| Folder sidebar | Folder name, section label, and count if displayed | Size, weight, alignment, and selected state |
| Toolbar and search | Native control labels and search text | Control defaults, sizing, and alignment |

Use the macOS HIG values as provisional references. Body is 13 pt regular with a 16 pt line height. Headline is 13 pt bold with a 16 pt line height. Title 1, 2, and 3 are 22, 17, and 15 pt regular with line heights of 26, 22, and 20 pt. These are platform styles. Record the measured Notes values separately for each matching role.

## Implementation rules

- Reuse the project’s existing typography definitions. Put any new values in one location named for their role, such as `noteListTitle` or `editorBody`.
- Use native control defaults where they match the reference. Apply explicit font values at the relevant role when measurement justifies the override.
- Keep font size, line height, spacing between paragraphs, and editor insets distinct. Diagnose wrapping and baseline differences at the same editor width.
- Preserve user-applied rich text and existing text-size behavior. Style the editor’s default text and explicitly styled ranges through the editor’s existing formatting path.
- Mark each recorded role as **measured in Notes** or **provisional**. Include the reference setting or source used for each measured value.

## Current roles

Compared on macOS 26.6.2. No Notes screenshot or Default text size setting was available, and Notes had no on-screen window, so nothing below is measured in Notes. The editor is TipTap in a web view, not an `NSTextView`. Sizes live in `macos/NotesCore/NoteTypography.swift` and the same editor numbers are in `macos/editor/editor.css`. One CSS pixel is one point in that web view.

| Role | Value in the app | Status | Source |
|---|---|---|---|
| Editor title | 22 pt bold, 26 pt line height | Provisional | HIG Title 1 size and line height. Weight is bold. |
| Editor heading | 13 pt bold, 16 pt line height | Provisional | HIG headline |
| Editor subheading | 13 pt semibold, 16 pt line height | Provisional | No HIG subheading style. Body size, semibold. |
| Editor body | 13 pt regular, 16 pt line height | Provisional | HIG body |
| Editor monospaced | 13 pt regular, system monospaced | Provisional | Body size, monospaced design |
| Editor paragraph spacing | 0.45 rem between paragraphs. Title margin 8 px 0 12 px. Heading margin 0.7 rem 0 0.35 rem. | Provisional | Existing spacing. Not measured. |
| Note list section label | 15 pt bold, label color, hairline under the label | Provisional | HIG Title 3 size. Bold, not the HIG regular weight. |
| Note list title | 13 pt semibold, truncates to one line | Provisional | Existing list title |
| Note list preview and date | 12 pt regular, secondary label color, one line | Provisional | HIG callout |
| Folder name | 13 pt regular | Provisional | HIG body |
| Folder count | 13 pt regular monospaced digits | Provisional | Folder name size |
| Folder section label | Not in this sidebar | — | — |
| Note date | 11 pt regular, 14 pt line height, centered, secondary color, above the title. It scrolls with the note. | Provisional | HIG subhead. Apple Notes layout. Not measured in Notes. |
| Note bar search | Capsule, 34 pt tall and 280 pt wide. Dark fill `rgb(25, 29, 30)`. Focus ring `rgb(121, 82, 129)`. Magnifying glass, placeholder Search, clear button once there is text. A click focuses the field. | Measured in Notes | Dark-mode Notes screenshot on macOS 26.6.2. |
| Note bar search suggestion | 13 pt regular, system font. Menu fill `rgb(40, 43, 45)` in dark mode. | Measured in Notes | Dark-mode Notes search menu. Point size from the system control font. |
| Note list search match | Magenta on the matched letters, `rgb(206, 112, 214)` in dark mode. | Measured in Notes | Dark-mode Notes search results. |
| Note list folder | 11 pt regular, secondary, with a folder icon under a search result. | Provisional | Notes search row. Point size not measured. |
| New Folder field | System text field font | Provisional | Native control default |