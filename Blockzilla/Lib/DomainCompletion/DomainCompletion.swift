/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation

typealias AutoCompleteSuggestions = [String]

protocol AutocompleteSource {
    var enabled: Bool { get }
    func getSuggestions() -> AutoCompleteSuggestions
}

enum CompletionSourceError: Error {
    case invalidUrl
    case duplicateDomain
    case indexOutOfRange

    var message: String {
        guard case .invalidUrl = self else { return "" }

        return UIConstants.strings.autocompleteAddCustomUrlError
    }
}

typealias CustomCompletionResult = Result<Void, CompletionSourceError>

protocol CustomAutocompleteSource: AutocompleteSource {
    func add(suggestion: String) -> CustomCompletionResult
    func add(suggestion: String, atIndex: Int) -> CustomCompletionResult
    func remove(at index: Int) -> CustomCompletionResult
}

class CustomCompletionSource: CustomAutocompleteSource {
    private lazy var regex = try! NSRegularExpression(pattern: "^(\\s+)?(?:https?:\\/\\/)?(?:www\\.)?", options: [.caseInsensitive])
    var enabled: Bool { return Settings.getToggle(.enableCustomDomainAutocomplete) }

    func getSuggestions() -> AutoCompleteSuggestions {
        return Settings.getCustomDomainSetting()
    }

    func add(suggestion: String) -> CustomCompletionResult {
        var sanitizedSuggestion = regex.stringByReplacingMatches(in: suggestion, options: [], range: NSRange(location: 0, length: suggestion.count), withTemplate: "")

        guard !sanitizedSuggestion.isEmpty else { return .failure(.invalidUrl) }

        guard sanitizedSuggestion.contains(".") else { return .failure(.invalidUrl) }

        // Drop trailing slash, otherwise URLs will end with two when added from quick add URL menu action
        if sanitizedSuggestion.suffix(1) == "/" {
            sanitizedSuggestion = String(sanitizedSuggestion.dropLast())
        }

        var domains = getSuggestions()
        guard !domains.contains(where: { domain in
            domain.compare(suggestion, options: .caseInsensitive) == .orderedSame
        }) else { return .failure(.duplicateDomain) }

        domains.append(suggestion)
        Settings.setCustomDomainSetting(domains: domains)

        return .success(())
    }

    func add(suggestion: String, atIndex: Int) -> CustomCompletionResult {
        let sanitizedSuggestion = regex.stringByReplacingMatches(in: suggestion, options: [], range: NSRange(location: 0, length: suggestion.count), withTemplate: "")

        guard !sanitizedSuggestion.isEmpty else { return .failure(.invalidUrl) }

        var domains = getSuggestions()
        guard !domains.contains(sanitizedSuggestion) else { return .failure(.duplicateDomain) }

        domains.insert(suggestion, at: atIndex)
        Settings.setCustomDomainSetting(domains: domains)

        return .success(())
    }

    func remove(at index: Int) -> CustomCompletionResult {
        var domains = getSuggestions()

        guard domains.count > index else { return .failure(.indexOutOfRange) }
        domains.remove(at: index)
        Settings.setCustomDomainSetting(domains: domains)

        return .success(())
    }
}

class TopDomainsCompletionSource: AutocompleteSource {
    var enabled: Bool { return Settings.getToggle(.enableDomainAutocomplete) }

    private lazy var topDomains: [String] = {
        let filePath = Bundle.main.path(forResource: "topdomains", ofType: "txt")
        return try! String(contentsOfFile: filePath!).components(separatedBy: "\n")
    }()

    func getSuggestions() -> AutoCompleteSuggestions {
        return topDomains
    }
}

class DomainCompletion: AutocompleteTextFieldCompletionSource {
    private var completionSources: [AutocompleteSource]

    init(completionSources: [AutocompleteSource]) {
        self.completionSources = completionSources
    }

    func autocompleteTextFieldCompletionSource(_ autocompleteTextField: AutocompleteTextField, forText text: String) -> String? {
        guard !text.isEmpty else { return nil }

        let domains = completionSources.lazy
            .filter({ $0.enabled }) // Only include domain sources that are enabled in settings
            .flatMap({ $0.getSuggestions() }) // Flatten all sources into a [String]

        for domain in domains {
            if let completion = self.completion(forDomain: domain, withText: text) {
                return completion
            }
        }

        return nil
    }

    private func completion(forDomain domain: String, withText text: String) -> String? {
        let domainWithDotPrefix: String = ".www.\(domain)"
        if let range = domainWithDotPrefix.range(of: ".\(text)", options: .caseInsensitive, range: nil, locale: nil) {
            // We don't actually want to match the top-level domain ("com", "org", etc.) by itself, so
            // so make sure the result includes at least one ".".
            let range = domainWithDotPrefix.index(range.lowerBound, offsetBy: 1)
            let matchedDomain = domainWithDotPrefix[range...]

            if matchedDomain.contains(".") {
                if matchedDomain.contains("/") {
                    return String(matchedDomain)
                }
                return matchedDomain + "/"
            }
        }

        return nil
    }
}
