import SwiftUI
import AppKit
import MongrelDictionaryCore

struct DictionaryContentView: View {
    @EnvironmentObject private var session: DictionarySession
    @Environment(\.openWindow) private var openWindow

    @FocusState private var searchFocused: Bool
    @State private var copiedSearchPackage = false
    @State private var copiedSearchPackageGeneration = 0

    var body: some View {
        ZStack {
            DictionaryCanvasBackground()

            NavigationSplitView {
                DictionarySidebarPane()
            } detail: {
                detailPane
            }
        }
        .onAppear {
            searchFocused = !session.hasSearched
        }
        .onReceive(NotificationCenter.default.publisher(for: .mongrelFocusSearch)) { _ in
            focusSearchAndSelectQuery()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mongrelCopySearchPackage)) { _ in
            markSearchPackageCopied()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mongrelRevealDictionaryWindow)) { _ in
            openWindow(id: "dictionary-main")
            focusSearchAndSelectQuery()
        }
        .onKeyPress("/") {
            if searchFocused || DictionaryClipboard.hasSelectedText() {
                return .ignored
            }
            focusSearchAndSelectQuery()
            return .handled
        }
        .onKeyPress(.escape) {
            NotificationCenter.default.post(name: .mongrelDismissFocus, object: nil)
            searchFocused = true
            return .handled
        }
    }

    private var detailPane: some View {
        GeometryReader { proxy in
            // The inspector is the first thing to go when the window narrows;
            // the reading column keeps its width for as long as possible.
            let showInspector = proxy.size.width >= 1220

            VStack(alignment: .leading, spacing: 22) {
                DictionaryDetailHeaderView(
                    copiedSearchPackage: copiedSearchPackage,
                    copyCurrentSearchPackage: copyCurrentSearchPackage
                )

                DictionarySearchDeckView(searchFocused: $searchFocused)

                HStack(alignment: .top, spacing: 26) {
                    DictionaryResultsColumn(centreContent: !showInspector)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    if showInspector {
                        DictionaryInspectorRail(
                            copiedSearchPackage: copiedSearchPackage,
                            copyCurrentSearchPackage: copyCurrentSearchPackage
                        )
                        .frame(width: 292)
                    }
                }
            }
            .padding(.horizontal, showInspector ? 30 : 22)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func copyCurrentSearchPackage() {
        guard session.hasSearched, !session.resultCards.isEmpty else { return }
        DictionaryClipboard.copy(session.searchPackageText)
        markSearchPackageCopied()
    }

    private func markSearchPackageCopied() {
        copiedSearchPackageGeneration += 1
        let generation = copiedSearchPackageGeneration
        copiedSearchPackage = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard generation == copiedSearchPackageGeneration else { return }
            copiedSearchPackage = false
        }
    }

    private func focusSearchAndSelectQuery() {
        searchFocused = true
        DictionaryClipboard.selectAllInFocusedTextView()
    }
}

// MARK: – Sidebar

private struct DictionarySidebarPane: View {
    @EnvironmentObject private var session: DictionarySession
    @ObservedObject private var appearance = MongrelAppearancePreferences.shared
    @State private var showAllSavedWords = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                brand
                quickReference
                if !session.hasSearched {
                    archivePulse
                }
            }
            .padding(22)
        }
        .frame(minWidth: 304, idealWidth: 328)
        .glassChromeBackground(style: .deep, cornerRadius: 0)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(DesignTokens.separator)
                .frame(width: 1)
        }
    }

    private var brand: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mongrel Dictionary")
                        .font(.system(size: session.hasSearched ? 22 : 28, weight: .semibold, design: .serif))
                        .foregroundStyle(DesignTokens.chromeText)
                        .readingBloom(.title)
                    if !session.hasSearched {
                        Text(DictionaryCorpusEdition.isPublicCore ? DictionaryCorpusEdition.coreDescription : "Offline dictionary, thesaurus, variants, antonyms, and comparative English.")
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(DesignTokens.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 8) {
                    DictionaryCapsuleBadge(
                        text: session.startup.badgeText,
                        symbol: session.startup.searchReady ? "checkmark.circle" : "clock",
                        tone: session.startup.searchReady ? .accent : .neutral
                    )
                    if !session.hasSearched {
                        DictionaryCapsuleBadge(text: "Press / to search", symbol: "slash.circle", tone: .neutral)
                    }
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                DictionarySidebarMetric(value: session.availableSourceMetricText, label: "Ready")
                DictionarySidebarMetric(value: "\(session.favoriteTerms.count)", label: "Saved")
                DictionarySidebarMetric(value: "\(session.recentTerms.count)", label: "Recent")
                DictionarySidebarMetric(value: session.wordOfDay.term.isEmpty ? "0" : "1", label: "Daily")
            }
        }
        .padding(18)
        .glassChromeBackground(style: .card, cornerRadius: DesignTokens.panelRadius)
    }

    private var quickReference: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !session.wordOfDay.term.isEmpty {
                Button {
                    session.selectTerm(session.wordOfDay.term)
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        DictionarySectionEyebrow(text: "Word of the Day")
                        Text(session.wordOfDay.term)
                            .font(.system(size: 22, weight: .semibold, design: .serif))
                            .foregroundStyle(DesignTokens.chromeText)
                        Text(session.wordOfDay.tagline)
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(DesignTokens.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .glassChromeBackground(style: .elevated, cornerRadius: DesignTokens.cardRadius)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Look up the word of the day, \(session.wordOfDay.term)")
            }

            if !session.favoriteTerms.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        DictionarySectionEyebrow(text: "Saved Shelf")
                        Spacer()
                        Text("\(session.favoriteTerms.count)")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(DesignTokens.textMuted)
                    }

                    DictionaryTermChips(
                        terms: showAllSavedWords ? session.favoriteTerms : Array(session.favoriteTerms.prefix(12)),
                        tone: .accent,
                        symbol: "star.fill",
                        removeTitle: "Remove from Saved Shelf",
                        onRemove: { session.removeFavorite($0) }
                    ) { session.selectTerm($0) }
                    if session.favoriteTerms.count > 12 {
                        Button(showAllSavedWords ? "Show fewer saved words" : "Show all \(session.favoriteTerms.count) saved words") {
                            showAllSavedWords.toggle()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .font(.system(size: 12, weight: .medium))
                    }
                    if let notice = session.savedShelfNotice {
                        Text(notice)
                            .font(.system(size: 12))
                            .foregroundStyle(DesignTokens.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !session.recentTerms.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        DictionarySectionEyebrow(text: "Recent Searches")
                        Spacer()
                        Button("Clear") { session.clearHistory() }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(DesignTokens.textMuted)
                            .help("Forget recent, popular, and Back/Forward lookup history. Keep the current result and saved words.")
                    }
                    DictionaryTermChips(
                        terms: Array(session.recentTerms.prefix(8)),
                        tone: .neutral,
                        symbol: "clock.arrow.circlepath",
                        removeTitle: "Forget this search",
                        onRemove: { session.forgetRecent($0) }
                    ) { session.selectTerm($0) }
                }
            }

            if !session.hasSearched, !session.topSearches.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    DictionarySectionEyebrow(text: "Popular Searches")

                    VStack(spacing: 8) {
                        ForEach(session.topSearches.prefix(6), id: \.term) { entry in
                            Button {
                                session.selectTerm(entry.term)
                            } label: {
                                HStack(spacing: 10) {
                                    Text(entry.term)
                                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                                        .foregroundStyle(DesignTokens.textPrimary)
                                    Spacer()
                                    Text("×\(entry.count)")
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundStyle(DesignTokens.textMuted)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .contentShape(Rectangle())
                                .glassChromeBackground(style: .elevated, cornerRadius: 14)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(entry.term), searched \(entry.count) times")
                        }
                    }
                }
            }
        }
        .padding(18)
        .glassChromeBackground(style: .card, cornerRadius: DesignTokens.panelRadius)
    }

    private var archivePulse: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                DictionarySectionEyebrow(text: "Archive")
                Spacer()
                DictionaryCapsuleBadge(
                    text: session.startup.badgeText,
                    symbol: session.startup.searchReady ? "checkmark.circle" : "clock",
                    tone: session.startup.searchReady ? .accent : .neutral
                )
            }

            Text(session.startup.detail)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(DesignTokens.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                DictionaryArchiveStatusRow(
                    label: "Lookup lane",
                    value: session.startup.searchReady ? "Ready" : "Warming",
                    state: session.startup.searchReady ? .ready : .working
                )
                DictionaryArchiveStatusRow(
                    label: "Archive inventory",
                    value: session.archiveInventoryStatusText,
                    state: session.startup.inventoryReady ? .ready : .working
                )
                DictionaryArchiveStatusRow(
                    label: "Sources ready",
                    value: session.availableSourceStatusText,
                    state: .ready
                )
                DictionaryArchiveStatusRow(
                    label: "Saved terms",
                    value: "\(session.favoriteTerms.count)",
                    state: .neutral
                )
                DictionaryArchiveStatusRow(
                    label: "Recent searches",
                    value: "\(session.recentTerms.count)",
                    state: .neutral
                )
            }
        }
        .padding(18)
        .glassChromeBackground(style: .card, cornerRadius: DesignTokens.panelRadius)
    }
}

// MARK: – Detail header

private struct DictionaryDetailHeaderView: View {
    @EnvironmentObject private var session: DictionarySession
    @ObservedObject private var appearance = MongrelAppearancePreferences.shared

    let copiedSearchPackage: Bool
    let copyCurrentSearchPackage: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                DictionarySectionEyebrow(text: session.hasSearched ? "Looking up" : "Reference Desk")

                if session.hasSearched {
                    Button {
                        session.restoreDisplayedQuery()
                        NotificationCenter.default.post(name: .mongrelFocusSearch, object: nil)
                    } label: {
                        Text(session.lastSearchedTerm)
                            .font(.system(size: 28, weight: .semibold, design: .serif))
                            .foregroundStyle(DesignTokens.chromeText)
                            .readingBloom(.title)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                    .help("Put this lookup back in the search field.")
                    .accessibilityLabel("Edit the lookup for \(session.lastSearchedTerm)")
                } else {
                    Text("Definitions.\nUsage. Contrast.")
                        .font(.system(size: 42, weight: .semibold, design: .serif))
                        .foregroundStyle(DesignTokens.chromeText)
                        .readingBloom(.title)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(DictionaryCorpusEdition.isPublicCore ? "Offline English definitions and synonyms. No account or connection needed." : "Offline local search across dictionary, thesaurus, variants, and reference notes.")
                        .font(.system(size: 13.5, weight: .medium, design: .rounded))
                        .foregroundStyle(DesignTokens.textSecondary)
                        .frame(maxWidth: 760, alignment: .leading)
                }
            }

            Spacer(minLength: 20)

            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 8) {
                    DictionaryChromeActionButton(
                        systemImage: "chevron.left",
                        title: "Back",
                        help: "Return to the previous lookup (Command-Left Bracket).",
                        enabled: session.canGoBack
                    ) {
                        session.goBack()
                    }
                    DictionaryChromeActionButton(
                        systemImage: "chevron.right",
                        title: "Forward",
                        help: "Move forward through lookup history (Command-Right Bracket).",
                        enabled: session.canGoForward
                    ) {
                        session.goForward()
                    }
                    DictionaryChromeActionButton(
                        systemImage: session.currentTermIsFavorite ? "star.fill" : "star",
                        title: session.currentTermIsFavorite ? "Saved" : "Save",
                        help: session.currentTermIsFavorite
                            ? "Remove this term from the saved shelf (Command-D)."
                            : "Add this term to the saved shelf (Command-D).",
                        enabled: !session.focusedTerm.isEmpty
                    ) {
                        session.toggleFavorite()
                    }
                    DictionaryChromeActionButton(
                        systemImage: copiedSearchPackage ? "checkmark" : "doc.on.doc",
                        title: copiedSearchPackage ? "Copied" : "Copy pack",
                        help: "Copy every result for this lookup as plain text (Shift-Command-C).",
                        enabled: session.hasSearched && !session.resultCards.isEmpty
                    ) {
                        copyCurrentSearchPackage()
                    }
                }

                HStack(spacing: 8) {
                    DictionaryCapsuleBadge(
                        text: session.startup.badgeText,
                        symbol: session.startup.searchReady ? "checkmark.circle" : "clock",
                        tone: session.startup.searchReady ? .accent : .neutral
                    )
                    DictionaryCapsuleBadge(
                        text: session.queryIntent.rawValue,
                        symbol: session.queryIntent.systemImage,
                        tone: .accent
                    )
                    if session.hasSearched {
                        DictionaryCapsuleBadge(
                            text: "\(session.lastResultCount) results",
                            symbol: "list.bullet",
                            tone: .neutral
                        )
                        DictionaryCapsuleBadge(
                            text: "\(session.lastSearchDurationMS) ms",
                            symbol: "speedometer",
                            tone: .neutral
                        )
                    }
                }
            }
        }
    }
}

// MARK: – Search deck

private struct DictionarySearchDeckView: View {
    @EnvironmentObject private var session: DictionarySession
    @ObservedObject private var appearance = MongrelAppearancePreferences.shared

    let searchFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                searchField
                searchButton
            }

            intentRow

            if session.isShowingLastLookupWithoutQuery {
                leftoverLookupHint
            }

            if !session.isLookupSettled {
                if let completion = session.inlineCompletion {
                    Button {
                        session.acceptInlineCompletion()
                    } label: {
                        Label("Tab to complete to “\(completion)”", systemImage: "arrow.right.to.line")
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(DesignTokens.accentDim)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Complete the query to \(completion)")
                }

                if session.hasQuery {
                    Text(composingStatusText)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(DesignTokens.textMuted)
                }

                if !session.startup.inventoryReady {
                    Label(session.startup.detail, systemImage: "clock")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(DesignTokens.textMuted)
                }

                if !session.suggestions.isEmpty {
                    DictionarySuggestionStrip(
                        title: "Suggestions",
                        subtitle: "Exact or nearby heads from the local lexicon",
                        symbol: "text.magnifyingglass",
                        items: session.suggestions,
                        tone: .accent
                    ) { session.selectTerm($0) }
                }

                if !session.didYouMean.isEmpty {
                    DictionarySuggestionStrip(
                        title: "Did you mean",
                        subtitle: "Recovered from typo-tolerant and phrase-aware matching",
                        symbol: "wand.and.stars",
                        items: session.didYouMean,
                        tone: .neutral
                    ) { session.selectTerm($0) }
                }
            }
        }
        .padding(session.isLookupSettled ? 14 : 20)
        .glassChromeBackground(style: .card, cornerRadius: session.isLookupSettled ? 18 : 24)
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DesignTokens.accent)
                .accessibilityHidden(true)

            TextField(
                session.isLookupSettled ? "Search" : (DictionaryCorpusEdition.isPublicCore ? "Search English words and phrases" : "Search headwords, phrases, dialect forms, translations"),
                text: $session.query
            )
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(DesignTokens.chromeText)
                .focused(searchFocused)
                .autocorrectionDisabled()
                .onSubmit { session.previewSearch() }
                .onChange(of: session.query) { _, _ in session.queryDidChange() }
                .onKeyPress(.tab) {
                    guard session.inlineCompletion != nil else { return .ignored }
                    session.acceptInlineCompletion()
                    return .handled
                }
                .accessibilityLabel("Search term")
                .help("Type three letters for live results. Return commits the lookup. Pastes longer than 240 characters are trimmed.")

            if session.hasQuery {
                Button {
                    session.clearSearchField()
                    searchFocused.wrappedValue = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DesignTokens.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear the search field")
                .help("Clear the typed query. The last results stay until you clear the desk.")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .glassChromeBackground(
            style: .elevated,
            cornerRadius: DesignTokens.cardRadius,
            isEmphasised: searchFocused.wrappedValue
        )
    }

    private var searchButton: some View {
        let isActionable = session.hasQuery || session.isSearching

        return Button {
            if session.isSearching {
                session.cancelSearch()
            } else {
                session.previewSearch()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: session.isSearching ? "xmark" : "arrow.right")
                Text(session.isSearching ? "Cancel" : "Search")
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(isActionable ? DesignTokens.onAccent : DesignTokens.textMuted)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(isActionable ? DesignTokens.accent : DesignTokens.glassElevated)
                    .overlay(Capsule().stroke(DesignTokens.borderRim, lineWidth: DesignTokens.borderWidth))
            )
        }
        .buttonStyle(.plain)
        .disabled(!isActionable)
        .help(session.isSearching ? "Stop the running search." : "Run the search (Command-Return).")
    }

    private var intentRow: some View {
        HStack(spacing: 8) {
            ForEach(Array(DictionaryCorpusEdition.availableIntents.enumerated()), id: \.element) { index, intent in
                let isSelected = session.queryIntent == intent

                Button {
                    session.selectIntent(intent)
                } label: {
                    Label(intent.rawValue, systemImage: intent.systemImage)
                        .font(.system(size: 11.5, weight: isSelected ? .bold : .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? DesignTokens.onAccent : DesignTokens.textSecondary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(isSelected ? DesignTokens.accent : DesignTokens.glassElevated)
                                .overlay(
                                    Capsule().stroke(
                                        isSelected ? DesignTokens.borderEmphasis : DesignTokens.borderRim,
                                        lineWidth: isSelected ? 1.2 : DesignTokens.borderWidth
                                    )
                                )
                        )
                }
                .buttonStyle(.plain)
                // Bold weight and an inverted fill carry the selection, so the
                // active mode is still obvious without reading the tint.
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                .help("\(session.promptText(for: intent)) (Command-\(index + 1))")
            }

            Spacer()

            if session.hasSearched {
                HStack(spacing: 10) {
                    if session.currentTermIsFavorite {
                        DictionaryCapsuleBadge(text: "Saved", symbol: "star.fill", tone: .accent)
                    }
                    Label(session.lastSearchedTerm, systemImage: "scope")
                    Text("\(session.lastResultCount) cards")
                        .monospacedDigit()
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(DesignTokens.textMuted)
            }
        }
    }

    private var composingStatusText: String {
        if session.isSearching && session.hasSearched {
            return "Updating local results as you type."
        }
        if session.hasSearched, !session.resultCards.isEmpty {
            return "Showing “\(session.lastSearchedTerm)”. Press Return to confirm the typed lookup."
        }
        return session.intentPrompt
    }

    private var leftoverLookupHint: some View {
        HStack(spacing: 12) {
            Text("Still showing “\(session.lastSearchedTerm)”.")
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(DesignTokens.textMuted)
            Spacer(minLength: 8)
            Button("Restore") {
                session.restoreDisplayedQuery()
                searchFocused.wrappedValue = true
                DictionaryClipboard.selectAllInFocusedTextView()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(DesignTokens.accentDim)
            .help("Put the last lookup back in the search field.")
            Button("Clear desk") {
                session.clearQuery()
                searchFocused.wrappedValue = true
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(DesignTokens.accentDim)
            .help("Clear the query and the visible results (Shift-Command-K).")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Still showing \(session.lastSearchedTerm)")
    }
}

// MARK: – Results

private struct DictionaryResultsColumn: View {
    @EnvironmentObject private var session: DictionarySession
    @ObservedObject private var appearance = MongrelAppearancePreferences.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var expandedCards: Set<String> = []
    @State private var focusedCardID: String?
    @State private var copiedCardID: String?
    @State private var sectionFilter: ResultSection?

    let centreContent: Bool

    private let topAnchorID = "dictionary-results-top"

    var body: some View {
        Group {
            if session.isSearching && session.resultCards.isEmpty {
                searchingPlaceholder
            } else {
                resultsScroller
            }
        }
        .onChange(of: session.resultCards.map(\.id)) { _, identifiers in
            adoptVisibleResults(identifiers)
        }
        .onChange(of: session.lastSearchedTerm) { _, _ in
            adoptVisibleResults(session.resultCards.map(\.id), preferFirst: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .mongrelFocusNextResult)) { _ in
            moveFocus(by: 1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .mongrelFocusPreviousResult)) { _ in
            moveFocus(by: -1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .mongrelToggleResultExpansion)) { _ in
            guard let focusedCardID else { return }
            toggleExpansion(focusedCardID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .mongrelDismissFocus)) { _ in
            focusedCardID = nil
        }
        .onCopyCommand {
            copyFocusedCardProviders()
        }
    }

    private var searchingPlaceholder: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProgressView()
                .tint(DesignTokens.accent)
                .scaleEffect(0.9)
            Text(session.inFlightTerm.isEmpty
                 ? "Local search in progress."
                 : "Looking up “\(session.inFlightTerm)”.")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(DesignTokens.chromeText)
            Text("Scanning local dictionary and thesaurus data.")
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(DesignTokens.textMuted)
        }
        .padding(26)
        .frame(maxWidth: 820, alignment: .leading)
        .glassChromeBackground(style: .card, cornerRadius: DesignTokens.panelRadius)
    }

    private var resultsScroller: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    Color.clear.frame(height: 0).id(topAnchorID)

                    if session.isSearching {
                        DictionarySearchRefreshBanner()
                    }

                    if session.lastSearchTimedOut {
                        DictionaryDeskNotice(
                            title: session.lastTimedOutTerm.isEmpty
                                ? "Lookup stopped"
                                : "Lookup stopped for “\(session.lastTimedOutTerm)”",
                            detail: "That search took too long, so it was cancelled. The last results are still on the desk.",
                            actionTitle: session.canRetryLookup ? "Retry" : nil,
                            action: session.canRetryLookup ? { session.retryCurrentLookup() } : nil
                        )
                    }

                    if session.hiddenResultCount > 0 {
                        DictionaryDeskNotice(
                            title: "Showing the strongest \(session.resultCards.count) results",
                            detail: "\(session.hiddenResultCount) lower-ranked matches stay out of the reading column."
                        )
                    }

                    if session.resultCards.isEmpty {
                        if session.hasSearched {
                            noResultsState
                        } else {
                            emptyState
                        }
                    } else {
                        if groupedResultCards.count > 1 {
                            DictionaryResultSectionFilter(
                                groups: groupedResultCards,
                                selection: $sectionFilter
                            )
                        }

                        ForEach(visibleGroups) { group in
                            Section {
                                VStack(alignment: .leading, spacing: 14) {
                                    ForEach(group.cards) { card in
                                        DictionaryResultCardView(
                                            card: card,
                                            matchedTerm: session.lastSearchedTerm,
                                            highlightMatches: session.isLookupSettled,
                                            isExpanded: expandedCards.contains(card.id),
                                            isFocused: focusedCardID == card.id,
                                            isCopied: copiedCardID == card.id,
                                            isSaved: session.isFavorite(card.title),
                                            onFocus: { focusedCardID = card.id },
                                            onToggleExpansion: { toggleExpansion(card.id) },
                                            onToggleSave: { session.toggleFavorite(term: card.title) },
                                            onCopy: { copy(card) },
                                            onSelectTerm: { session.selectTerm($0) },
                                            onSearchWithIntent: { intent in
                                                session.selectTerm(card.title, searchImmediately: false)
                                                session.selectIntent(intent)
                                            }
                                        )
                                        .id(card.id)
                                    }
                                }
                            } header: {
                                DictionaryResultSectionHeader(
                                    section: group.section,
                                    count: group.cards.count
                                )
                                .padding(.bottom, 4)
                            }
                        }
                    }
                }
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: centreContent ? .center : .leading)
                .padding(.bottom, 26)
            }
            .onChange(of: session.isSearching) { _, isSearching in
                guard isSearching else { return }
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    proxy.scrollTo(topAnchorID, anchor: .top)
                }
            }
            .onChange(of: focusedCardID) { _, identifier in
                guard let identifier else { return }
                if reduceMotion {
                    proxy.scrollTo(identifier, anchor: .center)
                } else {
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(identifier, anchor: .center)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 18) {
            DictionarySectionEyebrow(text: "Archive")
            Text("Offline reference index.")
                .font(.system(size: 28, weight: .semibold, design: .serif))
                .foregroundStyle(DesignTokens.chromeText)
                .readingBloom(.title)

            Text(DictionaryCorpusEdition.isPublicCore ? "English words and phrases. Definitions and synonyms. Type three letters to begin; Return keeps the lookup in history." : "Headwords. Phrases. Dialect forms. Translations. Type three letters and results begin to fill.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(DesignTokens.textSecondary)
                .frame(maxWidth: 640, alignment: .leading)

            HStack(spacing: 12) {
                DictionarySidebarMetric(value: session.availableSourceMetricText, label: "Sources")
                DictionarySidebarMetric(value: "\(session.favoriteTerms.count)", label: "Saved")
                DictionarySidebarMetric(value: session.wordOfDay.term.isEmpty ? "0" : "1", label: "Focus")
            }

            if !session.wordOfDay.term.isEmpty {
                Button {
                    session.selectTerm(session.wordOfDay.term)
                } label: {
                    Label("Start with today’s word, \(session.wordOfDay.term)", systemImage: "sun.max")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(DesignTokens.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Look up the word of the day, \(session.wordOfDay.term)")
            }

            if !session.recentTerms.isEmpty {
                DictionarySuggestionStrip(
                    title: "Pick up where you left off",
                    subtitle: "Recent lookups",
                    symbol: "clock.arrow.circlepath",
                    items: Array(session.recentTerms.prefix(6)),
                    tone: .neutral
                ) { session.selectTerm($0) }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassChromeBackground(style: .card, cornerRadius: 24)
    }

    private var noResultsState: some View {
        VStack(alignment: .leading, spacing: 16) {
            DictionarySectionEyebrow(text: "No match")
            Text("No results for “\(session.lastSearchedTerm)”.")
                .font(.system(size: 26, weight: .semibold, design: .serif))
                .foregroundStyle(DesignTokens.chromeText)
                .readingBloom(.title)

            Text("Check spelling, try a root form, or use a nearby suggestion.")
                .font(.system(size: 13.5, weight: .medium, design: .rounded))
                .foregroundStyle(DesignTokens.textSecondary)
                .frame(maxWidth: 660, alignment: .leading)

            if session.canRetryLookup {
                Button("Search again") {
                    session.retryCurrentLookup()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(DesignTokens.accent)
                .help("Run this lookup again, skipping the local cache (Command-R).")
            }

            if !session.didYouMean.isEmpty {
                DictionarySuggestionStrip(
                    title: "Nearby suggestions",
                    subtitle: "Closest indexed terms",
                    symbol: "wand.and.stars",
                    items: session.didYouMean,
                    tone: .neutral
                ) { session.selectTerm($0) }
            } else if !session.recentTerms.isEmpty || !session.favoriteTerms.isEmpty {
                DictionarySuggestionStrip(
                    title: "Try a known term",
                    subtitle: "Saved and recent lookups",
                    symbol: "clock.arrow.circlepath",
                    items: Array((session.favoriteTerms + session.recentTerms).uniquedTerms().prefix(6)),
                    tone: .neutral
                ) { session.selectTerm($0) }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassChromeBackground(style: .card, cornerRadius: 24)
    }

    private var groupedResultCards: [ResultCardSectionGroup] {
        var groups: [ResultCardSectionGroup] = []
        for card in session.resultCards {
            let section = DictionaryResultPresentation.section(for: card)
            if let lastIndex = groups.indices.last, groups[lastIndex].section == section {
                groups[lastIndex].cards.append(card)
            } else {
                groups.append(ResultCardSectionGroup(section: section, cards: [card]))
            }
        }
        return groups
    }

    private var visibleGroups: [ResultCardSectionGroup] {
        guard let sectionFilter else { return groupedResultCards }
        let filtered = groupedResultCards.filter { $0.section == sectionFilter }
        return filtered.isEmpty ? groupedResultCards : filtered
    }

    private var visibleResultCards: [DictionarySession.ResultCard] {
        visibleGroups.flatMap(\.cards)
    }

    private func adoptVisibleResults(_ identifiers: [String], preferFirst: Bool = false) {
        let live = Set(identifiers)
        expandedCards.formIntersection(live)
        if let focusedCardID, !live.contains(focusedCardID) {
            self.focusedCardID = nil
        }
        if preferFirst || focusedCardID == nil {
            focusedCardID = visibleResultCards.first?.id ?? identifiers.first
        }
        if let sectionFilter, !groupedResultCards.contains(where: { $0.section == sectionFilter }) {
            self.sectionFilter = nil
        }
        if let first = visibleResultCards.first, shouldAutoExpand(first) {
            expandedCards.insert(first.id)
        }
    }

    /// The first exact or direct card is the entry the reader came for, so it
    /// opens already expanded. Variants stay collapsed until asked for.
    private func shouldAutoExpand(_ card: DictionarySession.ResultCard) -> Bool {
        DictionaryResultPresentation.section(for: card) == .direct
            || card.chips.contains("exact hit")
            || card.chips.contains("direct note hit")
    }

    private func copyFocusedCardProviders() -> [NSItemProvider] {
        if let selected = DictionaryClipboard.selectedString() {
            DictionaryClipboard.copy(selected)
            return [NSItemProvider(object: selected as NSString)]
        }
        guard let focusedCardID,
              let card = session.resultCards.first(where: { $0.id == focusedCardID }) else {
            return []
        }
        copy(card)
        return [NSItemProvider(object: DictionaryResultPresentation.plainText(for: card) as NSString)]
    }

    private func toggleExpansion(_ identifier: String) {
        if expandedCards.contains(identifier) {
            expandedCards.remove(identifier)
        } else {
            expandedCards.insert(identifier)
        }
    }

    private func moveFocus(by offset: Int) {
        let identifiers = visibleResultCards.map(\.id)
        guard !identifiers.isEmpty else { return }
        guard let current = focusedCardID, let index = identifiers.firstIndex(of: current) else {
            focusedCardID = offset > 0 ? identifiers.first : identifiers.last
            return
        }
        let next = index + offset
        guard identifiers.indices.contains(next) else {
            NSSound.beep()
            return
        }
        focusedCardID = identifiers[next]
    }

    private func copy(_ card: DictionarySession.ResultCard) {
        DictionaryClipboard.copy(DictionaryResultPresentation.plainText(for: card))
        copiedCardID = card.id
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if copiedCardID == card.id {
                copiedCardID = nil
            }
        }
    }
}

private struct DictionaryResultCardView: View {
    @ObservedObject private var appearance = MongrelAppearancePreferences.shared

    let card: DictionarySession.ResultCard
    let matchedTerm: String
    let highlightMatches: Bool
    let isExpanded: Bool
    let isFocused: Bool
    let isCopied: Bool
    let isSaved: Bool
    let onFocus: () -> Void
    let onToggleExpansion: () -> Void
    let onToggleSave: () -> Void
    let onCopy: () -> Void
    let onSelectTerm: (String) -> Void
    let onSearchWithIntent: (QueryIntent) -> Void

    private var titleDiffersFromQuery: Bool {
        !matchedTerm.isEmpty
            && card.title.compare(matchedTerm, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame
    }

    /// Collapsing is only offered when there is genuinely more to reveal.
    private var isTruncatable: Bool {
        card.summary.count > 280 || card.summary.components(separatedBy: "\n").count > 5
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerRow
            definition
            descriptorGroups

            if isTruncatable {
                Button(action: onToggleExpansion) {
                    Label(
                        isExpanded ? "Show less" : "Show more",
                        systemImage: isExpanded ? "chevron.up" : "chevron.down"
                    )
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignTokens.accentDim)
                }
                .buttonStyle(.plain)
                .help("Expand or collapse this definition (Command-E).")
            }

            if let expansion = DictionaryResultPresentation.australianExpansion(for: matchedTerm) {
                Label("AU expansion: \(expansion)", systemImage: "text.bubble")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignTokens.accentDim)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(DesignTokens.glassElevated)
                            .overlay(Capsule().stroke(DesignTokens.borderRim, lineWidth: DesignTokens.borderWidth))
                    )
            }

            if !card.chips.isEmpty {
                DictionaryFlowLayout {
                    ForEach(Array(card.chips.prefix(6)).uniquedTerms(), id: \.self) { chip in
                        DictionaryCapsuleBadge(
                            text: DictionaryResultPresentation.chipTitle(chip),
                            symbol: nil,
                            tone: .subtle
                        )
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .glassCard(isSelected: isFocused, cornerRadius: 24)
        .simultaneousGesture(TapGesture().onEnded(onFocus))
        .contextMenu { cardContextMenu }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isFocused ? [.isSelected] : [])
        .accessibilityLabel("\(card.title), \(DictionaryResultPresentation.identityBadge(for: card)), from \(card.source)")
    }

    @ViewBuilder
    private var cardContextMenu: some View {
        Button(isSaved ? "Remove from Saved Shelf" : "Save Term") {
            onToggleSave()
        }
        Button("Copy Entry") {
            onCopy()
        }
        Divider()
        if let selected = DictionaryClipboard.selectedTextViewTerm() {
            Button("Look Up “\(selected)”") {
                onSelectTerm(selected)
            }
        }
        Button("Look Up “\(card.title)”") {
            onSelectTerm(card.title)
        }
        ForEach(DictionaryCorpusEdition.availableIntents.filter { $0 != .define }) { intent in
            Button("Search \(intent.rawValue.lowercased()) for “\(card.title)”") {
                onSearchWithIntent(intent)
            }
        }
    }

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    DictionarySectionEyebrow(text: "Entry")
                    if let matchBadge = DictionaryResultPresentation.matchBadge(for: card) {
                        DictionaryCapsuleBadge(text: matchBadge, symbol: "scope", tone: .neutral)
                    }
                }

                HStack(spacing: 8) {
                    DictionaryCapsuleBadge(
                        text: DictionaryResultPresentation.identityBadge(for: card),
                        symbol: "building.columns",
                        tone: .accent
                    )
                    if let firstChip = card.chips.first {
                        DictionaryCapsuleBadge(
                            text: DictionaryResultPresentation.chipTitle(firstChip),
                            symbol: nil,
                            tone: .subtle
                        )
                    }
                }

                Text(card.title)
                    .readingType(size: 30, weight: .semibold, design: .serif)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .readingBloom(.title)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                if titleDiffersFromQuery {
                    Button("Look up this headword") {
                        onSelectTerm(card.title)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignTokens.accentDim)
                    .help("Search “\(card.title)” as its own lookup.")
                    .accessibilityLabel("Look up \(card.title)")
                }
            }

            Spacer(minLength: 18)

            HStack(spacing: 8) {
                DictionaryChromeActionButton(
                    systemImage: isSaved ? "star.fill" : "star",
                    title: isSaved ? "Saved" : "Save",
                    help: isSaved
                        ? "Remove “\(card.title)” from the saved shelf."
                        : "Add “\(card.title)” to the saved shelf.",
                    enabled: true,
                    action: onToggleSave
                )
                DictionaryChromeActionButton(
                    systemImage: isCopied ? "checkmark" : "doc.on.doc",
                    title: isCopied ? "Copied" : "Copy",
                    help: "Copy this entry as plain text.",
                    enabled: true,
                    action: onCopy
                )
            }
        }
    }

    private var definitionText: Text {
        if highlightMatches {
            Text(DictionaryTextHighlighter.highlight(card.summary, matching: matchedTerm))
        } else {
            Text(card.summary)
        }
    }

    private var definition: some View {
        // Definitions take the strongest text role. This is the thing the
        // reader opened the application to read.
        definitionText
            .readingType(size: 15.5, lineSpacing: 5)
            .foregroundStyle(DesignTokens.textPrimary)
            .readingBloom(.reading)
            .lineLimit(isExpanded ? nil : 5)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var descriptorGroups: some View {
        if !card.counterparts.isEmpty {
            DictionaryDescriptorGroup(
                title: "Dialect counterparts",
                symbol: "arrow.left.arrow.right",
                items: card.counterparts.map { DictionaryDescriptor(label: $0.label, term: $0.term) },
                tone: .accent,
                action: onSelectTerm
            )
        }

        if !card.antonyms.isEmpty {
            DictionaryDescriptorGroup(
                title: "Antonyms",
                symbol: "arrow.up.arrow.down",
                items: card.antonyms.map { DictionaryDescriptor(label: nil, term: $0) },
                tone: .neutral,
                action: onSelectTerm
            )
        }

        if !card.relatedTerms.isEmpty {
            DictionaryDescriptorGroup(
                title: "Related terms",
                symbol: "link",
                items: card.relatedTerms.map { DictionaryDescriptor(label: nil, term: $0) },
                tone: .neutral,
                action: onSelectTerm
            )
        }

        if !card.topicTerms.isEmpty {
            DictionaryDescriptorGroup(
                title: "Topic mesh",
                symbol: "square.grid.2x2",
                items: card.topicTerms.map { DictionaryDescriptor(label: nil, term: $0) },
                tone: .subtle,
                action: onSelectTerm
            )
        }
    }
}

private struct DictionaryResultSectionFilter: View {
    @ObservedObject private var appearance = MongrelAppearancePreferences.shared

    let groups: [ResultCardSectionGroup]
    @Binding var selection: ResultSection?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(title: "All", symbol: "square.grid.2x2", count: groups.reduce(0) { $0 + $1.cards.count }, section: nil)
                ForEach(groups) { group in
                    filterChip(
                        title: group.section.shortTitle,
                        symbol: group.section.symbolName,
                        count: group.cards.count,
                        section: group.section
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filter results by kind")
    }

    private func filterChip(title: String, symbol: String, count: Int, section: ResultSection?) -> some View {
        let isSelected = selection == section
        return Button {
            selection = selection == section ? nil : section
        } label: {
            Label("\(title) \(count)", systemImage: symbol)
                .font(.system(size: 11, weight: isSelected ? .bold : .semibold, design: .rounded))
                .foregroundStyle(isSelected ? DesignTokens.onAccent : DesignTokens.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(isSelected ? DesignTokens.accent : DesignTokens.glassElevated)
                        .overlay(
                            Capsule().stroke(
                                isSelected ? DesignTokens.borderEmphasis : DesignTokens.borderRim,
                                lineWidth: isSelected ? 1.2 : DesignTokens.borderWidth
                            )
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("\(title), \(count) results")
        .help(isSelected && section != nil ? "Show every result again." : "Show \(title.lowercased()) results.")
    }
}

private struct DictionaryResultSectionHeader: View {
    @ObservedObject private var appearance = MongrelAppearancePreferences.shared

    let section: ResultSection
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            // The symbol, not the tint, is what separates one section from the
            // next for a reader who cannot rely on colour.
            Image(systemName: section.symbolName)
                .font(.system(size: 11, weight: .semibold))
            Text(section.title)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .kerning(0.7)
            Text("\(count)")
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(DesignTokens.textMuted)
            Spacer()
        }
        .foregroundStyle(DesignTokens.accentDim)
        .padding(.horizontal, 2)
        .padding(.top, 2)
        .accessibilityLabel("\(section.title), \(count) results")
    }
}

private struct DictionaryDeskNotice: View {
    @ObservedObject private var appearance = MongrelAppearancePreferences.shared

    let title: String
    let detail: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignTokens.textPrimary)
                Text(detail)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignTokens.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignTokens.accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassChromeBackground(style: .elevated, cornerRadius: 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(actionTitle.map { "\(title). \(detail). \($0)" } ?? "\(title). \(detail)")
    }
}

private struct DictionarySearchRefreshBanner: View {
    @EnvironmentObject private var session: DictionarySession
    @ObservedObject private var appearance = MongrelAppearancePreferences.shared

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(DesignTokens.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.inFlightTerm.isEmpty
                     ? "Refreshing local results"
                     : "Looking up “\(session.inFlightTerm)”")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignTokens.textPrimary)
                Text("Keeping the current cards visible until the replacement search finishes.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignTokens.textMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassChromeBackground(style: .elevated, cornerRadius: 16)
    }
}

// MARK: – Inspector

private struct DictionaryInspectorRail: View {
    @EnvironmentObject private var session: DictionarySession
    @ObservedObject private var appearance = MongrelAppearancePreferences.shared

    @State private var showSourceHealthDetails = false
    @State private var showDiagnosticsDetails = false
    @State private var showSessionDetails = false

    let copiedSearchPackage: Bool
    let copyCurrentSearchPackage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if session.hasSearched {
                lookupPanel
            }

            if !session.explorationGroups.isEmpty {
                DictionaryInspectorPanel(title: "Explore", subtitle: "Jump through the current result graph") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(session.explorationGroups) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(group.title)
                                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                    .foregroundStyle(DesignTokens.textPrimary)
                                DictionaryTermChips(terms: group.items, tone: .subtle, symbol: nil) {
                                    session.selectTerm($0)
                                }
                            }
                        }
                    }
                }
            }

            if !session.wordOfDay.term.isEmpty {
                DictionaryInspectorPanel(title: "Term of day", subtitle: "Pinned local entry") {
                    Button {
                        session.selectTerm(session.wordOfDay.term)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(session.wordOfDay.term)
                                .font(.system(size: 22, weight: .semibold, design: .serif))
                                .foregroundStyle(DesignTokens.chromeText)
                            Text(session.wordOfDay.tagline)
                                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                                .foregroundStyle(DesignTokens.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Look up \(session.wordOfDay.term)")
                }
            }

            Button {
                showSessionDetails.toggle()
            } label: {
                Label(
                    showSessionDetails ? "Hide session details" : "Session details",
                    systemImage: showSessionDetails ? "chevron.down" : "chart.bar"
                )
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(DesignTokens.accentDim)
            }
            .buttonStyle(.plain)
            .help("Archive health and lookup timings. Hidden while reading.")

            if showSessionDetails {
                archiveHealthPanel
                diagnosticsPanel
            }
        }
    }

    private var lookupPanel: some View {
        DictionaryInspectorPanel(
            title: "Lookup",
            subtitle: session.isLookupSettled || session.lastSearchedTerm.isEmpty
                ? "Current term"
                : "Still reading “\(session.lastSearchedTerm)”"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text(session.isLookupSettled || session.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                     ? session.lastSearchedTerm
                     : session.query.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                    .foregroundStyle(DesignTokens.chromeText)
                    .textSelection(.enabled)

                VStack(alignment: .leading, spacing: 8) {
                    DictionaryInspectorRow(
                        "Mode",
                        session.isLookupSettled ? session.lastSearchedIntent.rawValue : session.queryIntent.rawValue
                    )
                    DictionaryInspectorRow("Results", "\(session.lastResultCount)")
                    DictionaryInspectorRow("Latency", "\(session.lastSearchDurationMS) ms")
                }

                HStack(spacing: 8) {
                    DictionaryChromeActionButton(
                        systemImage: session.currentTermIsFavorite ? "star.fill" : "star",
                        title: session.currentTermIsFavorite ? "Saved" : "Save",
                        help: "Toggle the saved shelf for this term (Command-D).",
                        enabled: !session.focusedTerm.isEmpty
                    ) {
                        session.toggleFavorite()
                    }
                    DictionaryChromeActionButton(
                        systemImage: copiedSearchPackage ? "checkmark" : "doc.on.doc",
                        title: copiedSearchPackage ? "Copied" : "Copy pack",
                        help: "Copy every result for this lookup (Shift-Command-C).",
                        enabled: !session.resultCards.isEmpty,
                        action: copyCurrentSearchPackage
                    )
                    DictionaryChromeActionButton(
                        systemImage: "arrow.clockwise",
                        title: "Retry",
                        help: "Run this lookup again, skipping the local cache (Command-R).",
                        enabled: session.canRetryLookup,
                        action: { session.retryCurrentLookup() }
                    )
                }
            }
        }
    }

    private var archiveHealthPanel: some View {
        DictionaryInspectorPanel(title: "Archive health", subtitle: session.sourceHealthHeadline) {
            VStack(alignment: .leading, spacing: 10) {
                DictionaryInspectorRow("Lookup lane", session.startup.searchReady ? "Ready" : "Warming")
                DictionaryInspectorRow("Inventory", session.archiveInventoryStatusText)
                DictionaryInspectorRow("Ready", session.availableSourceStatusText)
                DictionaryInspectorRow(
                    "Partial",
                    session.sourceInventorySummary.isLoaded ? "\(session.sourceInventorySummary.partialCount)" : "Scanning"
                )
                DictionaryInspectorRow(
                    "Missing",
                    session.sourceInventorySummary.isLoaded ? "\(session.sourceInventorySummary.missingCount)" : "Scanning"
                )

                if !session.sourceHealthFocus.isEmpty {
                    Button(showSourceHealthDetails ? "Hide details" : "Show details") {
                        showSourceHealthDetails.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignTokens.accentDim)

                    if showSourceHealthDetails {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(session.sourceHealthFocus) { stat in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(DictionaryResultPresentation.inventoryTitle(for: stat.name))
                                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                        .foregroundStyle(DesignTokens.textPrimary)
                                    Text(stat.status)
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundStyle(DesignTokens.textMuted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var diagnosticsPanel: some View {
        DictionaryInspectorPanel(
            title: "Session diagnostics",
            subtitle: session.diagnostics.loadedIndices.isEmpty ? "Cold start" : "Warm path active"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                DictionaryInspectorRow("Loaded indices", "\(session.diagnostics.loadedIndices.count)")
                DictionaryInspectorRow("Inventory cache", session.diagnostics.inventoryCached ? "Warm" : "Cold")
                DictionaryInspectorRow("Avg latency", "\(session.averageSearchDurationMS) ms")
                DictionaryInspectorRow("P95 latency", "\(session.p95SearchDurationMS) ms")

                if let profile = session.diagnostics.lastSearchProfile {
                    DictionaryInspectorRow("Last query", "\(profile.term) · \(profile.intent.rawValue)")
                    DictionaryInspectorRow(
                        "Last search",
                        profile.cacheHit ? "Cache hit" : "\(profile.totalElapsedMS) ms"
                    )
                    if let slowest = profile.sourceTimings.max(by: { $0.elapsedMS < $1.elapsedMS }) {
                        DictionaryInspectorRow("Slowest source", "\(slowest.name) · \(slowest.elapsedMS) ms")
                    }
                }

                if !session.latencyHistory.isEmpty {
                    DictionaryFlowLayout {
                        ForEach(Array(session.latencyHistory.enumerated()), id: \.offset) { _, sample in
                            DictionaryCapsuleBadge(text: "\(sample) ms", symbol: nil, tone: .subtle)
                        }
                    }
                }

                if !session.diagnostics.cacheEntries.isEmpty {
                    Button(showDiagnosticsDetails ? "Hide cache details" : "Show cache details") {
                        showDiagnosticsDetails.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignTokens.accentDim)

                    if showDiagnosticsDetails {
                        cacheDetails
                    }
                }
            }
        }
    }

    private var cacheDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(session.diagnostics.cacheEntries.enumerated()), id: \.offset) { _, entry in
                DictionaryInspectorRow(entry.name, "\(entry.count)/\(entry.limit)")
            }

            if !session.diagnostics.loadedIndices.isEmpty {
                Text(
                    session.diagnostics.loadedIndices
                        .map(DictionaryResultPresentation.loadedIndexTitle)
                        .joined(separator: " • ")
                )
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(DesignTokens.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            }

            if let profile = session.diagnostics.lastSearchProfile, !profile.sourceTimings.isEmpty {
                Divider().overlay(DesignTokens.separator)
                Text("Last search source timings")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignTokens.textSecondary)
                ForEach(
                    Array(profile.sourceTimings.sorted(by: { $0.elapsedMS > $1.elapsedMS }).prefix(6).enumerated()),
                    id: \.offset
                ) { _, timing in
                    DictionaryInspectorRow(timing.name, "\(timing.elapsedMS) ms · \(timing.resultCount) hits")
                }
            }
        }
    }
}

// MARK: – Shared components

enum DictionaryCapsuleTone {
    case accent
    case neutral
    case subtle
}

struct DictionarySectionEyebrow: View {
    @ObservedObject private var appearance = MongrelAppearancePreferences.shared

    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .bold, design: .rounded))
            .kerning(1.1)
            .foregroundStyle(DesignTokens.accentDim)
    }
}

struct DictionaryCapsuleBadge: View {
    @ObservedObject private var appearance = MongrelAppearancePreferences.shared

    let text: String
    let symbol: String?
    let tone: DictionaryCapsuleTone

    init(text: String, symbol: String? = nil, tone: DictionaryCapsuleTone) {
        self.text = text
        self.symbol = symbol
        self.tone = tone
    }

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .accessibilityHidden(true)
            }
            Text(text)
        }
        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
        .foregroundStyle(tone == .accent ? DesignTokens.accent : DesignTokens.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(fill)
                .overlay(Capsule().stroke(DesignTokens.borderRim, lineWidth: DesignTokens.borderWidth))
        )
    }

    private var fill: Color {
        switch tone {
        case .accent: return DesignTokens.selectionFill
        case .neutral: return DesignTokens.glassElevated
        case .subtle: return DesignTokens.glassCard
        }
    }
}

struct DictionarySidebarMetric: View {
    @ObservedObject private var appearance = MongrelAppearancePreferences.shared

    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .monospacedDigit()
                .foregroundStyle(DesignTokens.chromeText)
            Text(label)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(DesignTokens.textMuted)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassChromeBackground(style: .elevated, cornerRadius: 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

struct DictionaryArchiveStatusRow: View {
    @ObservedObject private var appearance = MongrelAppearancePreferences.shared

    enum State {
        case ready
        case working
        case neutral

        /// Each state owns a glyph as well as a colour. A status dot alone is
        /// exactly the colour-only signal the appearance contract forbids.
        var symbol: String {
            switch self {
            case .ready: return "checkmark.circle.fill"
            case .working: return "clock.fill"
            case .neutral: return "circle.fill"
            }
        }
    }

    let label: String
    let value: String
    let state: State

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: state.symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(state == .neutral ? DesignTokens.textMuted : DesignTokens.accent)
                .accessibilityHidden(true)
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(DesignTokens.textPrimary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(state == .neutral ? DesignTokens.textSecondary : DesignTokens.accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassChromeBackground(style: .elevated, cornerRadius: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

struct DictionaryChromeActionButton: View {
    @ObservedObject private var appearance = MongrelAppearancePreferences.shared

    let systemImage: String
    let title: String
    let help: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(enabled ? DesignTokens.textPrimary : DesignTokens.textDisabled)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Capsule())
            .background(
                Capsule()
                    .fill(DesignTokens.glassElevated)
                    .overlay(Capsule().stroke(DesignTokens.borderRim, lineWidth: DesignTokens.borderWidth))
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(title)
        .help(help)
    }
}

struct DictionaryInspectorPanel<Content: View>: View {
    @ObservedObject private var appearance = MongrelAppearancePreferences.shared

    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                DictionarySectionEyebrow(text: title)
                Text(subtitle)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignTokens.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassChromeBackground(style: .card, cornerRadius: DesignTokens.panelRadius)
    }
}

struct DictionaryInspectorRow: View {
    @ObservedObject private var appearance = MongrelAppearancePreferences.shared

    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(DesignTokens.textMuted)
            Spacer()
            Text(value)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(DesignTokens.textPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

struct DictionarySuggestionStrip: View {
    @ObservedObject private var appearance = MongrelAppearancePreferences.shared

    let title: String
    let subtitle: String
    let symbol: String
    let items: [String]
    let tone: DictionaryCapsuleTone
    let action: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignTokens.textPrimary)
                Spacer()
                Text(subtitle)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignTokens.textMuted)
            }

            DictionaryTermChips(terms: items, tone: tone, symbol: nil, action: action)
        }
    }
}

struct DictionaryTermChips: View {
    let terms: [String]
    let tone: DictionaryCapsuleTone
    let symbol: String?
    var removeTitle: String = "Remove"
    var onRemove: ((String) -> Void)? = nil
    let action: (String) -> Void

    var body: some View {
        DictionaryFlowLayout {
            ForEach(terms.uniquedTerms(), id: \.self) { term in
                Button {
                    action(term)
                } label: {
                    DictionaryCapsuleBadge(text: term, symbol: symbol, tone: tone)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Look up \(term)")
                .contextMenu {
                    Button("Look Up “\(term)”") { action(term) }
                    if let onRemove {
                        Button(removeTitle, role: .destructive) { onRemove(term) }
                    }
                }
            }
        }
    }
}

struct DictionaryDescriptor: Hashable {
    let label: String?
    let term: String
}

struct DictionaryDescriptorGroup: View {
    @ObservedObject private var appearance = MongrelAppearancePreferences.shared

    let title: String
    let symbol: String
    let items: [DictionaryDescriptor]
    let tone: DictionaryCapsuleTone
    let action: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: symbol)
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .kerning(0.7)
                .foregroundStyle(DesignTokens.textSecondary)

            DictionaryFlowLayout {
                ForEach(items.uniquedDescriptors(), id: \.self) { item in
                    Button {
                        action(item.term)
                    } label: {
                        HStack(spacing: 6) {
                            if let label = item.label {
                                Text(label)
                                    .foregroundStyle(DesignTokens.textMuted)
                                Text("·")
                                    .foregroundStyle(DesignTokens.textMuted)
                            }
                            Text(item.term)
                                .foregroundStyle(DesignTokens.textPrimary)
                        }
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(tone == .accent ? DesignTokens.selectionFill : DesignTokens.glassElevated)
                                .overlay(Capsule().stroke(DesignTokens.borderRim, lineWidth: DesignTokens.borderWidth))
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        item.label.map { "\(title), \($0), look up \(item.term)" }
                            ?? "\(title), look up \(item.term)"
                    )
                }
            }
        }
    }
}

// MARK: – Flow layout

/// Wraps chips at the available width.
///
/// This replaces a helper that chunked items into fixed rows of four. Four
/// short part-of-speech chips fit comfortably; four long dialect counterparts
/// ran past the panel edge, and a single long term left three empty slots.
struct DictionaryFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        arrange(subviews: subviews, maxWidth: proposal.width ?? 10_000).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let arrangement = arrange(subviews: subviews, maxWidth: bounds.width)
        for (subview, origin) in zip(subviews, arrangement.origins) {
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        origins.reserveCapacity(subviews.count)

        let width = (maxWidth.isFinite && maxWidth > 0) ? maxWidth : 10_000
        var cursorX: CGFloat = 0
        var cursorY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widestRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursorX > 0 && cursorX + size.width > width {
                widestRow = max(widestRow, cursorX - spacing)
                cursorX = 0
                cursorY += rowHeight + lineSpacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: cursorX, y: cursorY))
            cursorX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        widestRow = max(widestRow, cursorX - spacing)
        return (
            CGSize(width: min(max(widestRow, 0), width), height: cursorY + rowHeight),
            origins
        )
    }
}

// MARK: – Result taxonomy

enum ResultSection: Hashable {
    case direct
    case fuzzy
    case companions
    case coverage
    case inference
    case thesaurus
    case definitions
    case translations

    var title: String {
        switch self {
        case .direct: return "Direct Matches"
        case .fuzzy: return "Variant And Fuzzy Matches"
        case .companions: return "Related English Variants"
        case .coverage: return "Spelling And Coverage"
        case .inference: return "Inferences And Pivots"
        case .thesaurus: return "Thesaurus"
        case .definitions: return "Definitions And Context"
        case .translations: return "Translations"
        }
    }

    var shortTitle: String {
        switch self {
        case .direct: return "Direct"
        case .fuzzy: return "Variants"
        case .companions: return "Companions"
        case .coverage: return "Coverage"
        case .inference: return "Pivots"
        case .thesaurus: return "Thesaurus"
        case .definitions: return "Definitions"
        case .translations: return "Translations"
        }
    }

    var symbolName: String {
        switch self {
        case .direct: return "scope"
        case .fuzzy: return "wand.and.stars"
        case .companions: return "arrow.left.arrow.right"
        case .coverage: return "character.book.closed"
        case .inference: return "sparkles"
        case .thesaurus: return "text.badge.plus"
        case .definitions: return "book.closed"
        case .translations: return "globe"
        }
    }
}

struct ResultCardSectionGroup: Identifiable {
    let section: ResultSection
    var cards: [DictionarySession.ResultCard]

    var id: ResultSection { section }
}

// MARK: – Clipboard

extension Array where Element == String {
    func uniquedTerms() -> [String] {
        var seen = Set<String>()
        return filter {
            seen.insert(
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .precomposedStringWithCanonicalMapping
                    .lowercased()
            ).inserted
        }
    }
}

private extension Array where Element == DictionaryDescriptor {
    func uniquedDescriptors() -> [DictionaryDescriptor] {
        var seen = Set<String>()
        return filter { item in
            let key = "\(item.label ?? "")\u{1F}\(item.term.lowercased())"
            return seen.insert(key).inserted
        }
    }
}

@MainActor
enum DictionaryClipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private static var selectAllGeneration = 0

    static func hasSelectedText() -> Bool {
        selectedString() != nil
    }

    /// Highlighted text in the key window, without falling back to the pasteboard.
    static func selectedTextViewTerm() -> String? {
        guard let selected = selectedString() else {
            return nil
        }
        return DictionaryLookupRequest.normalizedTerm(selected)
    }

    /// Command-L and `/` land in the search field; selecting the current query
    /// lets the next keystroke replace it instead of appending.
    @MainActor
    static func selectAllInFocusedTextView() {
        selectAllGeneration &+= 1
        let generation = selectAllGeneration
        Task { @MainActor in
            for attempt in 0..<4 {
                try? await Task.sleep(nanoseconds: attempt == 0 ? 16_000_000 : 24_000_000)
                guard generation == selectAllGeneration else { return }
                if selectAllInCurrentEditor() {
                    return
                }
            }
        }
    }

    static func selectedString() -> String? {
        var responder = NSApp.keyWindow?.firstResponder
        while let current = responder {
            if let textView = current as? NSTextView,
               let selected = selectedString(in: textView) {
                return selected
            }
            if let field = current as? NSTextField,
               let editor = field.currentEditor() as? NSTextView,
               let selected = selectedString(in: editor) {
                return selected
            }
            responder = current.nextResponder
        }
        return nil
    }

    /// A stale NSTextView selection can point past the current string. Asking
    /// NSString to slice that range throws an ObjC exception, so this stays
    /// inside the live UTF-16 bounds.
    static func selectedString(in textView: NSTextView?) -> String? {
        guard let textView else { return nil }
        let contents = textView.string as NSString
        let range = textView.selectedRange()
        guard range.location != NSNotFound,
              range.location >= 0,
              range.length > 0,
              range.location <= contents.length,
              range.length <= contents.length - range.location else {
            return nil
        }
        return contents.substring(with: range)
    }

    @MainActor
    private static func selectAllInCurrentEditor() -> Bool {
        var responder = NSApp.keyWindow?.firstResponder
        while let current = responder {
            if let textView = current as? NSTextView, textView.isEditable {
                textView.selectAll(nil)
                return true
            }
            if let field = current as? NSTextField {
                field.window?.makeFirstResponder(field)
                if let editor = field.currentEditor() {
                    editor.selectAll(nil)
                    return true
                }
            }
            if let text = current as? NSText {
                text.selectAll(nil)
                return true
            }
            responder = current.nextResponder
        }
        return false
    }
}
