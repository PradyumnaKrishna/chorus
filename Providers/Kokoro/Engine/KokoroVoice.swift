import Foundation

/// Kokoro's language codes. Only the languages espeak-ng can phonemize for
/// Kokoro are listed; Japanese and Chinese need a different G2P and are
/// deliberately left out rather than shipped sounding wrong.
enum KokoroLanguage: String, CaseIterable {
    case americanEnglish = "a"
    case britishEnglish  = "b"
    case spanish         = "e"
    case french          = "f"
    case hindi           = "h"
    case italian         = "i"
    case portuguese      = "p"

    var espeakVoice: String {
        switch self {
        case .americanEnglish: return "en-us"
        case .britishEnglish:  return "en"
        case .spanish:         return "es"
        case .french:          return "fr-fr"
        case .hindi:           return "hi"
        case .italian:         return "it"
        case .portuguese:      return "pt-br"
        }
    }

    var bcp47: String {
        switch self {
        case .americanEnglish: return "en-US"
        case .britishEnglish:  return "en-GB"
        case .spanish:         return "es-ES"
        case .french:          return "fr-FR"
        case .hindi:           return "hi-IN"
        case .italian:         return "it-IT"
        case .portuguese:      return "pt-BR"
        }
    }
}

/// One Kokoro voice, backed by a `voices/<id>.bin` style tensor.
struct KokoroVoice: Hashable {
    let id: String            // e.g. "af_bella"
    let displayName: String   // e.g. "Bella"
    let language: KokoroLanguage
    let isFemale: Bool

    /// Stable identifier handed to the system.
    var voiceIdentifier: String { "in.onpy.chorus.kokoro.\(id)" }

    /// Name shown in the system voice picker.
    var systemName: String { displayName }

    /// Voice files are named `<language><gender>_<name>.bin`.
    init?(fileStem: String) {
        let parts = fileStem.split(separator: "_", maxSplits: 1)
        guard parts.count == 2, parts[0].count == 2,
              let language = KokoroLanguage(rawValue: String(parts[0].prefix(1)))
        else { return nil }

        self.id = fileStem
        self.language = language
        self.isFemale = parts[0].hasSuffix("f")
        self.displayName = parts[1].prefix(1).uppercased() + parts[1].dropFirst()
    }

    static func catalog(in directory: URL) -> [KokoroVoice] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return files
            .filter { $0.hasSuffix(".bin") }
            .compactMap { KokoroVoice(fileStem: String($0.dropLast(4))) }
            .sorted { ($0.language.rawValue, $0.displayName) < ($1.language.rawValue, $1.displayName) }
    }
}
