import Foundation

/// A parse that could not produce structure, with the raw output kept.
public struct ParseFailure: Error, Equatable {
    public let raw: String
    public let detail: String
}

/// What came back, and whether it was understood.
public enum ParseOutcome<Value: Sendable & Equatable>: Sendable, Equatable {
    case decoded(Value)
    /// Structure was lost but the text is still useful (`NFR-REL-1`).
    case degraded(raw: String)
}

/// Parses model output that does not always behave.
///
/// `NFR-REL-1`. A local model wraps JSON in code fences, prefaces it with "Sure,
/// here you go", or both. None of that should cost the user a regeneration.
public enum ResponseParser {

    /// The outermost JSON object in `raw`, or `nil`.
    ///
    /// Brace matching is **string-aware**: it tracks whether the cursor is
    /// inside a JSON string literal and honours backslash escapes. The naive
    /// version — first `{` to last `}` — is nearly right and fails on exactly
    /// the responses this project produces most, because a correction's
    /// `explanation_en` can quite reasonably contain a brace.
    public static func extractJSONObject(from raw: String) -> String? {
        guard let start = raw.firstIndex(of: "{") else { return nil }

        var depth = 0
        var insideString = false
        var escaped = false

        for index in raw[start...].indices {
            let character = raw[index]

            if escaped {
                escaped = false
                continue
            }
            if insideString {
                if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    insideString = false
                }
                continue
            }
            switch character {
            case "\"": insideString = true
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return String(raw[start...index])
                }
            default: break
            }
        }
        return nil
    }

    /// Translate and re-pitch degrade to the raw text.
    ///
    /// Unparseable output still contains a usable translation, so refusing to
    /// show it would throw away the model's work and the user's time.
    public static func parseTranslate(_ raw: String) -> ParseOutcome<TranslateResponse> {
        guard let json = extractJSONObject(from: raw),
            let decoded = try? JSONDecoder.responseContract.decode(
                TranslateResponse.self, from: Data(json.utf8))
        else {
            return .degraded(raw: raw)
        }
        return .decoded(decoded)
    }

    /// Correction does **not** degrade to raw text.
    ///
    /// The asymmetry with ``parseTranslate(_:)`` is deliberate and is the thing
    /// to check hardest in review. A translation's value survives losing its
    /// structure; a correction's does not, because an itemised error list cannot
    /// be recovered from prose, and showing the raw output as though it were a
    /// verified correction would be inventing changes the model never itemised
    /// — exactly what `FR-COR-06` forbids.
    public static func parseCorrect(_ raw: String) throws -> CorrectResponse {
        guard let json = extractJSONObject(from: raw) else {
            throw ParseFailure(raw: raw, detail: "no JSON object found in the response")
        }
        do {
            return try JSONDecoder.responseContract.decode(
                CorrectResponse.self, from: Data(json.utf8))
        } catch {
            throw ParseFailure(raw: raw, detail: "\(error)")
        }
    }

    public static func parseExplain(_ raw: String) throws -> ExplainResponse {
        guard let json = extractJSONObject(from: raw) else {
            throw ParseFailure(raw: raw, detail: "no JSON object found in the response")
        }
        do {
            return try JSONDecoder.responseContract.decode(
                ExplainResponse.self, from: Data(json.utf8))
        } catch {
            throw ParseFailure(raw: raw, detail: "\(error)")
        }
    }
}
