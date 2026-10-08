import AppKit
import MongrelDictionaryCore
import SwiftUI

struct QuickLookupView: View {
    @EnvironmentObject private var session: DictionarySession
    @ObservedObject private var appearance = MongrelAppearancePreferences.shared
    @Environment(\.openWindow) private var openWindow
    @FocusState private var searchFocused: Bool
    @State private var copiedCardID: String?

    /// Quick Lookup is a glance, not a reading session. It shows the strongest
    /// handful of results and defers the rest to the full window.
    private let visibleResultLimit = 8

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DesignTokens.separator)
            results
            Divider().overlay(DesignTokens.separator)
            footer
        }
        .background(DictionaryCanvasBackground())
        .frame(minWidth: 560, minHeight: 500)
        .onAppear { searchFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: .mongrelFocusSearch)) { _ in
            focusSearchAndSelectQuery()
        }
        .onCopyCommand {
            copyVisibleSelectionOrCard()
        }
        .onKeyPress("/") {
            if searchFocused || DictionaryClipboard.hasSelectedText() {
                return .ignored
            }
            focusSearchAndSelectQuery()
            return .handled
        }
        .onKeyPress(.escape) {
            searchFocused = true
            return .handled
        }
    }

    private func focusSearchAndSelectQuery() {
        searchFocused = true
        DictionaryClipboard.selectAllInFocusedTextView()
    }

    private func copyVisibleSelectionOrCard() -> [NSItemProvider] {
        if let selected = DictionaryClipboard.selectedString() {
            DictionaryClipboard.copy(selected)
            return [NSItemProvider(object: selected as NSString)]
        }
        guard let card = session.resultCards.first else { return [] }
        DictionaryClipboard.copy(DictionaryResultPresentation.plainText(for: card))
        copiedCardID = card.id
        return [NSItemProvider(object: DictionaryResultPresentation.plainText(for: card) as NSString)]
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Quick Lookup", systemImage: "book.closed.fill")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignTokens.chromeText)
                Spacer()
                if session.isSearching {
                    ProgressView().controlSize(.small).tint(DesignTokens.accent)
                } else if session.hasSearched {
                    Text("\(session.lastResultCount) results · \(session.lastSearchDurationMS) ms")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(DesignTokens.textMuted)
                }
            }

            searchField

            if let notice = session.savedShelfNotice {
                Text(notice)
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if session.lastSearchTimedOut {
                HStack {
                    Text(session.lastTimedOutTerm.isEmpty
                         ? "The last lookup was stopped."
                         : "Lookup stopped for “\(session.lastTimedOutTerm)”.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(DesignTokens.textMuted)
                    Spacer()
                    if session.canRetryLookup {
                        Button("Retry") {
                            session.retryCurrentLookup()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(DesignTokens.accent)
                    }
                }
            }

            if session.isShowingLastLookupWithoutQuery {
                HStack {
                    Text("Still showing “\(session.lastSearchedTerm)”.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(DesignTokens.textMuted)
                    Spacer()
                    Button("Restore") {
                        session.restoreDisplayedQuery()
                        focusSearchAndSelectQuery()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignTokens.accentDim)
                    .help("Put the last lookup back in the search field.")
                    Button("Clear desk") {
                        session.clearQuery()
                        searchFocused = true
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignTokens.accentDim)
                    .help("Clear the query and the visible results (Shift-Command-K).")
                }
            }

            if !session.isLookupSettled, let completion = session.inlineCompletion {
                Button {
                    session.acceptInlineCompletion()
                } label: {
                    Label("Tab to complete to “\(completion)”", systemImage: "arrow.right.to.line")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(DesignTokens.accentDim)
                }
                .buttonStyle(.plain)
            }

            if !session.isLookupSettled, !session.suggestions.isEmpty {
                DictionaryTermChips(terms: Array(session.suggestions.prefix(6)), tone: .accent, symbol: nil) {
                    session.selectTerm($0)
                }
            }

            if !session.isLookupSettled, !session.didYouMean.isEmpty {
                DictionaryTermChips(terms: Array(session.didYouMean.prefix(6)), tone: .neutral, symbol: nil) {
                    session.selectTerm($0)
                }
            }

            Picker("Lookup mode", selection: Binding(
                get: { session.queryIntent },
                set: { session.selectIntent($0) }
            )) {
                ForEach(DictionaryCorpusEdition.availableIntents) { intent in
                    Label(intent.rawValue, systemImage: intent.systemImage).tag(intent)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(18)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DesignTokens.accent)
                .accessibilityHidden(true)

            TextField("Word or phrase", text: $session.query)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(DesignTokens.chromeText)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .onChange(of: session.query) { _, _ in session.queryDidChange() }
                .onSubmit { session.previewSearch() }
                .onKeyPress(.tab) {
                    guard session.inlineCompletion != nil else { return .ignored }
                    session.acceptInlineCompletion()
                    return .handled
                }
                .accessibilityLabel("Search term")
                .help("Type three letters for live results. Return commits the lookup.")

            if session.hasQuery {
                Button {
                    session.clearSearchField()
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignTokens.textMuted)
                .accessibilityLabel("Clear the search field")
                .help("Clear the typed query. The last results stay until you clear the desk.")
            }

            Button {
                if session.isSearching {
                    session.cancelSearch()
                } else {
                    session.previewSearch()
                }
            } label: {
                Image(systemName: session.isSearching ? "xmark.circle.fill" : "arrow.right.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(session.hasQuery || session.isSearching ? DesignTokens.accent : DesignTokens.textDisabled)
            .disabled(!session.hasQuery && !session.isSearching)
            .accessibilityLabel(session.isSearching ? "Cancel this lookup" : "Look up this term")
            .help(session.isSearching ? "Stop the running search." : "Run the lookup.")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassChromeBackground(
            style: .elevated,
            cornerRadius: 15,
            isEmphasised: searchFocused
        )
    }

    @ViewBuilder
    private var results: some View {
        if session.resultCards.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(session.resultCards.prefix(visibleResultLimit)) { card in
                        resultCard(card)
                    }

                    if session.resultCards.count > visibleResultLimit {
                        Button {
                            openWindow(id: "dictionary-main")
                            NSApp.activate(ignoringOtherApps: true)
                        } label: {
                            Label(
                                "Open the full dictionary for all \(session.resultCards.count) results",
                                systemImage: "arrow.up.left.and.arrow.down.right"
                            )
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(DesignTokens.accentDim)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(18)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: session.hasSearched ? "questionmark.text.page" : "text.book.closed")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(DesignTokens.accentDim)
                .accessibilityHidden(true)
            Text(session.hasSearched ? "No local result" : "Ready for an offline lookup")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(DesignTokens.textPrimary)
            Text(
                session.hasSearched
                    ? "Try a nearby spelling or another lookup mode."
                    : "Paste with Shift-Command-V, type a term, or select text in another app and use Services."
            )
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .multilineTextAlignment(.center)
            .foregroundStyle(DesignTokens.textMuted)
            .frame(maxWidth: 390)

            if !session.didYouMean.isEmpty {
                DictionaryTermChips(terms: session.didYouMean, tone: .neutral, symbol: nil) {
                    session.selectTerm($0)
                }
                .frame(maxWidth: 420)
            } else if !session.favoriteTerms.isEmpty || !session.recentTerms.isEmpty {
                DictionaryTermChips(terms: quickTerms, tone: .subtle, symbol: nil) {
                    session.selectTerm($0)
                }
                .frame(maxWidth: 420)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(22)
    }

    private var quickTerms: [String] {
        Array((session.favoriteTerms + session.recentTerms).uniquedTerms().prefix(6))
    }

    private func summaryText(for card: DictionarySession.ResultCard) -> Text {
        if session.isLookupSettled {
            Text(DictionaryTextHighlighter.highlight(card.summary, matching: session.lastSearchedTerm))
        } else {
            Text(card.summary)
        }
    }

    private func resultCard(_ card: DictionarySession.ResultCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.title)
                        .readingType(size: 20, weight: .semibold, design: .serif)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .readingBloom(.title)
                        .textSelection(.enabled)
                    if !session.lastSearchedTerm.isEmpty,
                       card.title.compare(session.lastSearchedTerm, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame {
                        Button("Look up this headword") {
                            session.selectTerm(card.title)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(DesignTokens.accentDim)
                    }
                }

                Spacer()

                Button {
                    DictionaryClipboard.copy(DictionaryResultPresentation.plainText(for: card))
                    copiedCardID = card.id
                } label: {
                    Image(systemName: copiedCardID == card.id ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.plain)
                .foregroundStyle(copiedCardID == card.id ? DesignTokens.accent : DesignTokens.textMuted)
                .accessibilityLabel("Copy \(card.title)")
                .help("Copy this entry as plain text.")
            }

            Label(DictionaryResultPresentation.identityBadge(for: card), systemImage: "building.columns")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(DesignTokens.textSecondary)

            summaryText(for: card)
                .readingType(size: 13, lineSpacing: 3, design: .rounded)
                .foregroundStyle(DesignTokens.textPrimary)
                .readingBloom(.reading)
                .textSelection(.enabled)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)

            if !card.relatedTerms.isEmpty {
                DictionaryTermChips(
                    terms: Array(card.relatedTerms.prefix(4)),
                    tone: .subtle,
                    symbol: nil
                ) {
                    session.selectTerm($0)
                }
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(isSelected: false, cornerRadius: 16)
        .contextMenu {
            Button("Copy Entry") {
                DictionaryClipboard.copy(DictionaryResultPresentation.plainText(for: card))
                copiedCardID = card.id
            }
            Button("Open in Reference Desk") {
                session.selectTerm(card.title)
                openWindow(id: "dictionary-main")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(card.title), from \(card.source)")
    }

    private var footer: some View {
        HStack {
            Text("Shift-Command-Space opens Quick Lookup · Shift-Command-V pastes and searches")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(DesignTokens.textMuted)
            Spacer()
            Button("Open Full Dictionary") {
                openWindow(id: "dictionary-main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(DesignTokens.accent)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}
