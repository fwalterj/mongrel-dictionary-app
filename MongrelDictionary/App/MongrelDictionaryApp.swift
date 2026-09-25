import SwiftUI
import AppKit
import MongrelDictionaryCore

@main
struct MongrelDictionaryApp: App {
    @NSApplicationDelegateAdaptor(DictionaryApplicationDelegate.self) private var appDelegate
    @StateObject private var session = DictionarySession()

    var body: some Scene {
        WindowGroup("Mongrel Dictionary", id: "dictionary-main") {
            DictionaryContentView()
                .environmentObject(session)
                .mongrelAppearance()
                .frame(minWidth: 1040, minHeight: 640)
                .onAppear { appDelegate.connect(to: session) }
                .onReceive(NotificationCenter.default.publisher(for: .mongrelRevealDictionaryWindow)) { _ in
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 780)
        .handlesExternalEvents(matching: [DictionaryLookupRequest.urlScheme])

        Window("Quick Lookup", id: "quick-lookup") {
            QuickLookupView()
                .environmentObject(session)
                .mongrelAppearance()
                .onAppear { appDelegate.connect(to: session) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 620, height: 640)

        Window("Lookup Help", id: "lookup-help") {
            DictionaryHelpView()
                .mongrelAppearance()
        }
        .defaultSize(width: 520, height: 640)

        .commands {
            DictionaryCommands(session: session)
            DictionaryAppearanceCommands()
        }

        Settings {
            DictionarySettingsView()
                .mongrelAppearance()
        }
    }
}

private struct DictionaryAppearanceCommands: Commands {
    @ObservedObject private var appearance = MongrelAppearancePreferences.shared

    var body: some Commands {
        CommandMenu("Appearance") {
            ForEach(MongrelAppearanceMode.allCases) { mode in
                Button {
                    appearance.mode = mode
                } label: {
                    // The checkmark is the state cue. Nothing here depends on
                    // the reader distinguishing one tint from another.
                    Label(
                        mode.title,
                        systemImage: appearance.mode == mode ? "checkmark.circle.fill" : "circle"
                    )
                }
                .help(mode.detail)
            }

            Divider()

            ForEach(MongrelContrastPage.allCases) { page in
                Button {
                    appearance.contrastPage = page
                    appearance.mode = .contrast
                } label: {
                    Label("Contrast: \(page.title)", systemImage:
                        appearance.mode == .contrast && appearance.contrastPage == page
                            ? "checkmark.circle.fill" : "circle")
                }
            }

            Divider()

            Button {
                appearance.bloomEnabled.toggle()
            } label: {
                Label(
                    "Reading Halo",
                    systemImage: appearance.bloomEnabled ? "checkmark.circle.fill" : "circle"
                )
            }
            .help("A restrained glow behind headwords and definitions.")

            Divider()

            Button("Larger Definitions") {
                appearance.adjustReadingTextScale(by: 0.1)
            }
            .keyboardShortcut("+", modifiers: .command)

            Button("Smaller Definitions") {
                appearance.adjustReadingTextScale(by: -0.1)
            }
            .keyboardShortcut("-", modifiers: .command)

            Button("Actual Definition Size") {
                appearance.resetReadingMetrics()
            }
            .keyboardShortcut("0", modifiers: .command)
        }
    }
}

private struct DictionaryCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var session: DictionarySession

    var body: some Commands {
        CommandMenu("Lookup") {
            Button("Quick Lookup") {
                openWindow(id: "quick-lookup")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(.space, modifiers: [.command, .shift])

            Button("Paste and Look Up") {
                pasteAndLookUp()
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])

            Button("Look Up Selection") {
                lookUpSelection()
            }
            .keyboardShortcut("l", modifiers: [.command, .option])

            Divider()

            Button("Back") {
                session.goBack()
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(!session.canGoBack)

            Button("Forward") {
                session.goForward()
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(!session.canGoForward)

            Divider()

            Button("Focus Search") {
                NotificationCenter.default.post(name: .mongrelFocusSearch, object: nil)
            }
            .keyboardShortcut("l", modifiers: .command)

            Button("Search Now") {
                if session.hasQuery {
                    session.previewSearch()
                }
                NotificationCenter.default.post(name: .mongrelFocusSearch, object: nil)
            }
            .keyboardShortcut(.return, modifiers: .command)

            Button("Refresh Lookup") {
                session.retryCurrentLookup()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!session.canRetryLookup)

            Button("Clear Desk") {
                session.clearQuery()
                NotificationCenter.default.post(name: .mongrelFocusSearch, object: nil)
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])

            Divider()

            Button("Next Result") {
                NotificationCenter.default.post(name: .mongrelFocusNextResult, object: nil)
            }
            .keyboardShortcut(.downArrow, modifiers: .command)

            Button("Previous Result") {
                NotificationCenter.default.post(name: .mongrelFocusPreviousResult, object: nil)
            }
            .keyboardShortcut(.upArrow, modifiers: .command)

            Button("Expand or Collapse Result") {
                NotificationCenter.default.post(name: .mongrelToggleResultExpansion, object: nil)
            }
            .keyboardShortcut("e", modifiers: .command)

            Divider()

            Button("Save Current Term") {
                session.toggleFavorite()
            }
            .keyboardShortcut("d", modifiers: .command)

            Button("Copy Search Package") {
                copySearchPackage()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])

            Divider()

            Button("Define") { session.selectIntent(.define) }
                .keyboardShortcut("1", modifiers: .command)

            Button("Synonyms") { session.selectIntent(.synonyms) }
                .keyboardShortcut("2", modifiers: .command)

            Button("Translation") { session.selectIntent(.translation) }
                .keyboardShortcut("3", modifiers: .command)

            Button("Slang") { session.selectIntent(.slang) }
                .keyboardShortcut("4", modifiers: .command)
        }

        CommandGroup(replacing: .help) {
            Button("Lookup Shortcuts") {
                openWindow(id: "lookup-help")
            }
            .keyboardShortcut("/", modifiers: [.command, .shift])
        }
    }

    private func lookUpSelection() {
        guard let term = DictionaryClipboard.selectedTextViewTerm() else {
            NSSound.beep()
            return
        }
        session.selectTerm(term)
        NotificationCenter.default.post(name: .mongrelFocusSearch, object: nil)
    }

    private func copySearchPackage() {
        guard session.hasSearched, !session.resultCards.isEmpty else {
            NSSound.beep()
            return
        }
        DictionaryClipboard.copy(session.searchPackageText)
        NotificationCenter.default.post(name: .mongrelCopySearchPackage, object: nil)
    }

    private func pasteAndLookUp() {
        guard let text = NSPasteboard.general.string(forType: .string),
              let request = DictionaryLookupRequest(term: text, intent: session.queryIntent) else {
            NSSound.beep()
            return
        }
        session.performLookup(request)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .mongrelFocusSearch, object: nil)
        let frontTitle = NSApp.keyWindow?.title ?? ""
        if frontTitle.localizedCaseInsensitiveContains("Mongrel Dictionary")
            || frontTitle.localizedCaseInsensitiveContains("Quick Lookup") {
            return
        }
        openWindow(id: "quick-lookup")
    }
}

extension Notification.Name {
    static let mongrelNavigateBack = Notification.Name("mongrel.dictionary.navigateBack")
    static let mongrelNavigateForward = Notification.Name("mongrel.dictionary.navigateForward")
    static let mongrelFocusSearch = Notification.Name("mongrel.dictionary.focusSearch")
    static let mongrelRunSearch = Notification.Name("mongrel.dictionary.runSearch")
    static let mongrelClearSearch = Notification.Name("mongrel.dictionary.clearSearch")
    static let mongrelSetIntent = Notification.Name("mongrel.dictionary.setIntent")
    static let mongrelToggleFavorite = Notification.Name("mongrel.dictionary.toggleFavorite")
    static let mongrelCopySearchPackage = Notification.Name("mongrel.dictionary.copySearchPackage")
    static let mongrelFocusNextResult = Notification.Name("mongrel.dictionary.focusNextResult")
    static let mongrelFocusPreviousResult = Notification.Name("mongrel.dictionary.focusPreviousResult")
    static let mongrelToggleResultExpansion = Notification.Name("mongrel.dictionary.toggleResultExpansion")
    static let mongrelLookupSelection = Notification.Name("mongrel.dictionary.lookupSelection")
    static let mongrelDismissFocus = Notification.Name("mongrel.dictionary.dismissFocus")
    static let mongrelRevealDictionaryWindow = Notification.Name("mongrel.dictionary.revealDictionaryWindow")
}
