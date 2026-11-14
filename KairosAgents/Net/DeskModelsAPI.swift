import Foundation

// The desktop's local model routes (routes/cookbook_routes.py over services/cookbook_service.py,
// core/ollama_client.py and core/llamacpp_engine.py; routes/model_setup_routes.py over
// services/model_setup.py), as the phone reads them for the Local models screen and its setup sheet.
// Every /api/cookbook route answers an admin account only.
//
// - Ollama: GET status says whether Ollama answers. installed is Ollama's own list (name, size in bytes), running
//   is what it holds in memory. Both answer 503 when Ollama is not reachable. POST pull/{name} starts a download
//   and answers at once; GET pull/{name}/status says how far it is (`status`, `completed`, `total`, `done`,
//   `error`; "not_started" when this run of the desktop never saw the name). DELETE models/{name} answers 503 for
//   any failure. POST register makes a NEW model connection on every call.
// - Built-in engine: the same shape under /engine. start waits up to 60 seconds for the server, so the phone's own
//   wait can end first; stop and register follow. Only one model runs at a time.
// - Neither catalog lists a file size. Neither pull nor download takes a request id.
// - The catalog rows of the built-in engine carry a download address, and register answers carry a server address:
//   neither is declared here, so neither is ever decoded. Setup status carries paths and versions: not decoded.
// - The phone never calls: pull or download with a name outside the catalog, cancel, model sign-in, the Codex
//   install routes, API key tests or connections.

// MARK: - Lists

nonisolated struct DeskModelsCatalogDTO: Decodable, Hashable, Sendable {
    var name: String
    var label: String?
    var params: String?
    var description: String?

    private enum CodingKeys: String, CodingKey { case name, label, params, description }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let given = try container.decode(String.self, forKey: .name)
        guard !given.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "empty name"))
        }
        name = given
        label = try? container.decodeIfPresent(String.self, forKey: .label)
        params = try? container.decodeIfPresent(String.self, forKey: .params)
        description = try? container.decodeIfPresent(String.self, forKey: .description)
    }
}

/// One row of Ollama's installed list, or of the built-in engine's downloaded list. Ollama names the model in
/// `name` and in `model`; the engine in `name`.
nonisolated struct DeskModelsInstalledDTO: Decodable, Hashable, Sendable {
    var name: String
    /// Bytes on disk.
    var size: Double?

    private enum CodingKeys: String, CodingKey { case name, model, size }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let first = try? container.decodeIfPresent(String.self, forKey: .name)
        let second = try? container.decodeIfPresent(String.self, forKey: .model)
        guard let given = first ?? second, !given.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "no name"))
        }
        name = given
        size = try? container.decodeIfPresent(Double.self, forKey: .size)
    }
}

/// One model Ollama holds in memory (its /api/ps).
nonisolated struct DeskModelsRunningDTO: Decodable, Hashable, Sendable {
    var name: String
    /// Bytes in memory.
    var size: Double?

    private enum CodingKeys: String, CodingKey { case name, model, size }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let first = try? container.decodeIfPresent(String.self, forKey: .name)
        let second = try? container.decodeIfPresent(String.self, forKey: .model)
        guard let given = first ?? second, !given.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "no name"))
        }
        name = given
        size = try? container.decodeIfPresent(Double.self, forKey: .size)
    }
}

// MARK: - Status and progress

nonisolated struct DeskModelsReachDTO: Decodable, Hashable, Sendable {
    var reachable: Bool?

    private enum CodingKeys: String, CodingKey { case reachable }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reachable = try? container.decodeIfPresent(Bool.self, forKey: .reachable)
    }
}

/// GET /api/cookbook/engine/status. The address and port it also carries are not decoded.
nonisolated struct DeskModelsEngineStatusDTO: Decodable, Hashable, Sendable {
    var running: Bool?
    var model: String?

    private enum CodingKeys: String, CodingKey { case running, model }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        running = try? container.decodeIfPresent(Bool.self, forKey: .running)
        model = try? container.decodeIfPresent(String.self, forKey: .model)
    }
}

/// A pull's or a download's status (cookbook_service.get_pull_progress, llamacpp_engine.get_download_progress), and
/// the recommended model's setup (cookbook_service.recommended_progress, which adds a `status` of its own).
/// `status` is "not_started" for a name this run of the desktop never saw. While a pull runs, Ollama's own words
/// ("pulling manifest", "verifying sha256 digest") are the status; `done` is what says it is over. The text of
/// `error` can carry an address, so only whether there is one is kept. A setup answer's `connection` is not decoded.
nonisolated struct DeskModelsProgressDTO: Decodable, Hashable, Sendable {
    var status: String?
    var completed: Double?
    var total: Double?
    var done: Bool?
    var hasError: Bool

    private enum CodingKeys: String, CodingKey { case status, completed, total, done, error }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try? container.decodeIfPresent(String.self, forKey: .status)
        completed = try? container.decodeIfPresent(Double.self, forKey: .completed)
        total = try? container.decodeIfPresent(Double.self, forKey: .total)
        done = try? container.decodeIfPresent(Bool.self, forKey: .done)
        let text = (try? container.decodeIfPresent(String.self, forKey: .error)) ?? nil
        hasError = !(text ?? "").isEmpty
    }
}

/// GET /api/cookbook/engine/recommendation: the first catalog row with the disk numbers. The download address in it
/// is not decoded.
nonisolated struct DeskModelsRecommendationDTO: Decodable, Hashable, Sendable {
    var name: String
    var label: String?
    var params: String?
    var description: String?
    var estimatedDownloadBytes: Double?
    var diskFreeBytes: Double?
    var downloaded: Bool?

    private enum CodingKeys: String, CodingKey {
        case name, label, params, description, estimatedDownloadBytes, diskFreeBytes, downloaded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let given = try container.decode(String.self, forKey: .name)
        guard !given.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "empty name"))
        }
        name = given
        label = try? container.decodeIfPresent(String.self, forKey: .label)
        params = try? container.decodeIfPresent(String.self, forKey: .params)
        description = try? container.decodeIfPresent(String.self, forKey: .description)
        estimatedDownloadBytes = try? container.decodeIfPresent(Double.self, forKey: .estimatedDownloadBytes)
        diskFreeBytes = try? container.decodeIfPresent(Double.self, forKey: .diskFreeBytes)
        downloaded = try? container.decodeIfPresent(Bool.self, forKey: .downloaded)
    }
}

/// What register answers: the new connection. Only its id is kept; its address is never decoded.
nonisolated struct DeskModelsRegisteredDTO: Decodable, Hashable, Sendable {
    var id: String?

    private enum CodingKeys: String, CodingKey { case id }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decodeIfPresent(String.self, forKey: .id)
    }
}

// MARK: - Model setup status

/// One row of a setup connection list. Nothing in it is read: only how many rows there are.
nonisolated struct DeskModelsRowDTO: Decodable, Hashable, Sendable {}

nonisolated struct DeskModelsSignInDTO: Decodable, Hashable, Sendable {
    var available: Bool?
    var installed: Bool?
    var signedIn: Bool?

    private enum CodingKeys: String, CodingKey { case available, installed, signedIn }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        available = try? container.decodeIfPresent(Bool.self, forKey: .available)
        installed = try? container.decodeIfPresent(Bool.self, forKey: .installed)
        signedIn = try? container.decodeIfPresent(Bool.self, forKey: .signedIn)
    }

    /// Present on the computer, whichever word the desktop used for it.
    var present: Bool { (available ?? installed) ?? false }
}

nonisolated struct DeskModelsConnectionsDTO: Decodable, Sendable {
    var local: DeskForgeList<DeskModelsRowDTO>?
    var api: DeskForgeList<DeskModelsRowDTO>?

    private enum CodingKeys: String, CodingKey { case local, api }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        local = try? container.decodeIfPresent(DeskForgeList<DeskModelsRowDTO>.self, forKey: .local)
        api = try? container.decodeIfPresent(DeskForgeList<DeskModelsRowDTO>.self, forKey: .api)
    }
}

/// GET /api/model-setup/status. The program paths and versions in it are not decoded.
nonisolated struct DeskModelsSetupStatusDTO: Decodable, Sendable {
    var claude: DeskModelsSignInDTO?
    var codex: DeskModelsSignInDTO?
    var antigravity: DeskModelsSignInDTO?
    var connections: DeskModelsConnectionsDTO?

    private enum CodingKeys: String, CodingKey { case claude, codex, antigravity, connections }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        claude = try? container.decodeIfPresent(DeskModelsSignInDTO.self, forKey: .claude)
        codex = try? container.decodeIfPresent(DeskModelsSignInDTO.self, forKey: .codex)
        antigravity = try? container.decodeIfPresent(DeskModelsSignInDTO.self, forKey: .antigravity)
        connections = try? container.decodeIfPresent(DeskModelsConnectionsDTO.self, forKey: .connections)
    }
}

// MARK: - Small helpers

nonisolated enum DeskModelsWire {
    /// A model name goes into a path as it is. Letters, digits and . _ : - only (a catalog name, or an installed
    /// tag such as "llama3.2:latest"); a name with a slash or anything else is left to the desktop.
    static func pathOK(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 120, name != ".", name != ".." else { return false }
        return name.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || "._:-".unicodeScalars.contains($0) }
    }

    static func pathName(_ name: String) throws -> String {
        guard pathOK(name) else { throw APIError.unreadable("model name") }
        return name
    }

    /// Bytes in the words a person reads: "4.7 GB".
    static func bytes(_ value: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(max(0, value)), countStyle: .file)
    }

    /// The size class a catalog row gives ("7B", "3.8B", "137M") as billions of parameters, or nil.
    static func billions(_ params: String) -> Double? {
        let text = params.trimmingCharacters(in: .whitespaces).uppercased()
        guard let last = text.last, last == "B" || last == "M", let number = Double(text.dropLast()), number > 0 else { return nil }
        return last == "B" ? number : number / 1000
    }

    /// A rough download size from the size class, for the confirm: neither catalog lists one. A common 4-bit file is
    /// about 0.6 GB for every billion parameters. Said as an estimate wherever it is shown.
    static func estimate(params: String) -> String? {
        guard let size = billions(params) else { return nil }
        let gigabytes = size * 0.6 + 0.2
        if gigabytes < 1 { return "about \(Int((gigabytes * 10).rounded()) * 100) MB" }
        return String(format: "about %.1f GB", gigabytes)
    }
}

// MARK: - The calls

extension APIClient {

    // Ollama

    /// GET /api/cookbook/status.
    func deskModelsOllamaStatus() async throws -> DeskModelsReachDTO {
        try await get("/api/cookbook/status")
    }

    /// GET /api/cookbook/catalog: the desktop's own short list.
    func deskModelsOllamaCatalog() async throws -> DeskForgeList<DeskModelsCatalogDTO> {
        try await get("/api/cookbook/catalog")
    }

    /// GET /api/cookbook/installed. 503 when Ollama is not reachable.
    func deskModelsOllamaInstalled() async throws -> DeskForgeList<DeskModelsInstalledDTO> {
        try await get("/api/cookbook/installed")
    }

    /// GET /api/cookbook/running. 503 when Ollama is not reachable.
    func deskModelsOllamaRunning() async throws -> DeskForgeList<DeskModelsRunningDTO> {
        try await get("/api/cookbook/running")
    }

    // The built-in engine

    func deskModelsEngineCatalog() async throws -> DeskForgeList<DeskModelsCatalogDTO> {
        try await get("/api/cookbook/engine/catalog")
    }

    func deskModelsEngineDownloaded() async throws -> DeskForgeList<DeskModelsInstalledDTO> {
        try await get("/api/cookbook/engine/downloaded")
    }

    func deskModelsEngineStatus() async throws -> DeskModelsEngineStatusDTO {
        try await get("/api/cookbook/engine/status")
    }

    /// POST /api/cookbook/engine/start/{name}: waits for the server to come up (up to 60 seconds), so it is sent with
    /// its own 75-second wait; the usual 30 seconds would end first and mark the whole desktop offline. A model that
    /// is not downloaded is 404.
    func deskModelsEngineStart(_ name: String) async throws -> DeskModelsEngineStatusDTO {
        let part = try DeskModelsWire.pathName(name)
        var request = try urlRequest("POST", "/api/cookbook/engine/start/" + part)
        request.timeoutInterval = 75
        request.httpBody = Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let data = try await send(request)
        do {
            return try KJSON.decode(DeskModelsEngineStatusDTO.self, from: data)
        } catch {
            throw APIError.unreadable(String(describing: error))
        }
    }

    func deskModelsEngineStop() async throws -> DeskForgeOkDTO {
        try await post("/api/cookbook/engine/stop")
    }

    // Both engines

    /// A pull (Ollama) or a download (built-in). Answers at once; the desktop keeps no second one for a name that is
    /// already running. The name is from the catalog the desktop returned, never typed.
    func deskModelsPull(_ engine: ModelEngine, _ name: String) async throws -> DeskForgeOkDTO {
        let part = try DeskModelsWire.pathName(name)
        return try await post(engine == .ollama ? "/api/cookbook/pull/" + part : "/api/cookbook/engine/download/" + part)
    }

    func deskModelsPullStatus(_ engine: ModelEngine, _ name: String) async throws -> DeskModelsProgressDTO {
        let part = try DeskModelsWire.pathName(name)
        return try await get(engine == .ollama ? "/api/cookbook/pull/" + part + "/status" : "/api/cookbook/engine/download/" + part + "/status")
    }

    /// DELETE: Ollama answers 503 for any failure; the built-in engine stops the model first when it runs.
    func deskModelsDelete(_ engine: ModelEngine, _ name: String) async throws -> DeskForgeOkDTO {
        let part = try DeskModelsWire.pathName(name)
        return try await request("DELETE", engine == .ollama ? "/api/cookbook/models/" + part : "/api/cookbook/engine/models/" + part)
    }

    /// POST register: makes a NEW model connection every time it is sent. The built-in engine refuses (400) a model
    /// that is not the running one.
    func deskModelsRegister(_ engine: ModelEngine, _ name: String) async throws -> DeskModelsRegisteredDTO {
        try await post(engine == .ollama ? "/api/cookbook/register" : "/api/cookbook/engine/register", json: ["name": name])
    }

    // The recommended model

    func deskModelsRecommendation() async throws -> DeskModelsRecommendationDTO {
        try await get("/api/cookbook/engine/recommendation")
    }

    /// POST .../engine/setup/{name}: downloads (when needed), starts and connects the recommended model in the
    /// background. 400 when the disk is too full.
    func deskModelsSetup(_ name: String) async throws -> DeskForgeOkDTO {
        let part = try DeskModelsWire.pathName(name)
        return try await post("/api/cookbook/engine/setup/" + part)
    }

    func deskModelsSetupProgress(_ name: String) async throws -> DeskModelsProgressDTO {
        let part = try DeskModelsWire.pathName(name)
        return try await get("/api/cookbook/engine/setup/" + part + "/status")
    }

    /// GET /api/model-setup/status: any account may read it.
    func deskModelsSetupStatus() async throws -> DeskModelsSetupStatusDTO {
        try await get("/api/model-setup/status")
    }
}

// MARK: - Samples and decode checks

nonisolated enum DeskModelsSamples {

    static let ollamaCatalog = #"""
    [{"name": "llama3.2", "label": "Llama 3.2", "params": "3B", "description": "A small, fast general model."},
     {"name": "qwen2.5", "label": "Qwen 2.5", "params": "7B", "description": null},
     {"name": "nomic-embed-text", "label": "Nomic Embed Text", "params": "137M", "description": "Small, not for chat."},
     {"label": "No name"},
     5]
    """#

    static let engineCatalog = #"""
    [{"name": "qwen2.5-0.5b-instruct", "label": "Qwen 2.5 0.5B Instruct", "params": "0.5B",
      "url": "https://models.example.com/small.gguf", "description": "Tiny and fast."},
     {"name": "phi-3.5-mini-instruct", "label": "Phi-3.5 Mini Instruct", "params": "3.8B",
      "url": "https://models.example.com/mini.gguf", "description": "Needs more memory."}]
    """#

    static let installed = #"""
    [{"name": "llama3.2:latest", "model": "llama3.2:latest", "size": 2019393189, "digest": "abc", "details": {"family": "llama"}},
     {"model": "qwen2.5:7b", "size": 4683087332},
     {"name": "broken", "size": "big"},
     {"size": 12},
     7]
    """#

    static let running = #"""
    [{"name": "llama3.2:latest", "model": "llama3.2:latest", "size": 3300000000, "size_vram": 3300000000, "expires_at": "2026-01-01T00:00:00Z"}]
    """#

    static let downloaded = #"""
    [{"name": "qwen2.5-0.5b-instruct", "size": 491400000}, {"name": "old-model", "size": null}]
    """#

    static let reachable = #"{"reachable": true}"#
    static let unreachable = #"{"reachable": false}"#

    static let engineIdle = #"{"running": false, "model": null, "port": null, "base_url": null}"#
    static let engineRunning = #"{"running": true, "model": "qwen2.5-0.5b-instruct", "port": 8600, "base_url": "http://127.0.0.1:8600/v1"}"#

    static let pulling = #"{"status": "pulling", "completed": 524288000, "total": 2019393189, "done": false, "error": null}"#
    static let pullNone = #"{"status": "not_started"}"#
    static let pullDone = #"{"status": "success", "completed": 2019393189, "total": 2019393189, "done": true, "error": null}"#
    static let pullFailed = #"{"status": "error", "completed": 10, "total": 20, "done": true, "error": "Client error for url https://example.com/x"}"#
    static let pullCancelled = #"{"status": "cancelled", "done": true, "error": null}"#
    static let pullWords = #"{"status": "verifying sha256 digest", "completed": 5, "total": 5, "done": false, "error": null}"#

    static let recommendation = #"""
    {"name": "qwen2.5-0.5b-instruct", "label": "Qwen 2.5 0.5B Instruct", "params": "0.5B",
     "url": "https://models.example.com/small.gguf", "description": "Tiny and fast.",
     "estimated_download_bytes": 400000000, "disk_free_bytes": 118000000000, "downloaded": false}
    """#

    static let setupConnected = #"""
    {"status": "connected", "done": true, "completed": 491400000, "total": 491400000,
     "connection": {"id": "a1b2c3d4e5f6", "name": "qwen", "base_url": "http://127.0.0.1:8600/v1", "model": "qwen"}}
    """#
    static let setupError = #"{"status": "error", "done": true, "error": "The local download failed. Try again from Cookbook."}"#
    static let setupIdle = #"{"status": "not_started", "done": false}"#

    static let registered = #"{"id": "a1b2c3d4e5f6", "name": "llama3.2:latest", "base_url": "http://localhost:11434/v1", "model": "llama3.2:latest", "kind": "local", "has_api_key": false}"#

    static let setupStatus = #"""
    {"claude": {"available": true, "source": "bundled", "signed_in": true},
     "codex": {"installed": false, "version": null, "path": null, "signed_in": false},
     "antigravity": {"installed": true, "path": "C:/tools/agy", "version": "1.4.7", "signed_in": false, "status": "needs_sign_in", "models": []},
     "node": {"npm": true},
     "connections": {"claude_cli": [{"id": "x", "name": "Claude", "kind": "claude_cli", "model": ""}],
                     "codex_cli": [], "antigravity_cli": [], "api": [{"id": "y", "name": "Key", "kind": "api", "model": "m"}],
                     "local": [{"id": "z", "name": "Local", "kind": "local", "model": "qwen"}, {"id": "w", "name": "Local 2", "kind": "local", "model": "phi"}]}}
    """#

    static let checks: [DecodeCheck] = [
        DecodeCheck("deskmodels.catalogs") {
            let ollama = try KJSON.decode(DeskForgeList<DeskModelsCatalogDTO>.self, from: ollamaCatalog)
            let engine = try KJSON.decode(DeskForgeList<DeskModelsCatalogDTO>.self, from: engineCatalog)
            guard ollama.items.count == 3, ollama.skipped == 2, ollama.items[0].name == "llama3.2",
                  ollama.items[0].params == "3B", ollama.items[1].description == nil, ollama.items[2].params == "137M",
                  engine.items.count == 2, engine.skipped == 0, engine.items[1].label == "Phi-3.5 Mini Instruct",
                  engine.items[0].params == "0.5B" else {
                throw SampleMismatch("catalog fields")
            }
            return "3 Ollama rows, 2 skipped, 2 engine rows, no address kept"
        },
        DecodeCheck("deskmodels.installed") {
            let list = try KJSON.decode(DeskForgeList<DeskModelsInstalledDTO>.self, from: installed)
            let memory = try KJSON.decode(DeskForgeList<DeskModelsRunningDTO>.self, from: DeskModelsSamples.running)
            let engine = try KJSON.decode(DeskForgeList<DeskModelsInstalledDTO>.self, from: downloaded)
            guard list.items.count == 3, list.skipped == 2, list.items[0].name == "llama3.2:latest",
                  list.items[0].size == 2019393189, list.items[1].name == "qwen2.5:7b", list.items[2].name == "broken",
                  list.items[2].size == nil,
                  memory.items.count == 1, memory.items[0].size == 3300000000,
                  engine.items.count == 2, engine.items[0].size == 491400000, engine.items[1].size == nil else {
                throw SampleMismatch("installed fields")
            }
            return "3 installed, 2 skipped, 1 running, 2 downloaded"
        },
        DecodeCheck("deskmodels.status") {
            let on = try KJSON.decode(DeskModelsReachDTO.self, from: reachable)
            let off = try KJSON.decode(DeskModelsReachDTO.self, from: unreachable)
            let idle = try KJSON.decode(DeskModelsEngineStatusDTO.self, from: engineIdle)
            let busy = try KJSON.decode(DeskModelsEngineStatusDTO.self, from: engineRunning)
            guard on.reachable == true, off.reachable == false, idle.running == false, idle.model == nil,
                  busy.running == true, busy.model == "qwen2.5-0.5b-instruct" else {
                throw SampleMismatch("status fields")
            }
            return "Ollama up and down, engine idle and running"
        },
        DecodeCheck("deskmodels.progress") {
            let going = try KJSON.decode(DeskModelsProgressDTO.self, from: pulling)
            let unseen = try KJSON.decode(DeskModelsProgressDTO.self, from: pullNone)
            let done = try KJSON.decode(DeskModelsProgressDTO.self, from: pullDone)
            let failed = try KJSON.decode(DeskModelsProgressDTO.self, from: pullFailed)
            let cancelled = try KJSON.decode(DeskModelsProgressDTO.self, from: pullCancelled)
            let words = try KJSON.decode(DeskModelsProgressDTO.self, from: pullWords)
            let connected = try KJSON.decode(DeskModelsProgressDTO.self, from: setupConnected)
            let broken = try KJSON.decode(DeskModelsProgressDTO.self, from: setupError)
            let waiting = try KJSON.decode(DeskModelsProgressDTO.self, from: setupIdle)
            guard going.done == false, going.completed == 524288000, going.total == 2019393189, !going.hasError,
                  unseen.status == "not_started", unseen.done == nil, unseen.total == nil,
                  done.done == true, done.status == "success", failed.hasError, failed.done == true,
                  cancelled.status == "cancelled", !cancelled.hasError,
                  words.done == false, words.status == "verifying sha256 digest",
                  connected.status == "connected", connected.done == true, !connected.hasError,
                  broken.hasError, broken.status == "error", waiting.done == false else {
                throw SampleMismatch("progress fields")
            }
            let state = DeskModelsProgress(going)
            guard state.phase == .running, state.fraction != nil, abs((state.fraction ?? 0) - 0.2596) < 0.001,
                  DeskModelsProgress(unseen).phase == .notStarted, DeskModelsProgress(done).phase == .done,
                  DeskModelsProgress(failed).phase == .failed, DeskModelsProgress(cancelled).phase == .cancelled,
                  DeskModelsProgress(words).phase == .running else {
                throw SampleMismatch("progress phases")
            }
            guard DeskModelsStage(words) == .working, DeskModelsStage(waiting) == .idle, DeskModelsStage(done) == .idle,
                  DeskModelsStage(connected) == .connected, DeskModelsStage(broken) == .failed else {
                throw SampleMismatch("setup stages")
            }
            return "running, not started, done, failed, cancelled, setup connected and failed"
        },
        DecodeCheck("deskmodels.setup") {
            let pick = try KJSON.decode(DeskModelsRecommendationDTO.self, from: recommendation)
            let status = try KJSON.decode(DeskModelsSetupStatusDTO.self, from: setupStatus)
            let made = try KJSON.decode(DeskModelsRegisteredDTO.self, from: registered)
            guard pick.name == "qwen2.5-0.5b-instruct", pick.params == "0.5B", pick.estimatedDownloadBytes == 400000000,
                  pick.diskFreeBytes == 118000000000, pick.downloaded == false,
                  status.claude?.present == true, status.claude?.signedIn == true,
                  status.codex?.present == false, status.codex?.signedIn == false,
                  status.antigravity?.present == true, status.antigravity?.signedIn == false,
                  status.connections?.local?.items.count == 2, status.connections?.api?.items.count == 1,
                  made.id == "a1b2c3d4e5f6" else {
                throw SampleMismatch("setup fields")
            }
            return "recommendation, sign-in states, 2 local and 1 key connection, register answer"
        },
        DecodeCheck("deskmodels.names") {
            for name in ["llama3.2", "llama3.2:latest", "qwen2.5-0.5b-instruct", "nomic-embed-text", "a_b"] {
                guard DeskModelsWire.pathOK(name) else { throw SampleMismatch("name " + name) }
            }
            for name in ["", ".", "..", "a/b", "a b", "../x", "a?b", "a#b", "hf.co/org/model:q4"] {
                guard !DeskModelsWire.pathOK(name) else { throw SampleMismatch("bad name " + name) }
            }
            guard DeskModelsWire.billions("7B") == 7, DeskModelsWire.billions("3.8B") == 3.8,
                  DeskModelsWire.billions("137M") == 0.137, DeskModelsWire.billions("big") == nil,
                  DeskModelsWire.estimate(params: "7B") == "about 4.4 GB", DeskModelsWire.estimate(params: "0.5B") == "about 500 MB",
                  DeskModelsWire.estimate(params: "huge") == nil else {
                throw SampleMismatch("size estimate")
            }
            return "model names and size estimates"
        },
    ]
}
