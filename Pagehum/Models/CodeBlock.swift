// Modified for Pagehum: unified application and command-line naming.
import Foundation

/// A fenced code block lifted out of an article body so it is never spoken as prose.
///
/// Code blocks occupy one slot in `ReaderModel.sentences` — the slot holds `spokenAnnouncement`
/// ("Swift code block, 12 lines.") while the real source lives here, in the parallel
/// `ReaderModel.codeBlocks` map. That keeps the whole index-addressed pipeline (scheduler,
/// generation, seek, progress, `PlaylistItem.lastSentenceIndex`) working unchanged.
///
/// Produced by `ArticleSegmenter` from the sentinel markers that `TextExtractor`'s reader JS
/// substitutes for `<pre>` elements.
nonisolated struct CodeBlock: Codable, Equatable {

    /// Raw language token as it appeared on the page (`"swift"`, `"bash"`, `"jsx"`), lowercased.
    /// `nil` when the page gave us nothing to go on.
    let language: String?

    /// The exact source text, newlines intact.
    let source: String

    // MARK: - Derived

    var lineCount: Int {
        // A trailing newline is formatting, not a line of code.
        let trimmed = source.hasSuffix("\n") ? String(source.dropLast()) : source
        return max(1, trimmed.components(separatedBy: "\n").count)
    }

    /// Human-readable, **TTS-pronounceable** language name, or `nil` for unrecognized tokens.
    ///
    /// Deliberately conservative: an unknown token is dropped rather than spoken, because Kokoro
    /// reading "jsonnet" or a build-tool slug aloud is worse than saying nothing.
    var displayLanguage: String? {
        guard let language, !language.isEmpty else { return nil }
        return Self.displayNames[language]
    }

    /// The short line the listener actually hears in place of the code.
    var spokenAnnouncement: String {
        let lines = lineCount
        let count = lines == 1 ? "one line" : "\(lines) lines"
        if let name = displayLanguage {
            return lines == 1 ? "\(name) code, \(count)." : "\(name) code block, \(count)."
        }
        return lines == 1 ? "Code, \(count)." : "Code block, \(count)."
    }

    /// First line with real content — used as the needle for highlighting the actual `<pre>` in
    /// `WebReaderView`, where the announcement text obviously doesn't exist in the DOM.
    var firstSubstantialLine: String? {
        source
            .components(separatedBy: "\n")
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.count >= 10 }
    }

    // MARK: - Language names

    /// Maps page language tokens to names Kokoro can pronounce. Symbols are spelled out
    /// ("C plus plus", not "C++") because the TTS front-end drops punctuation.
    private static let displayNames: [String: String] = [
        "bash": "Shell", "sh": "Shell", "zsh": "Shell", "shell": "Shell",
        "console": "Shell", "terminal": "Shell", "shell-session": "Shell", "powershell": "PowerShell",

        "js": "JavaScript", "javascript": "JavaScript", "jsx": "JavaScript", "mjs": "JavaScript",
        "ts": "TypeScript", "typescript": "TypeScript", "tsx": "TypeScript",

        "py": "Python", "python": "Python", "python3": "Python",
        "rb": "Ruby", "ruby": "Ruby",
        "go": "Go", "golang": "Go",
        "rs": "Rust", "rust": "Rust",
        "swift": "Swift",
        "kt": "Kotlin", "kotlin": "Kotlin",
        "java": "Java", "scala": "Scala", "clojure": "Clojure", "clj": "Clojure",
        "php": "PHP", "perl": "Perl", "lua": "Lua", "r": "R", "julia": "Julia",
        "dart": "Dart", "elixir": "Elixir", "ex": "Elixir", "erlang": "Erlang",
        "haskell": "Haskell", "hs": "Haskell", "ocaml": "OCaml", "zig": "Zig",

        "c": "C",
        "cpp": "C plus plus", "c++": "C plus plus", "cc": "C plus plus", "cxx": "C plus plus",
        "cs": "C sharp", "csharp": "C sharp", "c#": "C sharp",
        "objc": "Objective C", "objectivec": "Objective C", "m": "Objective C",

        "html": "HTML", "xml": "XML", "svg": "SVG", "css": "CSS",
        "scss": "SASS", "sass": "SASS", "less": "LESS",

        "json": "JSON", "jsonc": "JSON", "json5": "JSON",
        "yaml": "YAML", "yml": "YAML", "toml": "TOML", "ini": "INI",
        "sql": "SQL", "graphql": "GraphQL", "gql": "GraphQL", "proto": "Protobuf",

        "dockerfile": "Dockerfile", "docker": "Dockerfile",
        "makefile": "Makefile", "make": "Makefile", "cmake": "CMake",
        "nginx": "Nginx", "apache": "Apache",
        "diff": "Diff", "patch": "Diff", "git": "Git",
        "hcl": "Terraform", "terraform": "Terraform",
        "vim": "Vim", "regex": "Regular expression",
        "md": "Markdown", "markdown": "Markdown", "tex": "LaTeX", "latex": "LaTeX",
        "asm": "Assembly", "assembly": "Assembly", "wasm": "WebAssembly",
    ]
}
