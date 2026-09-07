import Foundation

public struct PolishConfiguration: Decodable, Sendable {
    public struct Selection: Decodable, Sendable {
        public var model: String = "apple/foundation"
        public var fallback: String = "rules"

        public init() {}
        private enum CodingKeys: String, CodingKey { case model, fallback }
        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            model = try values.decodeIfPresent(String.self, forKey: .model) ?? "apple/foundation"
            fallback = try values.decodeIfPresent(String.self, forKey: .fallback) ?? "rules"
        }
    }

    public struct Provider: Decodable, Sendable {
        public struct Options: Decodable, Sendable {
            public let baseURL: String
            public let apiKey: String?
            public let headers: [String: String]?
            public let timeoutMs: Double?
        }
        public struct Model: Decodable, Sendable {
            public enum API: String, Decodable, Sendable {
                case chatCompletions = "chat-completions"
                case responses
            }
            public struct Variant: Decodable, Sendable {
                public let reasoningEffort: String?
                public let textVerbosity: String?
                public let reasoningSummary: String?
            }
            public struct Limits: Decodable, Sendable {
                public let context: Int?
                public let output: Int?
            }
            public let name: String?
            public let api: API?
            public let reasoning: Bool?
            public let interleaved: Bool?
            public let variants: [String: Variant]?
            public let defaultVariant: String?
            public let limit: Limits?
            /// Transcript character budget; configure this with room left for instructions and output.
            public let chunkCharacterLimit: Int?
            public let maxTokens: Int?

            public func selectedVariant() throws -> Variant? {
                guard let defaultVariant else { return nil }
                guard let variant = variants?[defaultVariant] else {
                    throw LanguageModelBackendError.unavailable("defaultVariant must name a configured variant")
                }
                return variant
            }

            public func outputBudget() throws -> Int? {
                for value in [limit?.context, limit?.output, maxTokens].compactMap({ $0 }) {
                    guard value > 0 else {
                        throw LanguageModelBackendError.unavailable("Model token limits must be positive")
                    }
                }
                if let maximum = limit?.output, let maxTokens, maxTokens > maximum {
                    throw LanguageModelBackendError.unavailable("maxTokens exceeds limit.output")
                }
                let output = maxTokens ?? limit?.output
                if let context = limit?.context, let output, output >= context {
                    throw LanguageModelBackendError.unavailable("Output budget must be smaller than limit.context")
                }
                return output
            }
        }
        public let name: String?
        public let type: String
        public let options: Options
        public let models: [String: Model]
    }

    public var polish: Selection
    public let provider: [String: Provider]
    public static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/butterfly/butterfly.json")
    }

    private enum CodingKeys: String, CodingKey { case polish, provider }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        polish = try values.decodeIfPresent(Selection.self, forKey: .polish) ?? Selection()
        provider = try values.decodeIfPresent([String: Provider].self, forKey: .provider) ?? [:]
    }

    public static func load(from url: URL = fileURL) throws -> Self {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return try JSONDecoder().decode(Self.self, from: Data("{}".utf8))
        }
        do {
            return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        } catch {
            // Decoder diagnostics can contain configuration values, including credentials.
            throw LanguageModelBackendError.unavailable("Cannot read butterfly.json; check its JSON structure and field types")
        }
    }

    public var models: [(id: String, name: String)] {
        [("apple/foundation", "Apple Foundation Models"), ("builtin/rules", "Local Rules")]
        + provider.sorted { $0.key < $1.key }.flatMap { id, entry in
            entry.models.sorted { $0.key < $1.key }.map { modelID, model in
                ("\(id)/\(modelID)", "\(entry.name ?? id) / \(model.name ?? modelID)")
            }
        }
    }

    public func makeEngine(model override: String? = nil) throws -> SmartPolishEngine {
        guard polish.fallback == "rules" else {
            throw LanguageModelBackendError.unavailable("Only the rules fallback is supported")
        }
        let selected = override ?? polish.model
        switch selected {
        case "apple/foundation": return SmartPolishEngine()
        case "builtin/rules": return SmartPolishEngine(primaryBackend: RuleBasedLanguageModelBackend())
        default:
            let parts = selected.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2, let entry = provider[parts[0]],
                  let model = entry.models[parts[1]], entry.type == "openai-compatible" else {
                throw LanguageModelBackendError.unavailable("Unknown model or unsupported provider type in butterfly.json")
            }
            let limit = model.chunkCharacterLimit ?? 12_000
            guard limit >= 200, limit <= 1_000_000 else {
                throw LanguageModelBackendError.unavailable("chunkCharacterLimit must be between 200 and 1000000")
            }
            return SmartPolishEngine(
                primaryBackend: try EndpointLanguageModelBackend(
                    options: entry.options, modelID: parts[1], maxTokens: model.outputBudget(),
                    api: model.api ?? .chatCompletions, variant: model.selectedVariant(),
                    reasoning: model.reasoning, contextLimit: model.limit?.context
                ),
                chunkCharacterLimit: limit
            )
        }
    }
}
