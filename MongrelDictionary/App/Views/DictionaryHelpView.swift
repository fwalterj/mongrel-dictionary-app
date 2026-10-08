import SwiftUI
import MongrelDictionaryCore

struct DictionaryHelpView: View {
    @ObservedObject private var appearance = MongrelAppearancePreferences.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if DictionaryCorpusEdition.isPublicCore {
                    Text(DictionaryCorpusEdition.coreDescription)
                        .foregroundStyle(DesignTokens.textPrimary)
                    if let notices = DictionaryCorpusEdition.noticesURL {
                        Link("Corpus sources, licenses, and changes", destination: notices)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    DictionarySectionEyebrow(text: "Lookup Help")
                    Text("Shortcuts for the Reference Desk")
                        .font(.system(size: 26, weight: .semibold, design: .serif))
                        .foregroundStyle(DesignTokens.chromeText)
                    Text("Everything here is local. These keys are the fastest way through a lookup without taking your hands off the keyboard.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(DesignTokens.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                helpSection(title: "Search", rows: [
                    ("/ or Command-L", "Focus the search field and select the current query"),
                    ("Tab", "Complete the first longer suggestion. Recents stay clean if a still-longer word remains."),
                    ("Return", "Commit the current lookup. An empty field keeps the last cards."),
                    ("Command-Return", "Search now"),
                    ("Command-R", "Retry the current lookup, skipping the cache"),
                    ("Search ✕", "Clear the field only. Last results stay until you clear the desk."),
                    ("Shift-Command-K", "Clear the desk and lookup history"),
                ])

                helpSection(title: "Modes and history", rows: [
                    (DictionaryCorpusEdition.isPublicCore ? "Command-1 and 2" : "Command-1 to 4", DictionaryCorpusEdition.isPublicCore ? "Define and Synonyms — other modes are not included in Core Beta" : "Define, Synonyms, Translation, Slang — reuses the last lookup if the field is empty"),
                    ("Command-[ and ]", "Back and forward through committed lookups"),
                    ("Shift-Command-V", "Paste and look up"),
                    ("Option-Command-L", "Look up the highlighted text, not the clipboard"),
                    ("Shift-Command-Space", "Open Quick Lookup")
                ])

                helpSection(title: "Reading", rows: [
                    ("Command-Up / Down", "Move result focus"),
                    ("Command-E", "Expand or collapse the focused result"),
                    ("Command-D", "Save or remove the term on the desk"),
                    ("Command-C", "Copy the focused result, or the selected definition text"),
                    ("Shift-Command-C", "Copy the search package"),
                    ("Escape", "Release card focus and return to search")
                ])
            }
            .padding(28)
        }
        .background(DictionaryCanvasBackground())
        .frame(minWidth: 460, minHeight: 520)
    }

    private func helpSection(title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DictionarySectionEyebrow(text: title)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows, id: \.0) { shortcut, detail in
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text(shortcut)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(DesignTokens.textPrimary)
                            .frame(width: 168, alignment: .leading)
                        Text(detail)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(DesignTokens.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassChromeBackground(style: .card, cornerRadius: 18)
        }
    }
}
