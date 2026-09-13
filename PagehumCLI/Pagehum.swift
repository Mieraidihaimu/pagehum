// Modified for Pagehum: unified application and command-line naming.
import AppKit
import ArgumentParser
import AVFoundation
import Foundation
import KokoroSwift

@main
struct Pagehum: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pagehum",
        abstract: "Generate local speech audio with Kokoro on Apple Silicon.",
        version: "0.1.0",
        subcommands: [Generate.self, Voices.self]
    )
}

struct Assets: ParsableArguments {
    @Option(help: "Directory containing kokoro-v1_0.safetensors and voices.npz (or PAGEHUM_MODEL_DIR).")
    var modelDir: String?

    func directory() throws -> URL {
        if let path = modelDir ?? ProcessInfo.processInfo.environment["PAGEHUM_MODEL_DIR"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        guard let resourceURL = resourceBundle()?.resourceURL else {
            throw ValidationError("Missing pagehum-resources.bundle beside the executable. Rebuild with scripts/build-cli.sh or use --model-dir.")
        }
        return resourceURL
    }
}

func resourceBundle() -> Bundle? {
    let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
    let directory = executable.resolvingSymlinksInPath().deletingLastPathComponent()
    return Bundle(url: directory.appendingPathComponent("pagehum-resources.bundle"))
}

func report(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

/// All model work for a command is performed serially on this GCD queue.
private let synthesisQueue = DispatchQueue(label: "com.pagehum.cli.synthesis", qos: .userInitiated)
func onSynthesisQueue<T>(_ work: @escaping () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        synthesisQueue.async {
            // The NPZ dependency prints diagnostics to stdout. Keep stdout usable
            // by shell scripts (only the output pathname or voice names).
            let result = Result {
                fflush(stdout)
                let saved = dup(STDOUT_FILENO)
                guard saved >= 0 else { throw SpeechSynthesisError.message("Cannot configure CLI output.") }
                defer { fflush(stdout); dup2(saved, STDOUT_FILENO); close(saved) }
                guard dup2(STDERR_FILENO, STDOUT_FILENO) >= 0 else {
                    throw SpeechSynthesisError.message("Cannot redirect model diagnostics.")
                }
                return try work()
            }
            continuation.resume(with: result)
        }
    }
}

struct Voices: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List the English voices supported by this CLI.")
    @OptionGroup var assets: Assets

    mutating func run() async throws {
        let directory = try assets.directory()
        let names = try await onSynthesisQueue {
            let (_, voices) = try SpeechSynthesis.load(directory: directory)
            return voices.keys.map { String($0.split(separator: ".")[0]) }
                .filter { $0.hasPrefix("a") || $0.hasPrefix("b") }.sorted()
        }
        names.forEach { print($0) }
    }
}

struct Generate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Turn text, a UTF-8 file, stdin, or a web article into .m4a or .wav.")
    @Option(help: "Text to speak.") var text: String?
    @Option(help: "HTTP or HTTPS article URL.") var url: String?
    @Option(help: "Path to a UTF-8 text file.") var file: String?
    @Flag(help: "Read UTF-8 text from standard input.") var stdin = false
    @Option(name: [.short, .long], help: "Destination .m4a or .wav file.") var output: String
    @Option(help: "Voice name; use 'pagehum voices' to list choices.") var voice = "af_heart"
    @Option(help: "M4A preset: compact (32 kbps), balanced (48 kbps), high (64 kbps). WAV is always uncompressed.")
    var quality: Quality = .balanced
    @Flag(help: "Replace an existing output file after successful generation.") var force = false
    @OptionGroup var assets: Assets

    enum Quality: String, ExpressibleByArgument {
        case compact, balanced, high
        var bitRate: Int {
            switch self { case .compact: 32_000; case .balanced: 48_000; case .high: 64_000 }
        }
    }

    mutating func validate() throws {
        guard [text != nil, url != nil, file != nil, stdin].filter({ $0 }).count == 1 else {
            throw ValidationError("Choose exactly one input: --text, --url, --file, or --stdin.")
        }
        guard ["m4a", "wav"].contains(URL(fileURLWithPath: output).pathExtension.lowercased()) else {
            throw ValidationError("Output must end in .m4a or .wav.")
        }
        if let url {
            guard let parsed = URL(string: url), ["http", "https"].contains(parsed.scheme?.lowercased() ?? ""),
                  parsed.host != nil else { throw ValidationError("Provide a complete HTTP or HTTPS URL.") }
        }
        guard voice.hasPrefix("a") || voice.hasPrefix("b") else {
            throw ValidationError("This version supports American and British English voices. Run 'pagehum voices'.")
        }
    }

    @MainActor
    mutating func run() async throws {
        let outputURL = URL(fileURLWithPath: output)
        if !force && FileManager.default.fileExists(atPath: outputURL.path) {
            throw ValidationError("Output exists. Use --force to replace it.")
        }
        if let file, URL(fileURLWithPath: file).standardizedFileURL.resolvingSymlinksInPath()
            == outputURL.standardizedFileURL.resolvingSymlinksInPath() {
            throw ValidationError("Input and output must be different files.")
        }
        let directory = try assets.directory()
        let chunks: [String]
        if let url, let source = URL(string: url) {
            report("Extracting article…")
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.prohibited)
            guard let bundle = resourceBundle() else {
                throw ValidationError("URL extraction requires pagehum-resources.bundle beside the executable.")
            }
            let deadline = Task { @MainActor in
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                report("Error: Article extraction exceeded 60 seconds.")
                Foundation.exit(1)
            }
            defer { deadline.cancel() }
            let document = try await ReaderWebDocumentExtractor(bundle: bundle).extract(url: source)
            chunks = ReaderDocumentSentenceProjector.segment(
                document, splitProse: SentenceSegmenter.splitIntoSentences
            ).sentences
            report("Article: \(document.manifest.title)")
        } else {
            let input: String
            if let text { input = text }
            else if let file { input = try String(contentsOfFile: file, encoding: .utf8) }
            else {
                guard isatty(STDIN_FILENO) == 0 else {
                    throw ValidationError("Pipe text into --stdin, for example: pbpaste | pagehum generate --stdin -o speech.m4a")
                }
                let data = FileHandle.standardInput.readDataToEndOfFile()
                guard let decoded = String(data: data, encoding: .utf8) else {
                    throw ValidationError("Standard input must contain UTF-8 text.")
                }
                input = decoded
            }
            chunks = SentenceSegmenter.splitIntoSentences(input)
        }
        guard !chunks.isEmpty else { throw ValidationError("Input contains no readable text.") }
        let selectedVoice = voice, bitRate = quality.bitRate, overwrite = force
        report("Loading Kokoro; \(chunks.count) speech chunks…")
        let duration = try await onSynthesisQueue {
            let (engine, voices) = try SpeechSynthesis.load(directory: directory)
            guard let style = voices[selectedVoice + ".npy"] else {
                throw ValidationError("Unknown voice '\(selectedVoice)'. Run 'pagehum voices'.")
            }
            let language: Language = selectedVoice.hasPrefix("b") ? .enGB : .enUS
            guard let format = AVAudioFormat(standardFormatWithSampleRate: SpeechSynthesis.sampleRate, channels: 1) else {
                throw SpeechSynthesisError.message("Cannot create the speech audio format.")
            }
            let writer = try AudioExporter(output: outputURL, bitRate: bitRate, overwrite: overwrite)
            for (index, chunk) in chunks.enumerated() {
                do {
                    try autoreleasepool {
                        let audio = try SpeechSynthesis.generate(engine: engine, voice: style, language: language,
                                                                 text: chunk, format: format)
                        try writer.append(audio.buffer)
                    }
                } catch {
                    throw SpeechSynthesisError.message("Speech chunk \(index + 1)/\(chunks.count) failed: \(error.localizedDescription)")
                }
                report("Generated \(index + 1)/\(chunks.count)")
            }
            try writer.finish()
            return Double(writer.frameCount) / SpeechSynthesis.sampleRate
        }
        report(String(format: "Saved %.1f seconds of audio.", duration))
        print(outputURL.path)
    }
}
