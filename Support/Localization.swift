import Foundation

/// Translation coordinator that resolves user-facing strings from the OS locale.
///
/// The actual string tables live in two separate files:
///   - `RussianStrings.swift` (used when the system language is Russian)
///   - `EnglishStrings.swift` (used for every other locale, plus as the fallback)
///
/// If a key is missing from the active table, the English table is consulted,
/// and if it is missing there too, the raw key is returned so the defect is
/// visible during development instead of silently passing an empty string.
public enum L {

    /// Returns `true` when the preferred system language is Russian.
    ///
    /// The check uses the user's preferred language list (ordered) rather than
    /// `Locale.current` because on macOS that list reflects the system language
    /// setting, which is what drives the OS-level UI language.
    public static var isRussian: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("ru") ?? false
    }

    /// The dictionary that is active for the current locale.
    public static var strings: [String: String] {
        isRussian ? RussianStrings.dict : EnglishStrings.dict
    }

    /// Resolves a localized string for the given key.
    ///
    /// - Parameters:
    ///   - key: A stable identifier defined in both string tables.
    ///   - args: Optional format arguments. Values are expected to be `%@`-safe
    ///           (prefer passing `CVarArg` values that bridge to Objective-C,
    ///           e.g. `String`).
    /// - Returns: The localized value, or the English fallback, or the key itself.
    public static func str(_ key: String, _ args: CVarArg...) -> String {
        let value = strings[key]
            ?? EnglishStrings.dict[key]
            ?? "⚠️\(key)"
        guard !args.isEmpty else { return value }
        return String(format: value, arguments: args)
    }
}