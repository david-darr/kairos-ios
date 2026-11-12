import SwiftUI

nonisolated enum ModelEngine: String, CaseIterable, Hashable, Sendable {
    case ollama = "Ollama", builtIn = "Built-in engine"
}

nonisolated struct LocalModel: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var sizeGB: Double
    var running = false
}

nonisolated struct CatalogModel: Identifiable, Hashable, Sendable {
    let id: String
    var label: String
    var params: String
    var about: String
    var sizeGB: Double
}

nonisolated enum PullState: Hashable, Sendable {
    case pulling(Double)
    case done
    case failed(String)
}

nonisolated enum ChatAdd: Hashable, Sendable { case adding, added }

nonisolated enum RecommendState: Hashable, Sendable {
    case idle
    case confirming
    case downloading(Double)
    case starting
    case connected
}

nonisolated enum SetupChoiceState: Hashable, Sendable {
    case ready, notSet, notInstalled, waiting
}

nonisolated struct SetupChoice: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var detail: String
    var symbol: String
    var state: SetupChoiceState
}

/// What the local models screen reads and changes.
protocol LocalModelsProviding: AnyObject {
    var engine: ModelEngine { get set }
    var ollamaReachable: Bool { get }
    func installed(_ engine: ModelEngine) -> [LocalModel]
    func catalog(_ engine: ModelEngine) -> [CatalogModel]
}

@Observable
final class LocalModelsStore: LocalModelsProviding {
    var engine: ModelEngine = .ollama
    var ollamaReachable = true
    var checking = false
    var ollama: [LocalModel] = LocalModelsSample.ollama
    var builtIn: [LocalModel] = LocalModelsSample.builtIn
    var pulls: [String: PullState] = [:]
    var chat: [String: ChatAdd] = [:]
    var failedOnce: Set<String> = []
    var recommend: RecommendState = .idle
    var choices: [SetupChoice] = LocalModelsSample.choices

    func installed(_ engine: ModelEngine) -> [LocalModel] { engine == .ollama ? ollama : builtIn }
    func catalog(_ engine: ModelEngine) -> [CatalogModel] { engine == .ollama ? LocalModelsSample.ollamaCatalog : LocalModelsSample.builtInCatalog }

    var runningBuiltIn: LocalModel? { builtIn.first { $0.running } }

    func totalGB(_ engine: ModelEngine) -> Double { installed(engine).reduce(0) { $0 + $1.sizeGB } }

    func recheck() {
        checking = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(Motion.snappy) {
                ollamaReachable = true
                checking = false
            }
        }
    }

    func useInChat(_ model: LocalModel) {
        chat[model.id] = .adding
        Task {
            try? await Task.sleep(for: .seconds(1.0))
            withAnimation(Motion.snappy) { chat[model.id] = .added }
            Haptics.success()
        }
    }

    func delete(_ model: LocalModel, from engine: ModelEngine) {
        withAnimation(Motion.snappy) {
            if engine == .ollama { ollama.removeAll { $0.id == model.id } } else { builtIn.removeAll { $0.id == model.id } }
        }
        chat[model.id] = nil
    }

    func start(_ model: LocalModel) {
        for index in builtIn.indices { builtIn[index].running = builtIn[index].id == model.id }
    }

    func stopEngine() {
        for index in builtIn.indices { builtIn[index].running = false }
    }

    func pull(_ entry: CatalogModel, into engine: ModelEngine) {
        pulls[entry.id] = .pulling(0)
        let failFirst = entry.id == LocalModelsSample.flakyID && !failedOnce.contains(entry.id)
        Task {
            for step in 1...20 {
                try? await Task.sleep(for: .seconds(0.18))
                if failFirst && step == 9 {
                    failedOnce.insert(entry.id)
                    withAnimation(Motion.snappy) { pulls[entry.id] = .failed("the download stopped. Check the PC's connection and try again.") }
                    return
                }
                pulls[entry.id] = .pulling(Double(step) / 20)
            }
            withAnimation(Motion.snappy) {
                pulls[entry.id] = .done
                let model = LocalModel(id: entry.id, name: entry.label.lowercased().replacingOccurrences(of: " ", with: "-") + ":" + entry.params.lowercased(), sizeGB: entry.sizeGB)
                if engine == .ollama {
                    if !ollama.contains(where: { $0.id == model.id }) { ollama.append(model) }
                } else if !builtIn.contains(where: { $0.id == model.id }) {
                    builtIn.append(model)
                }
            }
            Haptics.success()
        }
    }

    func isInstalled(_ entry: CatalogModel, _ engine: ModelEngine) -> Bool {
        installed(engine).contains { $0.id == entry.id }
    }

    func downloadRecommended() {
        recommend = .downloading(0)
        Task {
            for step in 1...25 {
                try? await Task.sleep(for: .seconds(0.15))
                recommend = .downloading(Double(step) / 25)
            }
            withAnimation(Motion.snappy) { recommend = .starting }
            try? await Task.sleep(for: .seconds(1.0))
            withAnimation(Motion.snappy) {
                recommend = .connected
                if let index = choices.firstIndex(where: { $0.id == "local" }) { choices[index].state = .ready }
            }
            Haptics.success()
        }
    }

    func choose(_ id: String) {
        guard let index = choices.firstIndex(where: { $0.id == id }) else { return }
        choices[index].state = .waiting
    }

    func cancelWaiting(_ id: String) {
        guard let index = choices.firstIndex(where: { $0.id == id }) else { return }
        choices[index].state = LocalModelsSample.choices.first(where: { $0.id == id })?.state ?? .notSet
    }
}

nonisolated enum LocalModelsSample {
    static let flakyID = "c-mistral"

    static let ollama = [
        LocalModel(id: "o-qwen", name: "qwen3:8b", sizeGB: 5.2, running: true),
        LocalModel(id: "o-llama", name: "llama3.2:3b", sizeGB: 2.0),
        LocalModel(id: "o-embed", name: "nomic-embed-text", sizeGB: 0.3),
    ]

    static let builtIn = [
        LocalModel(id: "b-gemma", name: "gemma-3-4b-q4", sizeGB: 2.5, running: true),
        LocalModel(id: "b-phi", name: "phi-4-mini-q4", sizeGB: 2.4),
    ]

    static let ollamaCatalog = [
        CatalogModel(id: "c-qwen14", label: "Qwen 3", params: "14B", about: "Strong all-round model for writing and code. Needs a good graphics card.", sizeGB: 9.3),
        CatalogModel(id: flakyID, label: "Mistral Small", params: "24B", about: "Careful answers and long documents.", sizeGB: 14.0),
        CatalogModel(id: "c-gemma", label: "Gemma 3", params: "4B", about: "Small and quick. Fine for simple chats on most PCs.", sizeGB: 3.3),
        CatalogModel(id: "c-deepseek", label: "DeepSeek R1", params: "8B", about: "Thinks step by step before it answers.", sizeGB: 4.9),
        CatalogModel(id: "c-llava", label: "LLaVA", params: "7B", about: "Reads pictures as well as text.", sizeGB: 4.7),
    ]

    static let builtInCatalog = [
        CatalogModel(id: "c-qwen-gguf", label: "Qwen 3 GGUF", params: "4B", about: "Runs on most PCs without a graphics card.", sizeGB: 2.6),
        CatalogModel(id: "c-llama-gguf", label: "Llama 3.2 GGUF", params: "3B", about: "Light and fast for short replies.", sizeGB: 2.0),
        CatalogModel(id: "c-mistral-gguf", label: "Mistral 7B GGUF", params: "7B", about: "A bigger model for better answers.", sizeGB: 4.4),
        CatalogModel(id: "c-smol", label: "SmolLM 2", params: "1.7B", about: "The smallest. Good for trying things out.", sizeGB: 1.1),
    ]

    static let choices = [
        SetupChoice(id: "claude", title: "I pay for Claude", detail: "Use your Claude subscription", symbol: "sparkle", state: .ready),
        SetupChoice(id: "chatgpt", title: "I pay for ChatGPT", detail: "Use your ChatGPT plan through Codex", symbol: "bubble.left.and.bubble.right", state: .notSet),
        SetupChoice(id: "gemini", title: "Antigravity (Gemini)", detail: "Use Gemini through the Antigravity app", symbol: "diamond", state: .notInstalled),
        SetupChoice(id: "key", title: "I have an API key", detail: "OpenAI, Anthropic, OpenRouter or Google", symbol: "key", state: .notSet),
        SetupChoice(id: "local", title: "Free, on this computer", detail: "A small model that runs on your PC", symbol: "cpu", state: .notSet),
    ]

    static let glossary = [
        ("CLI", "A program you run in a terminal. Kairos runs it for you."),
        ("Agent and harness", "The agent is the model. The harness is the program that lets it read files and run commands."),
        ("API key", "A secret code from a model company. You pay for what you use."),
        ("Subscription or pay per use", "A plan has a monthly price. An API key costs a little for each reply."),
        ("Local model", "A model that runs on your own PC. Free and private, but slower and simpler."),
    ]
}
