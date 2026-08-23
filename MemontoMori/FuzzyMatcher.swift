import Foundation

/// fzf のような曖昧一致（サブシーケンス検索）。
///
/// 入力した文字が候補の中に **順番どおり** に現れれば一致とみなし、
/// 「先頭か」「単語の切れ目か」「連続しているか」でスコアを付けます。
/// スコアは並べ替えのためだけに使う相対値で、絶対的な意味は持ちません。
enum FuzzyMatcher {
    struct Match: Equatable {
        /// 大きいほど良い一致。
        let score: Int
        /// 候補の何文字目が一致したか（`Array(candidate)` に対する添字）。ハイライト用。
        let matchedIndices: [Int]
    }

    /// 候補の先頭にそのまま一致した。
    private static let startBonus = 20
    /// `/` `_` `-` `.` や camelCase の切れ目に一致した。
    private static let boundaryBonus = 14
    /// 直前の一致から続けて一致した。
    private static let consecutiveBonus = 12
    /// 一致と一致の間に挟まった 1 文字あたりの減点。
    private static let gapPenalty = 1
    /// 離れすぎた場合でも減点は打ち止めにする。
    private static let maxGapPenalty = 24

    /// - Returns: 一致しなければ `nil`。空クエリはスコア 0 の一致として扱う。
    static func match(query: String, in candidate: String) -> Match? {
        let pattern = Array(query.lowercased().filter { !$0.isWhitespace })
        guard !pattern.isEmpty else { return Match(score: 0, matchedIndices: []) }

        let characters = Array(candidate)
        guard !characters.isEmpty else { return nil }
        let lowered = characters.map(lowercasedFirst)

        // まず前から貪欲に走査し、一致するかどうかと終端位置を求める。
        var patternIndex = 0
        var lastIndex = 0
        for (index, character) in lowered.enumerated() {
            if character == pattern[patternIndex] {
                patternIndex += 1
                lastIndex = index
                if patternIndex == pattern.count { break }
            }
        }
        guard patternIndex == pattern.count else { return nil }

        // 次に終端から後ろ向きに詰め直す。前向きの貪欲一致だけだと候補の前方に
        // 一致がばらけてしまい、"ab" が "a……b" のように離れて拾われるため。
        var matched = [Int](repeating: 0, count: pattern.count)
        var cursor = pattern.count - 1
        var index = lastIndex
        while cursor >= 0 && index >= 0 {
            if lowered[index] == pattern[cursor] {
                matched[cursor] = index
                cursor -= 1
            }
            index -= 1
        }
        guard cursor < 0 else { return nil }

        return Match(score: score(for: matched, characters: characters), matchedIndices: matched)
    }

    /// 別名（英語表記など）も含めて一番良い一致を返す。
    ///
    /// - Returns: `index` は `candidates` の何番目に一致したか。ハイライトの対象を選ぶのに使う。
    static func bestMatch(query: String, in candidates: [String]) -> (index: Int, match: Match)? {
        var best: (index: Int, match: Match)?
        for (index, candidate) in candidates.enumerated() {
            guard let match = match(query: query, in: candidate) else { continue }
            if let current = best, current.match.score >= match.score { continue }
            best = (index, match)
        }
        return best
    }

    private static func score(for matched: [Int], characters: [Character]) -> Int {
        var total = 0
        var previous: Int?
        for index in matched {
            if index == 0 {
                total += startBonus
            } else if isBoundary(at: index, in: characters) {
                total += boundaryBonus
            }
            if let previous {
                if index == previous + 1 {
                    total += consecutiveBonus
                } else {
                    total -= min((index - previous - 1) * gapPenalty, maxGapPenalty)
                }
            }
            previous = index
        }
        // 同じような一致なら短い候補を上に出す。
        total -= characters.count / 8
        return total
    }

    private static func isBoundary(at index: Int, in characters: [Character]) -> Bool {
        guard index > 0 else { return true }
        let previous = characters[index - 1]
        if previous == "/" || previous == "_" || previous == "-" || previous == "." || previous == " " {
            return true
        }
        // camelCase の切れ目
        return previous.isLowercase && characters[index].isUppercase
    }

    /// `Character.lowercased()` は `String` を返すので、先頭の 1 文字だけを取り出す。
    /// 添字をハイライトに使う都合上、小文字化で文字数がずれないようにするための措置。
    private static func lowercasedFirst(_ character: Character) -> Character {
        character.lowercased().first ?? character
    }
}
