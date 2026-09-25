import Foundation
import MongrelDictionaryCore

/// Turns repository vocabulary into the wording the Reference Desk shows.
///
/// The repository labels results with its own source and chip names. Readers
/// should see "Core English" rather than "wordnet", and a card's grouping,
/// identity badge, and match badge all derive from the same labels — so the
/// mapping lives in one place instead of being repeated per view.
enum DictionaryResultPresentation {

    // MARK: – Grouping

    static func section(for card: DictionarySession.ResultCard) -> ResultSection {
        let source = card.source.lowercased()

        if source.contains("freedict")
            || source.contains("za mafoko")
            || source.contains("bilingual")
            || source.contains("→") {
            return .translations
        }
        if card.chips.contains("companion result") {
            return .companions
        }
        if card.chips.contains("exact hit") || card.chips.contains("direct note hit") {
            return .direct
        }
        if card.chips.contains("variant hit")
            || card.chips.contains("typo-tolerant hit")
            || card.chips.contains("synonym-led hit")
            || card.chips.contains("phrase-core hit") {
            return .fuzzy
        }
        if card.source == "Regional spelling note" || card.source == "Regional English wordlists" {
            return .coverage
        }
        if card.source == "English word-family inference" || card.source == "Reference pivots" {
            return .inference
        }
        if source.contains("thesaurus") {
            return .thesaurus
        }
        return .definitions
    }

    // MARK: – Badges

    /// The lexical tradition a card came from, shown beside the headword.
    static func identityBadge(for card: DictionarySession.ResultCard) -> String {
        let source = card.source
        let lower = source.lowercased()

        if lower.contains("wordnet"), let partOfSpeech = card.chips.first(where: isPartOfSpeechChip) {
            return chipTitle(partOfSpeech)
        }

        switch source {
        case "Mongrel reference notes": return "Reference English"
        case "Regional spelling note": return "Comparative English"
        case "English word-family inference": return "Word family"
        case "Australian English Dictionary", "Australian usage notes": return "Australian English"
        case "Reference pivots": return "Nearby terms"
        case "Regional English wordlists":
            if let regionalChip = card.chips.first(where: isRegionalIdentityChip) {
                return chipTitle(regionalChip)
            }
            return "Regional English"
        default:
            break
        }

        if lower.contains("thesaurus") { return "Synonyms" }
        if lower.contains("freedict") || lower.contains("za mafoko") { return "Translation" }
        if source.hasPrefix("No match") { return "No direct match" }
        return "Reference entry"
    }

    /// Why this card matched, so a fuzzy recovery is never mistaken for a
    /// dictionary's own considered entry.
    static func matchBadge(for card: DictionarySession.ResultCard) -> String? {
        if card.chips.contains("exact hit") { return "Exact hit" }
        if card.chips.contains("variant hit") { return "Variant form" }
        if card.chips.contains("typo-tolerant hit") { return "Typo recovery" }
        if card.chips.contains("synonym-led hit") { return "Synonym-led" }
        if card.chips.contains("phrase-core hit") { return "Phrase core" }
        if card.chips.contains("dialect companion") { return "Dialect companion" }
        if card.chips.contains("related companion") { return "Related companion" }
        if card.source == "English word-family inference" { return "Word-family inference" }
        if card.source == "Reference pivots" { return "Nearby headwords" }
        return nil
    }

    static func chipTitle(_ chip: String) -> String {
        switch chip {
        case "australian english": return "Australian English"
        case "regional english": return "Regional English"
        case "regional spelling": return "Regional spelling"
        case "direct note hit": return "Direct entry"
        case "phrase-core hit": return "Phrase core"
        case "typo-tolerant hit": return "Typo recovery"
        case "variant hit": return "Variant form"
        case "exact hit": return "Exact hit"
        case "synonym-led hit": return "Synonym-led"
        case "dialect companion": return "Dialect companion"
        case "related companion": return "Related companion"
        case "companion result": return "Companion result"
        case "headword": return "Headword"
        case "wordnet": return "Core English"
        case "oewn": return "Modern core"
        case "classic": return "Classic core"
        case "usage": return "Usage"
        case "thesaurus", "synonyms": return "Synonyms"
        case "moby": return "Expanded synonyms"
        case "public domain": return "Expanded coverage"
        case "hunspell": return "Local coverage"
        default: return chip.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func isPartOfSpeechChip(_ chip: String) -> Bool {
        let lower = chip.lowercased()
        return lower.contains("noun")
            || lower.contains("verb")
            || lower.contains("adjective")
            || lower.contains("adverb")
    }

    static func isRegionalIdentityChip(_ chip: String) -> Bool {
        let lower = chip.lowercased()
        return lower.contains("british")
            || lower.contains("australian")
            || lower.contains("canadian")
            || lower.contains("new zealand")
            || lower.contains("south african")
            || lower.contains("american")
    }

    // MARK: – Inventory naming

    static func inventoryTitle(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("wordnet") { return "Core English" }
        if name == "Australian English Dictionary" { return "Australian English" }
        if name == "Mongrel reference notes" { return "Reference English" }
        if lower.contains("english (") { return "Regional English" }
        if lower.contains("thesaurus") { return "Synonyms" }
        if lower.contains("freedict") || lower.contains("za mafoko") { return "Translations" }
        return "Reference archive"
    }

    static func loadedIndexTitle(_ name: String) -> String {
        switch name {
        case "WordNet 2025", "WordNet classic": return "Core English"
        case "Reference notes": return "Reference English"
        case "Regional English": return "Regional English"
        case "Aussie dictionary": return "Australian English"
        case "Search lexicon": return "Lookup index"
        case "OpenOffice thesaurus", "Moby thesaurus": return "Synonyms"
        case "FreeDict", "ZA Mafoko": return "Translations"
        default: return name
        }
    }

    // MARK: – Clipboard

    /// A single card rendered for pasting elsewhere, labels included so the
    /// text is still self-describing outside the application.
    static func plainText(for card: DictionarySession.ResultCard) -> String {
        var lines = [card.title, card.summary]

        if !card.counterparts.isEmpty {
            lines.append("Counterparts: " + card.counterparts.map { "\($0.label): \($0.term)" }.joined(separator: "; "))
        }
        if !card.antonyms.isEmpty {
            lines.append("Antonyms: " + card.antonyms.joined(separator: ", "))
        }
        if !card.relatedTerms.isEmpty {
            lines.append("Related terms: " + card.relatedTerms.joined(separator: ", "))
        }
        if !card.topicTerms.isEmpty {
            lines.append("Topic mesh: " + card.topicTerms.joined(separator: ", "))
        }
        lines.append("Source: \(card.source)")

        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    // MARK: – Australian glosses

    /// Clipped Australian forms that readers commonly meet before they meet the
    /// full word. Shown as a gloss, never as a substitute for a real entry.
    static func australianExpansion(for rawTerm: String) -> String? {
        australianExpansions[rawTerm.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
    }

    private static let australianExpansions: [String: String] = [
        "arvo": "afternoon",
        "avo": "avocado",
        "barbie": "barbecue",
        "bikie": "motorcyclist / motorcycle gang member",
        "bottleo": "bottle shop / liquor store",
        "brekkie": "breakfast",
        "brissy": "Brisbane",
        "chokkie": "chocolate",
        "crook": "sick / unwell",
        "esky": "portable cooler box (brand name)",
        "footy": "Australian Rules Football (AFL) or Rugby League (NRL) depending on state",
        "freo": "Fremantle",
        "gong": "Wollongong",
        "hecs": "Higher Education Loan Program (HELP)",
        "maccas": "McDonald's",
        "melbs": "Melbourne",
        "mozzie": "mosquito",
        "prezzie": "present / gift",
        "roo": "kangaroo",
        "sanger": "sandwich",
        "servo": "service station",
        "snag": "sausage",
        "sunnies": "sunglasses",
        "super": "superannuation",
        "tassie": "Tasmania",
        "thongs": "flip-flops / sandals",
        "tinnie": "can of beer / small aluminium boat",
        "trackies": "tracksuit pants",
        "tradie": "tradesperson (plumber, electrician, etc.)",
        "ute": "utility vehicle",
        "uni": "university"
    ]
}
