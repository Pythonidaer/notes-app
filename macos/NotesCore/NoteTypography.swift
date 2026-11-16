import AppKit

/// Point sizes and weights for each text role.
///
/// The editor is a web page, so these sizes are also written in `editor.css`.
/// A role without a Notes measurement uses the macOS Human Interface Guidelines.
enum NoteTypography {
    /// Provisional. HIG Title 1 is 22 pt with a 26 pt line height. Notes titles are bold.
    static let editorTitleSize: CGFloat = 22
    static let editorTitleWeight = NSFont.Weight.bold
    static let editorTitleLineHeight: CGFloat = 26

    /// Provisional. HIG headline is 13 pt bold with a 16 pt line height.
    static let editorHeadingSize: CGFloat = 13
    static let editorHeadingWeight = NSFont.Weight.bold
    static let editorHeadingLineHeight: CGFloat = 16

    /// Provisional. Body size, semibold. The HIG has no subheading style.
    static let editorSubheadingSize: CGFloat = 13
    static let editorSubheadingWeight = NSFont.Weight.semibold
    static let editorSubheadingLineHeight: CGFloat = 16

    /// Provisional. HIG body is 13 pt regular with a 16 pt line height.
    static let editorBodySize: CGFloat = 13
    static let editorBodyWeight = NSFont.Weight.regular
    static let editorBodyLineHeight: CGFloat = 16

    /// Provisional. System monospaced design at the body size.
    static let editorMonospacedSize: CGFloat = 13
    static let editorMonospacedWeight = NSFont.Weight.regular

    /// Provisional. HIG subhead is 11 pt with a 14 pt line height. Centered above the title.
    static let editorDateSize: CGFloat = 11
    static let editorDateWeight = NSFont.Weight.regular
    static let editorDateLineHeight: CGFloat = 14

    /// Provisional. HIG Title 3 is 15 pt. Bold keeps the label heavier than a note title.
    static let noteListSectionSize: CGFloat = 15
    static let noteListSectionWeight = NSFont.Weight.bold

    /// Provisional. 13 pt semibold, one step under the section label.
    static let noteListTitleSize: CGFloat = 13
    static let noteListTitleWeight = NSFont.Weight.semibold

    /// Provisional. HIG callout is 12 pt regular.
    static let noteListPreviewSize: CGFloat = 12
    static let noteListPreviewWeight = NSFont.Weight.regular

    /// Provisional. The folder under a search result, one step under the preview.
    static let noteListFolderSize: CGFloat = 11
    static let noteListFolderWeight = NSFont.Weight.regular

    /// Provisional. HIG body is 13 pt regular.
    static let folderNameSize: CGFloat = 13
    static let folderNameWeight = NSFont.Weight.regular

    /// Provisional. Monospaced digits at the folder name size.
    static let folderCountSize: CGFloat = 13
    static let folderCountWeight = NSFont.Weight.regular

    /// Measured in Notes. The note bar search field uses the system control font.
    static let noteBarSearchSize: CGFloat = 13
    static let noteBarSearchWeight = NSFont.Weight.regular

    /// Measured in Notes. A row in the search field's suggestion menu.
    static let noteSearchSuggestionSize: CGFloat = 13
    static let noteSearchSuggestionWeight = NSFont.Weight.regular

    static var editorTitle: NSFont {
        NSFont.systemFont(ofSize: editorTitleSize, weight: editorTitleWeight)
    }

    static var editorHeading: NSFont {
        NSFont.systemFont(ofSize: editorHeadingSize, weight: editorHeadingWeight)
    }

    static var editorSubheading: NSFont {
        NSFont.systemFont(ofSize: editorSubheadingSize, weight: editorSubheadingWeight)
    }

    static var editorBody: NSFont {
        NSFont.systemFont(ofSize: editorBodySize, weight: editorBodyWeight)
    }

    static var editorMonospaced: NSFont {
        NSFont.monospacedSystemFont(ofSize: editorMonospacedSize, weight: editorMonospacedWeight)
    }

    static var editorDate: NSFont {
        NSFont.systemFont(ofSize: editorDateSize, weight: editorDateWeight)
    }

    static var noteListSection: NSFont {
        NSFont.systemFont(ofSize: noteListSectionSize, weight: noteListSectionWeight)
    }

    static var noteListTitle: NSFont {
        NSFont.systemFont(ofSize: noteListTitleSize, weight: noteListTitleWeight)
    }

    static var noteListPreview: NSFont {
        NSFont.systemFont(ofSize: noteListPreviewSize, weight: noteListPreviewWeight)
    }

    static var noteListFolder: NSFont {
        NSFont.systemFont(ofSize: noteListFolderSize, weight: noteListFolderWeight)
    }

    static var folderName: NSFont {
        NSFont.systemFont(ofSize: folderNameSize, weight: folderNameWeight)
    }

    static var folderCount: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: folderCountSize, weight: folderCountWeight)
    }

    static var noteBarSearch: NSFont {
        NSFont.systemFont(ofSize: noteBarSearchSize, weight: noteBarSearchWeight)
    }

    static var noteSearchSuggestion: NSFont {
        NSFont.systemFont(ofSize: noteSearchSuggestionSize, weight: noteSearchSuggestionWeight)
    }

    /// CSS `font-weight` for a system font weight.
    static func cssWeight(_ weight: NSFont.Weight) -> Int {
        if weight >= .bold { return 700 }
        if weight >= .semibold { return 600 }
        if weight >= .medium { return 500 }
        return 400
    }
}
