import Foundation

/// Comprehensive developer and software engineering lexicon for speech recognition contextual biasing
public struct TechDictionary: Sendable {
    
    /// User custom dictionary file path: ~/.config/butterfly/dictionary.txt
    public static var userDictionaryURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/butterfly/dictionary.txt")
    }
    
    /// Dynamically loads custom vocabulary from ~/.config/butterfly/dictionary.txt
    public static func loadUserVocabulary() -> [String] {
        let url = userDictionaryURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .flatMap { line in
                line.components(separatedBy: CharacterSet(charactersIn: ",;"))
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
    }
    
    /// Combined, deduplicated vocabulary for ASR Contextual Strings (Apple Speech) & Whisper Prompt Biasing
    public static var allVocabulary: [String] {
        var set = Set<String>()
        var result: [String] = []
        
        for term in loadUserVocabulary() + engineeringVocabulary {
            if !set.contains(term) {
                set.insert(term)
                result.append(term)
            }
        }
        return result
    }
    
    /// Formatted Whisper Initial Prompt (Prime attention for code-switching & technical speech)
    public static var whisperInitialPrompt: String {
        let topTerms = allVocabulary.prefix(40).joined(separator: ", ")
        return "以下是繁體中文（台灣）與軟體工程技術對話，包含專有名詞：\(topTerms)。請忠實辨識並保持標準繁體中文與正確英文大小寫。"
    }
    
    /// Curated list of high-frequency engineering, developer, and cloud terminology (Code-Switching keywords)
    public static let engineeringVocabulary: [String] = [
        // MARK: - Core Architecture & System Concepts
        "Whitelist", "Blacklist", "Allowlist", "Blocklist", "Local", "Model", "Local Model", "Local Models",
        "Frontend", "Backend", "Fullstack", "Database", "DevOps", "CI/CD", "Pipeline", "Repository", "Repo",
        "Commit", "Branch", "Merge", "Rebase", "Pull Request", "PR", "Issue", "Fork", "Stash", "Cherry-pick",
        "Release", "Deploy", "Deployment", "Rollback", "Staging", "Production", "Prod", "Dev", "Debug", "Refactor",
        "Lint", "Linter", "Test", "Unit Test", "Integration Test", "E2E", "Benchmark", "Performance",
        
        // MARK: - Networking & Protocols
        "API", "Endpoint", "RESTful", "GraphQL", "gRPC", "WebSocket", "HTTP", "HTTPS", "TCP", "UDP",
        "IP", "DNS", "Domain", "Proxy", "Reverse Proxy", "VPN", "Gateway", "Router", "Firewall", "SSL", "TLS",
        "Token", "Auth", "OAuth", "JWT", "Session", "Cookie", "Cache", "Redis", "Memcached",
        "Payload", "Response", "Request", "Status Code", "JSON", "YAML", "XML", "CSV", "Base64", "UUID", "Regex",
        
        // MARK: - Databases & Storage
        "SQL", "NoSQL", "MySQL", "PostgreSQL", "SQLite", "MongoDB", "Cassandra", "DynamoDB",
        "Vector Database", "Embedding", "Vector", "Index", "Query", "Schema", "Migration", "ORM", "Prisma",
        
        // MARK: - Security & Threat Modeling
        "Threat Modeling", "Threat Model", "Threat Intelligence", "STRIDE", "Zero Trust",
        "Vulnerability", "CVE", "Exploit", "Penetration Test", "Pen Test", "OAuth", "SAML",
        "SSO", "RBAC", "ABAC", "Encryption", "Hashing", "Salt", "HMAC", "Bcrypt",
        
        // MARK: - AI & Machine Learning
        "AI", "LLM", "SLM", "GPT", "Claude", "Gemini", "Whisper", "WhisperKit", "DeepSeek", "Llama", "Mistral",
        "Agent", "Prompt", "Prompting", "Context", "Fine-tune", "Fine-tuning", "RAG", "Zero-shot", "Few-shot",
        "Parameter", "Weight", "Tokenizer", "Inference", "Core ML", "Metal", "ANE", "Neural Engine",
        "PyTorch", "TensorFlow", "ONNX", "Transformer", "Speech-to-Text", "ASR", "TTS", "VAD",
        "Antigravity", "Voice", "Slash Command", "Frozen Text", "Dynamic Window", "Trigger", "觸發", "觸發條件", "觸發點",
        
        // MARK: - Apple Ecosystem & Swift
        "Apple Silicon", "M1", "M2", "M3", "M4", "M1 Pro", "M2 Max", "M3 Ultra", "M4 Max",
        "macOS", "iOS", "iPadOS", "watchOS", "visionOS", "Swift", "SwiftUI", "UIKit", "AppKit",
        "Objective-C", "Xcode", "SPM", "Swift Package Manager", "CocoaPods", "Combine", "Async/Await",
        "Actor", "Sendable", "Task", "MainActor", "Butterfly", "OpenCC", "Menu", "Menu Bar", "Toolbar", "Status Bar",
        
        // MARK: - Programming Languages & Runtimes
        "Rust", "Go", "Golang", "Python", "PyPI", "Conda", "JavaScript", "TypeScript",
        "Node", "Node.js", "NPM", "Yarn", "PNPM", "Bun", "Deno", "Java", "Kotlin", "Android",
        "C", "C++", "C#", ".NET", "PHP", "Ruby", "Elixir", "Scala", "Haskell", "WebAssembly", "WASM",
        
        // MARK: - Frontend & Web Frameworks
        "React", "React Native", "Next.js", "Vue", "Vue.js", "Nuxt", "Angular", "Svelte", "SvelteKit",
        "Tailwind", "Tailwind CSS", "CSS", "HTML", "DOM", "Vite", "Webpack", "Babel", "ESBuild",
        "Electron", "Tauri", "Flutter", "Dart", "PWA",
        
        // MARK: - UI & Component Jargon
        "Component", "Layout", "Container", "Modal", "Dialog", "Popup", "Dropdown", "Menu", "Tooltip", "Panel",
        "Sidebar", "Navbar", "Header", "Footer", "Button", "Input", "Form", "Card", "Table", "List", "Grid",
        "Flex", "Flexbox", "Margin", "Padding", "Border", "Shadow", "Icon", "SVG", "Asset",
        "State", "Props", "Context", "Hook", "Reducer", "Dispatch", "Middleware", "Service", "Controller", "View",
        
        // MARK: - Cloud & Infrastructure
        "Docker", "Dockerfile", "Container", "Kubernetes", "K8s", "Pod", "Helm", "Terraform", "Ansible",
        "AWS", "GCP", "Google Cloud", "Azure", "Cloudflare", "Vercel", "Netlify", "Supabase", "Firebase",
        "S3", "EC2", "Lambda", "Cloud Run", "Serverless", "IAM", "KMS", "CDN", "Load Balancer",
        
        // MARK: - Developer Productivity & Tools
        "SDK", "CLI", "GUI", "UI", "UX", "Figma", "Sketch", "Postman", "Insomnia", "Swagger",
        "Jira", "Confluence", "Slack", "Notion", "Discord", "Linear", "Zoom", "Google Meet", "Teams",
        "GitHub", "GitLab", "Bitbucket", "Stack Overflow", "Homebrew", "Brew", "Terminal", "Zsh", "Bash",
        "VS Code", "Cursor", "Zed", "IntelliJ", "Vim", "Neovim", "Emacs",
        
        // MARK: - Common Status & Action Slang
        "Online", "Offline", "Status", "Success", "Failed", "Error", "Warning", "Info", "Fatal",
        "Timeout", "Crash", "Hang", "Freeze", "Lag", "Spike", "Drop", "Peak", "Traffic", "Latency",
        "Throughput", "Bandwidth", "Sync", "Async", "Callback", "Event", "Listener", "Emitter",
        "Override", "Inherit", "Inject", "Dependency Injection", "Singleton", "Factory", "Adapter",
        "Esc", "Space", "Option", "Command", "Shift", "Control", "Tab", "Enter", "Backspace", "Delete"
    ]
}
