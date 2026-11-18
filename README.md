# Notes

A local Mac app for the imported Pythonidaer library. The window has three columns: folders, the note list, and the note. A folder can contain folders and notes. A note is in one folder, or in none. All notes is a view of every note.

New notes go in the selected folder. When All notes is selected, a new note goes in Comedy. Deleting a folder asks first, then deletes that folder, the folders inside it, and their notes. Audio files stay on disk.

The database is `~/Library/Application Support/com.pythonidaer.notes/notes.sqlite`. Audio files stay in `/Users/johnnyhammond/Documents/notesnursery/notes-export/note-audio` and are not copied. The export is imported once. Playback uses the last segment of the storage path and checks that the file stays in that folder.

## Build

Quit this app, then run `npm run app`. That is the Xcode build and open in one command. It sets `DEVELOPER_DIR` to `/Applications/Xcode.app/Contents/Developer`, builds the Notes scheme into `macos/.derived`, and opens `macos/.derived/Build/Products/Debug/Notes.app`. The Xcode build also rebuilds the editor. `npm run build` builds only the editor. Do not quit `/System/Applications/Notes.app`.

The note bar has a Search field on the trailing side. It is the library search for the note list, and the only search field. It is the Apple Notes capsule: a magnifying glass, the placeholder Search, and a clear button once there is text. A click focuses it. While the field is empty, the suggestions menu lists Notes with Checklists and Notes with Attachments. Typing filters the list in the selected folder. The clear button empties the query and the list returns to the folder. Search matches the title, the note text, and attachment names, including an audio filename. Each word matches on its own. Command-F finds inside the open note and does not filter the list. Recording, OCR, cards, Voice Recorder, Memorize by Heart, Bluetooth sync, and laugh-aware transcription stay out. Share and lock stay out.

## Status

Folders replaced labels. The open database was migrated in place: 158 notes, 20 root folders, no label tables, 43 audio display names. Comedy is still `4102f124-0352-4bb6-afef-05f745b0bd82`. A note that had Comedy is in Comedy. Otherwise it is in its earliest former label. One note has no folder and still appears in All notes. Do not migrate or import again. Do not modify Notes Nursery. Do not create, migrate, or import `notes.sqlite`.

Swift is the app, bundle `com.pythonidaer.notes.swift`. It refuses to create, migrate, or import the database. Quit this app and run `npm run app` to build and open it. Do not quit `/System/Applications/Notes.app`.

A save writes `title`, `body_html`, `created_at_source`, and `updated_at`. It does not write `modified_at_source`, so the list date stays the original Apple date.

The window has three columns. A folder row selects across the whole row, and only the current folder keeps the accent pill. A note opens on click. Dragging a note onto a folder, or a folder beside another folder, saves. Weekday dates such as "Wednesday, June 3, 2026 at 8:10:03 PM" group with the month instead of Unknown Date. Section labels such as Previous 30 Days and September are 15pt bold, larger than the 13pt semibold note titles, and a hairline sits under each label. The date and the opening text are 12pt regular in a lighter gray. Each note row shows the title, then one line with a short date such as 11/6/26 and the opening text, cut off at the edge. A hairline separates notes. Note titles sit farther in from the left than the section labels. The note body fills the detail panel. The date is the first line inside the note, centered, as month, day, year, at, and the time. It is small and secondary, and it scrolls with the note. It is not a pill in the toolbar. The title is the next block. It scrolls with the note and passes under the toolbar. The folder name is not shown there. In dark mode the note column is a darker gray than the note list, `rgb(30, 30, 30)`. Click the text to edit. Typing saves that note. Where a note had a filename caption such as Confidence.mp3, the note shows an audio player instead. The files stay in the export folder, and the storage path stays stable. There is no play button at the bottom right. The editor round-trip keeps tasks, colored text, and the audio figure.

One toolbar spans the note list and the note. The selected folder's name and note count sit above the list. To their right, More opens two menus. On the note side, Search is the trailing field. That field is the library search. A click focuses it, and an empty field opens the suggestions menu. While a search is active, the list title is Search and the subtitle is Found n notes, Found 1 note, or No Results. Results sit under the heading Notes. The matched letters are a distinct color. The line beside the date is the part of the note where the word was found, and the folder name sits under that. Search stays in the selected folder. All notes is still every note. Command-F opens a find and replace panel over the open note. The note starts below that panel. The panel has the find field, the match count, previous and next, Done, and Replace. Checking Replace adds a second row in the panel: a Replace field as wide as the find field, then Replace and All connected together, and Done on that row under the Replace checkbox. Replace changes the current match. All changes every match in that note. Done closes the bar, keeps the replaced text, and clears the highlights. Sort By, with an up-and-down arrow, lists Default (Date Edited), Date Edited, Date Created, and Title, then a divider, then Newest First and Oldest First. Group By Date, with a calendar, lists Default (On), On, and Off. The current choice in each group is marked. Create a note is its own button on the left of the note bar, separate from the format pill. The pill is Aa, the checklist, table, then attachment. Delete stays after the pill. Aa opens a menu and closes when Aa is clicked again. The capital A is larger than the lowercase a. Table inserts a table of two columns and two rows. Tab moves between cells and adds a row at the end. The attachment button opens a menu. The rows are Choose Photo or Video, Record Audio, and Attach File, each with its icon. Record Audio does not start a recording. The menu has bold, italic, underline, strikethrough, a highlight pencil with the current color dot beside it, Title, Heading, Subheading, Body, Monostyled, bulleted, dashed, and numbered lists, and Block Quote. Title, Heading, Subheading, and Body apply to the selected block. Title updates the title the list shows. Double-clicking the title selects that block. New folder is an icon immediately left of the sidebar collapse button. When the folder sidebar is collapsed, New Folder is hidden. Only the button that opens the sidebar stays, and it sits to the left of the folder name and the note count. New Folder opens a dialog with the name selected, Cancel, and OK. A folder created while another folder is selected is added inside that folder, at the end of that folder's children. The parent opens and the new folder is selected. With All notes selected, New Folder still adds a folder at the top level. The disclosure arrow sits beside the folder it opens, including on a nested folder. Deleting a folder stays on the folder's menu. Deleting a note stays in the current folder and selects the next note in that list. The last note selects the one before it. The only note leaves that folder selected and the list empty.

Highlight matches Apple Notes. The pencil and the current color dot stay in the top row. Hovering the dot shows a background behind it. Its help is "Choose a highlight color". Clicking the dot opens a separate menu of Purple, Pink, Orange, Mint, and Blue. Each row is a dot and the name, and the current color is marked. The pencil applies the current color. The mark sets the font to that color and the background to a lighter shade, a 15% wash of the same color. In dark mode, mint text measures about `rgb(99, 215, 195)`. Choosing the same color again removes the highlight. The name is stored as `data-color` on `<mark>`, so existing notes still round-trip. The TipTap Color extension stays so existing colored text, including `#2563eb`, still round-trips. Bare `<mark>` and the commands `"highlight"` and `"color"` do nothing.

## Apple Notes type

Apple Notes uses the system font. This app does too.

In the list, a section label such as Today, Previous 30 Days, or October is 15pt bold. It is white, like the title, and a hairline sits under it. The note title is 13pt semibold. The date and the opening text are 12pt regular, in a lighter gray.

In the note, the title is 22px bold with a 26px line height. The body is 13px regular with a 16px line height. A heading is 13px bold. A subheading is 13px semibold. Monospaced text is 13px. These sizes are the macOS Human Interface Guidelines stand-ins. None of them has been measured in Notes yet. The record is in `typography.md`. A highlight color, such as the teal on a title, is the highlight, not the title style. The date stays inside the note, centered at the top, small and secondary. Search is the trailing field on the note bar. A click focuses it. Typing filters the note list, including notes with attachments, and highlights the letters that matched. An empty field opens the suggestions menu. Command-F is a separate find and replace for the open note.

The note scrolls vertically only. A sideways trackpad swipe does not move it.

The target is `macos/`. Its editor is TipTap in `macos/editor/`, built into `macos/Notes/Editor/` by an Xcode phase: `cd "$SRCROOT/.." && npm exec vite -- --config macos/editor/vite.config.js build`. That build uses the root `node_modules`, including `vite`, `@tiptap/core`, and `dompurify`.

Swift rules go in `AGENTS.md`.

## Next

The Search field on the note bar is the library search for the note list. It is the Apple Notes capsule. A click focuses it, the suggestions menu opens while it is empty, and typing filters the list.

Test more of what is already there. Test the styling of task checkboxes and tables. Test adding an audio file. There needs to be a way to see every audio file, or at least to delete one, so that can be tested. Test recording an audio file. Recording may belong to Voice Recorder.

After that, transcription with an LLM. Then Memorize by Heart. Then look through the pieces already available and use them to figure out the LLM and Memorize by Heart. Then the LLM that tracks laughs.

Then the mobile app for Bluetooth sync. Then get the iPhone notes into this app and synced. Then figure out Bluetooth sync from the phone once that app exists. TestFlight is the open question for getting a build onto the phone.

The database has to persist across restart and shut down.

Recently Deleted can go at the bottom of the folder list. A folder needs a … button that appears on hover and opens a menu for rename and the other folder actions.

The app needs the Mac menu bar at the top of the screen while it is the active application. That is the application menu, not another control in the window toolbar.

Later: review why choosing a search suggestion always asks to allow access to Documents. Compare the checklist component and the search suggestion menu with Apple Notes.

Later: the menu bar no longer has a File menu. Review the menus, and the menu for each item, against Apple Notes, then add what this app needs of its own.

Later: closing the main window leaves no Notes menu bar to reopen it from. The menu bar switches to the next app, such as Messages or Finder, so reopening takes `npm run app`. Decide whether the close button should quit the app, or whether clicking the Dock icon should reopen the window.
