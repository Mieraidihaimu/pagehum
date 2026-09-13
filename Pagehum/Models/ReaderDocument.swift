import Foundation

struct ReaderDocumentManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let currentExtractionVersion = 1
    static let currentProjectionVersion = 1

    enum SourceKind: String, Codable, Equatable, Sendable {
        case url
        case pdf
        case text
    }

    let schemaVersion: Int
    let extractionVersion: Int
    let projectionVersion: Int
    let sourceKind: SourceKind
    let title: String
    let createdAt: Date
    let contentHash: String
    let projectionRules: ReaderDocumentProjectionRules
    let originalURL: URL?
    let finalURL: URL?
    let canonicalURL: URL?
    let byline: String?
    let siteName: String?
    let excerpt: String?
    let language: String?
    let direction: String?
    let publicationDate: String?

    init(
        schemaVersion: Int = currentSchemaVersion,
        extractionVersion: Int = currentExtractionVersion,
        projectionVersion: Int = currentProjectionVersion,
        sourceKind: SourceKind,
        title: String,
        createdAt: Date,
        contentHash: String,
        projectionRules: ReaderDocumentProjectionRules,
        originalURL: URL? = nil,
        finalURL: URL? = nil,
        canonicalURL: URL? = nil,
        byline: String? = nil,
        siteName: String? = nil,
        excerpt: String? = nil,
        language: String? = nil,
        direction: String? = nil,
        publicationDate: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.extractionVersion = extractionVersion
        self.projectionVersion = projectionVersion
        self.sourceKind = sourceKind
        self.title = title
        self.createdAt = createdAt
        self.contentHash = contentHash
        self.projectionRules = projectionRules
        self.originalURL = originalURL
        self.finalURL = finalURL
        self.canonicalURL = canonicalURL
        self.byline = byline
        self.siteName = siteName
        self.excerpt = excerpt
        self.language = language
        self.direction = direction
        self.publicationDate = publicationDate
    }
}

struct ReaderDocumentProjectionRules: Codable, Equatable, Sendable {
    let blockSeparator: String
}

struct ReaderDocumentUTF16Range: Codable, Equatable, Sendable {
    let location: Int
    let length: Int

    var upperBound: Int { location + length }
}

struct ReaderDocumentBlock: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Equatable, Sendable {
        case prose
        case heading
        case listItem
        case quote
        case code
        case imageCaption
        case table
    }

    let id: String
    let kind: Kind
    let isSpeakable: Bool
    let rangeUTF16: ReaderDocumentUTF16Range
}

struct ReaderDocumentBlockIndex: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let blocks: [ReaderDocumentBlock]
}

struct ReaderDocument: Equatable, Sendable {
    let manifest: ReaderDocumentManifest
    let articleHTML: String
    let plainText: String
    let blockIndex: ReaderDocumentBlockIndex

    var blocks: [ReaderDocumentBlock] { blockIndex.blocks }

    func validateProjection() throws {
        guard manifest.schemaVersion == ReaderDocumentManifest.currentSchemaVersion,
              manifest.projectionVersion == ReaderDocumentManifest.currentProjectionVersion,
              blockIndex.schemaVersion == ReaderDocumentBlockIndex.currentSchemaVersion
        else { throw ReaderDocumentValidationError.unsupportedVersion }

        guard Set(blocks.map(\.id)).count == blocks.count else {
            throw ReaderDocumentValidationError.duplicateBlockID
        }

        let textLength = plainText.utf16.count
        guard !blocks.isEmpty else {
            if !plainText.isEmpty { throw ReaderDocumentValidationError.incompleteProjection }
            return
        }

        for (index, block) in blocks.enumerated() {
            let range = block.rangeUTF16
            guard range.location >= 0,
                  range.length > 0,
                  range.upperBound <= textLength
            else { throw ReaderDocumentValidationError.invalidRange }

            if index == 0 {
                guard range.location == 0 else {
                    throw ReaderDocumentValidationError.incompleteProjection
                }
            } else {
                let previousEnd = blocks[index - 1].rangeUTF16.upperBound
                guard previousEnd <= range.location else {
                    throw ReaderDocumentValidationError.overlappingRanges
                }
                let gap = (plainText as NSString).substring(
                    with: NSRange(location: previousEnd, length: range.location - previousEnd)
                )
                guard gap == manifest.projectionRules.blockSeparator else {
                    throw ReaderDocumentValidationError.invalidBlockSeparator
                }
            }
        }

        guard blocks.last?.rangeUTF16.upperBound == textLength else {
            throw ReaderDocumentValidationError.incompleteProjection
        }
    }
}

enum ReaderDocumentValidationError: Error, Equatable {
    case unsupportedVersion
    case duplicateBlockID
    case invalidRange
    case overlappingRanges
    case invalidBlockSeparator
    case incompleteProjection
}