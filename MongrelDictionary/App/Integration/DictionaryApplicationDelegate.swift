import AppKit
import MongrelDictionaryCore

@MainActor
final class DictionaryApplicationDelegate: NSObject, NSApplicationDelegate {
    private weak var session: DictionarySession?
    private let servicesProvider = DictionaryServicesProvider()
    private var pendingLookups: [DictionaryLookupRequest] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = servicesProvider
        NSUpdateDynamicServices()
    }

    func applicationWillTerminate(_ notification: Notification) {
        session?.flushPendingPersistence()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let requests = urls.compactMap(DictionaryLookupRequest.init(url:))
        enqueueOrPerform(requests)
        revealDictionary()
    }

    func connect(to session: DictionarySession) {
        self.session = session
        servicesProvider.lookupHandler = { [weak self] text in
            self?.performServiceLookup(text)
        }
        if !pendingLookups.isEmpty {
            let queued = pendingLookups
            pendingLookups.removeAll()
            perform(queued)
            revealDictionary()
        }
    }

    private func performServiceLookup(_ text: String) {
        guard let request = DictionaryLookupRequest(term: text, intent: session?.queryIntent ?? .define) else { return }
        enqueueOrPerform([request])
        revealDictionary()
    }

    private func enqueueOrPerform(_ requests: [DictionaryLookupRequest]) {
        guard !requests.isEmpty else { return }
        if session != nil {
            perform(requests)
        } else {
            pendingLookups.append(contentsOf: requests)
        }
    }

    private func perform(_ requests: [DictionaryLookupRequest]) {
        for request in requests {
            session?.performLookup(request)
        }
    }

    private func revealDictionary() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeKey }) {
            window.makeKeyAndOrderFront(nil)
        }
        NotificationCenter.default.post(name: .mongrelRevealDictionaryWindow, object: nil)
        NotificationCenter.default.post(name: .mongrelFocusSearch, object: nil)
    }
}

@MainActor
private final class DictionaryServicesProvider: NSObject {
    var lookupHandler: ((String) -> Void)?

    @objc(lookup:userData:error:)
    func lookup(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let text = pasteboard.string(forType: .string),
              DictionaryLookupRequest.normalizedTerm(text) != nil else {
            error.pointee = "Mongrel Dictionary could not read text from the selected application." as NSString
            return
        }
        lookupHandler?(text)
    }
}
