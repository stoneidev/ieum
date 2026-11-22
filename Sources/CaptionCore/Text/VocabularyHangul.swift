import Foundation

/// Hangul spellings (and common mishearings) that should rewrite to a Latin vocabulary term.
///
/// Korean speech of English jargon often comes out in Hangul (`쿠버네티스`, `피그마`). The Latin vocabulary
/// entry alone used to miss those windows (measured on the codeswitch passage in `docs/TRANSCRIPTION-RESEARCH.md`).
/// This table is curated loanword forms, not a full transliterator: unknown products still need an explicit Hangul line.
public enum VocabularyHangul {
    /// Hangul forms that map to `term` when `term` is a Latin vocabulary entry. Empty when `term` is not Latin
    /// or has no known Hangul spellings.
    public static func aliases(forLatin term: String) -> [String] {
        let key = normalize(term)
        guard !key.isEmpty, isLatin(term) else { return [] }
        return table[key] ?? []
    }

    /// Among Latin vocabulary lines that claim the same Hangul alias, pick one stably: the longest spelling wins
    /// (`PostgreSQL` over `Postgres`); equal length keeps lexicographic order.
    public static func preferredLatin(among lines: [String]) -> String? {
        let latin = lines.filter(isLatin)
        guard let first = latin.first else { return nil }
        return latin.dropFirst().reduce(first) { best, next in
            if next.count != best.count { return next.count > best.count ? next : best }
            return next.lowercased() < best.lowercased() ? next : best
        }
    }

    /// Splits a Hangul token into `(stem, particle)` by peeling trailing josa/endings, including stacks
    /// (`에서는요` → stem + `에서는요`). Longest particle wins at each step.
    public static func peelingParticle(from token: String) -> (stem: String, particle: String) {
        guard isHangulHeavy(token) else { return (token, "") }
        var stem = token
        var particle = ""
        while true {
            var peeled: String?
            for candidate in particles where stem.count > candidate.count && stem.hasSuffix(candidate) {
                let next = String(stem.dropLast(candidate.count))
                guard !next.isEmpty, isHangulHeavy(next) else { continue }
                peeled = candidate
                break
            }
            guard let peeled else { break }
            particle = peeled + particle
            stem = String(stem.dropLast(peeled.count))
        }
        return (stem, particle)
    }

    public static func isLatin(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return false }
        return letters.allSatisfy { $0.isASCII || ($0.value >= 0xC0 && $0.value <= 0x24F) }
    }

    public static func isHangulHeavy(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return false }
        let hangul = letters.filter(isHangulScalar).count
        return Double(hangul) / Double(letters.count) >= 0.5
    }

    // MARK: - Table

    /// Lowercased Latin → Hangul forms. Research listed `피로` for Figma, but that is also ordinary Korean
    /// ("fatigue"), so it is omitted on purpose.
    private static let table: [String: [String]] = [
        "kubernetes": ["쿠버네티스", "큐버네티스", "큐버닉스", "쿠버네테스", "쿠버네티즈"],
        "terraform": ["테라폼", "테라폴"],
        "figma": ["피그마"],
        "slack": ["슬랙", "슬락"],
        "jira": ["지라"],
        "docker": ["도커", "도카"],
        "github": ["깃허브"],
        "gitlab": ["깃랩"],
        "graphql": ["그래프큐엘"],
        "postgresql": ["포스트그레스", "포스트그레"],
        "postgres": ["포스트그레스", "포스트그레"],
        "mysql": ["마이에스큐엘"],
        "redis": ["레디스"],
        "kafka": ["카프카"],
        "aws": ["에이더블유에스"],
        "api": ["에이피아이"],
        "sdk": ["에스디케이"],
        "okr": ["오케이알"],
        "notion": ["노션"],
        "confluence": ["컨플루언스", "콘플루언스"],
        "linear": ["리니어"],
        "zoom": ["줌"],
        "teams": ["팀즈", "팀스"],
        "webex": ["웹엑스"],
        "skype": ["스카이프"],
        "swift": ["스위프트"],
        "python": ["파이썬", "파이선"],
        "javascript": ["자바스크립트"],
        "typescript": ["타입스크립트"],
        "react": ["리액트"],
    ]

    /// Case particles and common endings stuck to loanwords in speech recognition. Longest first.
    private static let particles: [String] = [
        "으로부터", "에서부터", "에게서는", "한테서는",
        "에서는", "에서도", "으로는", "으로도",
        "입니다", "습니다", "습니까",
        "까지는", "부터는", "으로써", "으로서",
        "에게서", "한테서", "한테", "에게",
        "하고", "으로", "로서", "로써",
        "에서", "까지", "부터", "보다",
        "이나", "이랑", "랑",
        "은", "는", "이", "가", "을", "를", "의", "에", "와", "과", "도", "만", "로", "요",
    ].sorted { $0.count > $1.count }

    private static func normalize(_ term: String) -> String {
        term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func isHangulScalar(_ scalar: Unicode.Scalar) -> Bool {
        (0xAC00...0xD7A3).contains(scalar.value) || (0x1100...0x11FF).contains(scalar.value)
            || (0x3130...0x318F).contains(scalar.value)
    }
}
