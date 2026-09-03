import Foundation

/// Matches what the coach typed against the text of a record.
///
/// The obvious version — lowercase both sides and ask for a substring — is
/// wrong in two ways a coach will hit within a season.
///
/// It can't find "Muñoz" from "munoz". The app stores the name as it was
/// entered, carefully, once; it is searched later, one-handed, on a touchline,
/// by someone who is not going to hold down the n.
///
/// And it can't find anything at all from "u12 rondo", because no single field
/// contains that phrase — the words live in the title and the tags. A coach
/// typing two words means both, not a sentence.
enum SearchQuery {
    /// Whether `query` matches, treating each word as a separate requirement
    /// that any one of `fields` can satisfy.
    ///
    /// An empty or all-whitespace query matches everything, so a caller can ask
    /// unconditionally rather than branching on whether a search is running.
    static func matches(_ query: String, in fields: [String]) -> Bool {
        let terms = query.split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return true }
        return terms.allSatisfy { term in
            fields.contains {
                $0.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }

    /// Whether the coach has typed anything worth matching against — the
    /// difference between "this list is empty" and "nothing matched", which are
    /// different things to say.
    static func isActive(_ query: String) -> Bool {
        !query.split(whereSeparator: \.isWhitespace).isEmpty
    }
}
