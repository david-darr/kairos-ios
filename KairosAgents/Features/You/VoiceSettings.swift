import SwiftUI

// Voice: which voice Kairos speaks with, its quality, pronunciations, listening models,
// the backup and Open Mic voices, realtime on a free Gemini key, and the bot call voice.
// Everything runs on sample data until the desktop connection fills it in.

// MARK: - Sample data

nonisolated enum VoiceEngineChoice: String, CaseIterable, Hashable, Sendable {
    case kairos, gptLive, elevenLabs

    var title: String {
        switch self {
        case .kairos: "Kairos Voice"
        case .gptLive: "GPT-Live"
        case .elevenLabs: "ElevenLabs"
        }
    }

    var detail: String {
        switch self {
        case .kairos: "Free and private. Listening, turn-taking and speaking all run on your desktop."
        case .gptLive: "About 5 cents a minute on your OpenAI key. During calls and Open Mic your voice goes to OpenAI."
        case .elevenLabs: "About 4 cents a minute of speech on your ElevenLabs key. Every spoken sentence goes to ElevenLabs."
        }
    }

    var company: String {
        switch self {
        case .kairos: "Kairos"
        case .gptLive: "OpenAI"
        case .elevenLabs: "ElevenLabs"
        }
    }
}

nonisolated struct VoicePronunciation: Identifiable, Hashable, Sendable {
    let id = UUID()
    var word: String
    var say: String
}

nonisolated struct VoiceRecognitionModel: Identifiable, Hashable, Sendable {
    let id: String
    var label: String
    var size: String
    var about: String
    var downloaded: Bool
    var progress: Double? = nil
}

nonisolated enum VoiceOptionalItem: String, Hashable, Sendable {
    case kokoro, smartTurn
}

// MARK: - Voice

struct VoiceScreen: View {
    private let store = YouStore.shared

    @State private var engine: VoiceEngineChoice = .kairos
    @State private var saving: VoiceEngineChoice? = nil
    @State private var expanded: VoiceEngineChoice? = nil
    @State private var openAIKey = ""
    @State private var openAISaved = false
    @State private var elevenKey = ""
    @State private var elevenSaved = true
    @State private var keyMessage: String? = nil
    @State private var keyError: String? = nil
    @State private var checking = false

    @State private var hd = false
    @State private var hdVoice = "Iris"
    @State private var playing: String? = nil

    @State private var sayings: [VoicePronunciation] = [
        VoicePronunciation(word: "Siobhan", say: "shi-VAWN"),
        VoicePronunciation(word: "Kairos", say: "KY-ross"),
    ]

    @State private var models: [VoiceRecognitionModel] = [
        VoiceRecognitionModel(id: "base.en", label: "Base", size: "142 MB", about: "Quick and light. Good for short notes.", downloaded: true),
        VoiceRecognitionModel(id: "small.en", label: "Small", size: "466 MB", about: "More accurate, a little slower.", downloaded: true),
        VoiceRecognitionModel(id: "medium.en", label: "Medium", size: "1.5 GB", about: "The most accurate. Best on a fast processor.", downloaded: false),
    ]
    @State private var activeModel = "base.en"

    @State private var optionalReady: [VoiceOptionalItem: Bool] = [.kokoro: true, .smartTurn: false]
    @State private var optionalProgress: [VoiceOptionalItem: Double] = [:]

    @State private var backupVoice = "auto"
    @State private var openMicVoice = "same"

    @State private var geminiConnected = false
    @State private var geminiEditing = false
    @State private var geminiKey = ""
    @State private var geminiError: String? = nil
    @State private var geminiChecking = false

    @State private var started = false
    private let startDownloading: Bool

    init(startExpanded: VoiceEngineChoice? = nil, startHD: Bool = false, startDownloading: Bool = false, startGemini: Bool = false) {
        _expanded = State(initialValue: startExpanded)
        _hd = State(initialValue: startHD)
        _geminiEditing = State(initialValue: startGemini)
        self.startDownloading = startDownloading
    }

    private var isAdmin: Bool { store.current.isAdmin }

    var body: some View {
        SettingsPage("Voice", subtitle: "How Kairos sounds, and how it hears you.") {
            SettingsGroup("Voice", footer: "Calls, Open Mic, replies read aloud, voice notes, phone calls and Discord voice all use this. A bot can still have its own voice.") {
                ForEach(VoiceEngineChoice.allCases, id: \.self) { choice in
                    engineRow(choice)
                }
            }
            .arrives(0)

            qualityGroup.arrives(1)
            pronunciationsGroup.arrives(2)
            listeningGroup.arrives(3)

            SettingsGroup("Backup and Open Mic", footer: "The backup voice is the desktop's own voice. Kairos uses it only when no other voice is ready.") {
                PickRow(title: "Backup voice", symbol: "speaker.wave.2", selection: $backupVoice, options: ["auto", "Daniel", "Samantha", "Karen"], label: backupLabel)
                ActionRow(title: "Preview the backup voice", symbol: "play.fill") { store.say("Playing a preview") }
                PickRow(
                    title: "Open Mic voice",
                    detail: "Same as the Voice, unless you pick another for Open Mic only.",
                    symbol: "mic",
                    selection: $openMicVoice,
                    options: ["same", "Iris", "Ryan", "Aiden", "Bella"],
                    label: { $0 == "same" ? "Same as the Voice" : $0 }
                )
            }
            .arrives(4)

            geminiGroup.arrives(5)

            NoteText(text: "On this phone, calls and dictation use the iPhone's own microphone and speaker.", symbol: "iphone")

            SettingsGroup {
                NavRow(title: "Bot call voice", detail: "The live voice each bot uses on a call.", symbol: "phone", to: .botVoice)
            }

            NoteText(text: "Voice servers and the graphics card setup are changed on the desktop.", symbol: "desktopcomputer")
        }
        .animation(Motion.snappy, value: expanded)
        .animation(Motion.snappy, value: engine)
        .animation(Motion.snappy, value: hd)
        .animation(Motion.snappy, value: geminiEditing)
        .onChange(of: backupVoice) { store.say(backupVoice == "auto" ? "Using the best available voice" : "Voice updated") }
        .onChange(of: openMicVoice) { store.say(openMicVoice == "same" ? "Open Mic follows the Voice" : "Open Mic voice updated") }
        .onAppear {
            guard !started else { return }
            started = true
            if startDownloading { download("medium.en") }
        }
    }

    // MARK: Voice choice

    private func engineRow(_ choice: VoiceEngineChoice) -> some View {
        let chosen = engine == choice
        return VStack(alignment: .leading, spacing: 0) {
            Button { pick(choice) } label: {
                HStack(spacing: 12) {
                    Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(chosen ? Palette.goldText : Palette.inkFaint)
                        .contentTransition(.symbolEffect(.replace))
                    RowLabel(title: choice.title, detail: choice.detail)
                    if saving == choice {
                        Text("Saving...")
                            .font(KFont.ui(14, relativeTo: .footnote))
                            .foregroundStyle(Palette.inkFaint)
                    } else if chosen {
                        StatusPill(text: "In use")
                    } else if choice != .kairos {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.inkFaint)
                            .rotationEffect(.degrees(expanded == choice ? 180 : 0))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.985))
            .accessibilityAddTraits(chosen ? .isSelected : [])
            if expanded == choice {
                keyPanel(choice)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func isSaved(_ choice: VoiceEngineChoice) -> Bool {
        switch choice {
        case .kairos: true
        case .gptLive: openAISaved
        case .elevenLabs: elevenSaved
        }
    }

    private func keyBinding(_ choice: VoiceEngineChoice) -> Binding<String> {
        Binding(
            get: { choice == .gptLive ? openAIKey : elevenKey },
            set: { value in if choice == .gptLive { openAIKey = value } else { elevenKey = value } }
        )
    }

    private func keyPanel(_ choice: VoiceEngineChoice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isSaved(choice) ? "Key saved. Paste a new key to replace it." : "Paste your \(choice.company) key. Kairos never shows it again.")
                .font(KFont.ui(13.5, relativeTo: .footnote))
                .foregroundStyle(Palette.inkFaint)
            SecureField(isSaved(choice) ? "Saved" : "Paste the key", text: keyBinding(choice))
                .font(KFont.ui(16))
                .foregroundStyle(Palette.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .frame(height: 46)
                .kCard(radius: 14, raised: true)
            if let keyMessage {
                Text(keyMessage)
                    .font(KFont.ui(14, relativeTo: .footnote))
                    .foregroundStyle(checking ? Palette.inkDim : Palette.success)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let keyError {
                Text(keyError)
                    .font(KFont.ui(14, relativeTo: .footnote))
                    .foregroundStyle(Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if choice == .elevenLabs {
                    PillButton(title: "Check") { check(choice, use: false) }
                }
                PillButton(title: checking ? "Checking..." : (engine == choice ? "Check" : "Check and use"), prominent: true) {
                    check(choice, use: engine != choice)
                }
                if choice == .elevenLabs && elevenSaved {
                    PillButton(title: "Remove key", danger: true) { removeElevenKey() }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    private func pick(_ choice: VoiceEngineChoice) {
        Haptics.select()
        keyError = nil
        keyMessage = nil
        if choice == .kairos {
            expanded = nil
            guard engine != .kairos else { return }
            use(.kairos)
            return
        }
        withAnimation(Motion.snappy) { expanded = expanded == choice ? nil : choice }
    }

    private func use(_ choice: VoiceEngineChoice) {
        saving = choice
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(Motion.snappy) {
                saving = nil
                engine = choice
                expanded = nil
                keyMessage = nil
            }
            Haptics.success()
            store.say("\(choice.title) is your voice now.")
        }
    }

    private func check(_ choice: VoiceEngineChoice, use useIt: Bool) {
        guard !checking else { return }
        let typed = (choice == .gptLive ? openAIKey : elevenKey).trimmingCharacters(in: .whitespaces)
        keyError = nil
        if typed.isEmpty && !isSaved(choice) {
            keyError = "Paste the key first."
            Haptics.thud()
            return
        }
        if !typed.isEmpty && typed.count < 12 {
            keyError = "\(choice.company) did not accept that key. Check it and try again."
            Haptics.thud()
            return
        }
        checking = true
        keyMessage = "Asking \(choice.company) whether the key works..."
        Task {
            try? await Task.sleep(for: .milliseconds(1000))
            checking = false
            if choice == .gptLive { openAISaved = true; openAIKey = "" } else { elevenSaved = true; elevenKey = "" }
            if useIt {
                keyMessage = nil
                use(choice)
            } else if choice == .elevenLabs {
                keyMessage = "The key works. 32 voices on the account. About 41,000 characters are left this month."
            } else {
                keyMessage = "The key works."
            }
        }
    }

    private func removeElevenKey() {
        elevenSaved = false
        elevenKey = ""
        keyMessage = nil
        if engine == .elevenLabs {
            withAnimation(Motion.snappy) { engine = .kairos }
            store.say("Key removed. Kairos Voice speaks now.")
        } else {
            store.say("Key removed.")
        }
    }

    // MARK: Quality

    private var qualityGroup: some View {
        SettingsGroup("Voice quality", footer: "For Kairos Voice. HD voice is downloaded on the desktop and needs an NVIDIA graphics card.") {
            qualityRow(hd: false, title: "Standard", detail: "Works on any computer.")
            qualityRow(hd: true, title: "HD", detail: "Clearer, on the desktop's NVIDIA card. Installed.")
            optionalRow(.kokoro, title: "Standard voice (Kokoro)", detail: "One download, then it runs on the desktop.", size: "330 MB")
            if hd {
                ForEach(["Iris", "Ryan", "Aiden"], id: \.self) { name in
                    hdVoiceRow(name)
                }
            }
        }
    }

    private func qualityRow(hd isHD: Bool, title: String, detail: String) -> some View {
        let chosen = hd == isHD
        return Button {
            Haptics.select()
            if !isHD && optionalReady[.kokoro] != true {
                store.say("Download the Standard voice first")
                return
            }
            withAnimation(Motion.snappy) { hd = isHD }
            store.say(isHD ? "HD voice is on" : "Standard voice is on")
        } label: {
            HStack(spacing: 12) {
                Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(chosen ? Palette.goldText : Palette.inkFaint)
                    .contentTransition(.symbolEffect(.replace))
                RowLabel(title: title, detail: detail)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.985))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func hdVoiceRow(_ name: String) -> some View {
        let chosen = hdVoice == name
        let isPlaying = playing == name
        return HStack(spacing: 8) {
            Button {
                Haptics.select()
                withAnimation(Motion.snappy) { hdVoice = name }
                store.say("\(name) speaks now")
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(chosen ? Palette.goldText : Palette.inkFaint)
                    Text(name)
                        .font(KFont.ui(16))
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 30)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.985))
            .accessibilityAddTraits(chosen ? .isSelected : [])
            Button { play(name) } label: {
                Image(systemName: isPlaying ? "waveform" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.goldText)
                    .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
                    .background(Palette.ink.opacity(0.08), in: Circle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(isPlaying ? "Playing a sample of \(name)" : "Play a sample of \(name)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private func play(_ name: String) {
        Haptics.tap()
        withAnimation(Motion.snappy) { playing = name }
        store.say("Playing a sample of \(name)")
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            if playing == name { withAnimation(Motion.snappy) { playing = nil } }
        }
    }

    // MARK: Pronunciations

    private var pronunciationsGroup: some View {
        SettingsGroup("Pronunciations", footer: "Words Kairos Voice says wrong, like a name. Write how to say it with hyphens between syllables and the stressed one in capitals, like shi-VAWN for Siobhan. HD voice uses these spellings too.") {
            if sayings.isEmpty {
                EmptyRow(text: "No words yet.")
            }
            ForEach(sayings) { item in
                HStack(spacing: 8) {
                    TextField("Word", text: sayingBinding(item.id, \.word))
                        .font(KFont.ui(16))
                        .foregroundStyle(Palette.ink)
                        .autocorrectionDisabled()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.inkFaint)
                        .accessibilityHidden(true)
                    TextField("How to say it", text: sayingBinding(item.id, \.say))
                        .font(KFont.ui(16))
                        .foregroundStyle(Palette.goldText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        Haptics.tap()
                        withAnimation(Motion.snappy) { sayings.removeAll { $0.id == item.id } }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Palette.danger)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel(item.word.isEmpty ? "Remove this word" : "Remove \(item.word)")
                }
                .padding(.leading, 16)
                .padding(.trailing, 6)
                .frame(minHeight: 52)
            }
            ActionRow(title: "Add a word", symbol: "plus") {
                withAnimation(Motion.snappy) { sayings.append(VoicePronunciation(word: "", say: "")) }
            }
            ActionRow(title: "Save pronunciations", symbol: "checkmark", tone: .gold) { savePronunciations() }
        }
    }

    private func sayingBinding(_ id: UUID, _ path: WritableKeyPath<VoicePronunciation, String>) -> Binding<String> {
        Binding(
            get: { sayings.first { $0.id == id }?[keyPath: path] ?? "" },
            set: { value in
                if let index = sayings.firstIndex(where: { $0.id == id }) { sayings[index][keyPath: path] = value }
            }
        )
    }

    private func savePronunciations() {
        let half = sayings.contains { $0.word.isEmpty != $0.say.isEmpty }
        if half {
            store.say("Fill in both sides of each word")
            Haptics.thud()
            return
        }
        withAnimation(Motion.snappy) { sayings.removeAll { $0.word.isEmpty && $0.say.isEmpty } }
        Haptics.success()
        store.say("Saved. Kairos Voice says these words this way now.")
    }

    // MARK: Listening

    private var listeningGroup: some View {
        let active = models.first { $0.id == activeModel }?.label ?? activeModel
        return SettingsGroup("Listening", footer: "How Kairos hears you, on the desktop. Using the \(active) model. Larger models are more accurate and slower, and recognition runs on the processor.") {
            ForEach(models) { model in
                recognitionRow(model)
            }
            optionalRow(.smartTurn, title: "Know when you have finished (Smart Turn)", detail: "Answers sooner without cutting you off mid-sentence. Runs on the processor in about 12 ms.", size: "8 MB")
        }
    }

    private func recognitionRow(_ model: VoiceRecognitionModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                RowLabel(title: "\(model.label) · \(model.size)", detail: model.about, symbol: "waveform")
                if model.id == activeModel {
                    StatusPill(text: "In use")
                } else if model.downloaded {
                    StatusPill(text: "Downloaded", tone: .muted)
                } else if let progress = model.progress {
                    progressText(progress)
                } else if isAdmin {
                    PillButton(title: "Download", symbol: "square.and.arrow.down") { download(model.id) }
                } else {
                    Text("An admin can download this.")
                        .font(KFont.ui(13.5, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                        .multilineTextAlignment(.trailing)
                }
            }
            if let progress = model.progress {
                ProgressView(value: progress)
                    .tint(Palette.gold)
                    .padding(.leading, 38)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 52)
    }

    private func progressText(_ progress: Double) -> some View {
        Text(progress <= 0 ? "Starting..." : "\(Int(progress * 100))%")
            .font(KFont.ui(15, .medium))
            .foregroundStyle(Palette.goldText)
            .monospacedDigit()
            .contentTransition(.numericText())
    }

    private func setProgress(_ id: String, _ value: Double?) {
        guard let index = models.firstIndex(where: { $0.id == id }) else { return }
        models[index].progress = value
    }

    private func download(_ id: String) {
        guard let model = models.first(where: { $0.id == id }), model.progress == nil else { return }
        Haptics.tap()
        withAnimation(Motion.snappy) { setProgress(id, 0) }
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            var done = 0.0
            while done < 1 {
                try? await Task.sleep(for: .milliseconds(700))
                done = min(1, done + Double.random(in: 0.1...0.22))
                withAnimation(Motion.gentle) { setProgress(id, done) }
            }
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(Motion.snappy) {
                if let index = models.firstIndex(where: { $0.id == id }) {
                    models[index].progress = nil
                    models[index].downloaded = true
                }
            }
            Haptics.success()
            store.say("\(model.label) speech model ready")
        }
    }

    // MARK: Optional downloads (Kokoro, Smart Turn)

    private func optionalRow(_ item: VoiceOptionalItem, title: String, detail: String, size: String) -> some View {
        let ready = optionalReady[item] == true
        let progress = optionalProgress[item]
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                RowLabel(title: title, detail: detail, symbol: item == .kokoro ? "speaker.wave.2" : "clock")
                if ready {
                    StatusPill(text: "Ready")
                } else if let progress {
                    progressText(progress)
                } else if !isAdmin {
                    Text("An admin can download this.")
                        .font(KFont.ui(13.5, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                        .multilineTextAlignment(.trailing)
                }
            }
            if let progress {
                ProgressView(value: progress)
                    .tint(Palette.gold)
                    .padding(.leading, 38)
            } else if isAdmin {
                HStack(spacing: 8) {
                    if ready {
                        PillButton(title: "Remove", danger: true) { removeOptional(item, title: title) }
                    } else {
                        PillButton(title: "Download · \(size)", symbol: "square.and.arrow.down") { downloadOptional(item, title: title) }
                    }
                }
                .padding(.leading, 38)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func downloadOptional(_ item: VoiceOptionalItem, title: String) {
        guard optionalProgress[item] == nil else { return }
        Haptics.tap()
        withAnimation(Motion.snappy) { optionalProgress[item] = 0 }
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            var done = 0.0
            while done < 1 {
                try? await Task.sleep(for: .milliseconds(700))
                done = min(1, done + Double.random(in: 0.15...0.3))
                withAnimation(Motion.gentle) { optionalProgress[item] = done }
            }
            withAnimation(Motion.snappy) {
                optionalProgress[item] = nil
                optionalReady[item] = true
            }
            Haptics.success()
            store.say("\(title) downloaded")
        }
    }

    private func removeOptional(_ item: VoiceOptionalItem, title: String) {
        withAnimation(Motion.snappy) {
            optionalReady[item] = false
            if item == .kokoro { hd = true }
        }
        store.say(item == .kokoro ? "Standard voice removed. HD voice speaks now." : "\(title) removed")
    }

    // MARK: Backup voice

    private func backupLabel(_ option: String) -> String {
        switch option {
        case "auto": "Automatic (Daniel)"
        case "Daniel": "Daniel · en-GB"
        case "Samantha": "Samantha · en-US"
        case "Karen": "Karen · en-AU"
        default: option
        }
    }

    // MARK: Gemini

    private var geminiGroup: some View {
        SettingsGroup("Realtime on a free Gemini key", footer: "The quickest, most natural way to talk with a bot. Realtime calls send your audio to Google; dictation stays on the desktop.") {
            StatusRow(
                title: "Gemini free key",
                detail: geminiConnected ? "Realtime voice can use Gemini at no cost." : "Not set up yet.",
                symbol: "sparkles",
                status: geminiConnected ? "Connected" : "Not set up",
                tone: geminiConnected ? .ok : .muted
            )
            if geminiEditing {
                VStack(alignment: .leading, spacing: 10) {
                    SecureField("Paste your Gemini API key", text: $geminiKey)
                        .font(KFont.ui(16))
                        .foregroundStyle(Palette.ink)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 14)
                        .frame(height: 46)
                        .kCard(radius: 14, raised: true)
                    if let geminiError {
                        Text(geminiError)
                            .font(KFont.ui(14, relativeTo: .footnote))
                            .foregroundStyle(Palette.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 8) {
                        PillButton(title: geminiChecking ? "Checking..." : "Check and connect", prominent: true) { connectGemini() }
                        PillButton(title: "Cancel") {
                            withAnimation(Motion.snappy) {
                                geminiEditing = false
                                geminiKey = ""
                                geminiError = nil
                            }
                        }
                    }
                }
                .padding(16)
                .transition(.opacity)
            } else {
                ActionRow(title: geminiConnected ? "Replace the key" : "Set up", symbol: "key") {
                    withAnimation(Motion.snappy) { geminiEditing = true }
                }
            }
        }
    }

    private func connectGemini() {
        guard !geminiChecking else { return }
        let typed = geminiKey.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { geminiError = "Paste your Gemini API key first."; Haptics.thud(); return }
        guard typed.count >= 12 else { geminiError = "Google did not accept that key. Check it and try again."; Haptics.thud(); return }
        geminiError = nil
        geminiChecking = true
        Task {
            try? await Task.sleep(for: .milliseconds(1000))
            geminiChecking = false
            withAnimation(Motion.snappy) {
                geminiConnected = true
                geminiEditing = false
                geminiKey = ""
            }
            Haptics.success()
            store.say("Connected. Realtime voice can now use Gemini on your free key.")
        }
    }
}

// MARK: - Bot call voice

nonisolated struct BotVoiceSetting: Hashable, Sendable {
    var voice = "marin"
    var readTyped = true
    var idleMinutes = 10
}

/// The live voice a bot uses on a call, whether it reads typed replies, and when an idle call ends.
struct BotVoiceScreen: View {
    private let store = YouStore.shared
    private let voices = ["marin", "cedar", "coral", "sage", "ash"]
    @State private var botID = "kip"
    @State private var settings: [String: BotVoiceSetting] = [
        "scout": BotVoiceSetting(voice: "cedar", readTyped: false, idleMinutes: 5),
        "quill": BotVoiceSetting(voice: "coral", readTyped: true, idleMinutes: 15),
    ]
    @State private var playing: String? = nil

    private var bots: [Bot] { SampleData.allBots.filter { $0.members.isEmpty } }

    var body: some View {
        SettingsPage("Bot call voice", subtitle: "How a bot sounds on a live call.") {
            SettingsGroup {
                PickRow(
                    title: "Bot",
                    symbol: "person.crop.circle",
                    selection: $botID,
                    options: bots.map(\.id),
                    label: { SampleData.bot($0).name }
                )
            }
            .arrives(0)

            SettingsGroup("Live voice", footer: "Voice changes apply to your next call.") {
                ForEach(voices, id: \.self) { voice in
                    voiceRow(voice)
                }
            }
            .arrives(1)

            SettingsGroup("During a call") {
                ToggleRow(title: "Read typed replies", detail: "Speak the replies to messages you type during a call.", isOn: binding(\.readTyped))
                StepperRow(title: "End an idle call after", detail: "Minutes with nobody talking.", value: binding(\.idleMinutes), range: 1...60, unit: "min")
            }
            .arrives(2)

            GoldButton(title: "Save") {
                Haptics.success()
                store.say("Saved. Voice changes apply to your next call.")
            }
            .arrives(3)
        }
        .animation(Motion.snappy, value: botID)
    }

    private var current: BotVoiceSetting { settings[botID] ?? BotVoiceSetting() }

    private func binding<Value>(_ path: WritableKeyPath<BotVoiceSetting, Value>) -> Binding<Value> {
        Binding(
            get: { (settings[botID] ?? BotVoiceSetting())[keyPath: path] },
            set: { value in
                var setting = settings[botID] ?? BotVoiceSetting()
                setting[keyPath: path] = value
                settings[botID] = setting
            }
        )
    }

    private func voiceRow(_ voice: String) -> some View {
        let chosen = current.voice == voice
        let isPlaying = playing == voice
        return HStack(spacing: 8) {
            Button {
                Haptics.select()
                withAnimation(Motion.snappy) { binding(\.voice).wrappedValue = voice }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(chosen ? Palette.goldText : Palette.inkFaint)
                        .contentTransition(.symbolEffect(.replace))
                    Text(voice.capitalized)
                        .font(KFont.ui(16))
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.985))
            .accessibilityAddTraits(chosen ? .isSelected : [])
            Button {
                Haptics.tap()
                withAnimation(Motion.snappy) { playing = voice }
                store.say("Playing a sample of \(voice.capitalized)")
                Task {
                    try? await Task.sleep(for: .seconds(2.4))
                    if playing == voice { withAnimation(Motion.snappy) { playing = nil } }
                }
            } label: {
                Image(systemName: isPlaying ? "waveform" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.goldText)
                    .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
                    .background(Palette.ink.opacity(0.08), in: Circle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Play a sample of \(voice.capitalized)")
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Debug pictures

enum VoiceDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        case "voice": return AnyView(VoiceScreen())
        case "voice-gptlive": return AnyView(VoiceScreen(startExpanded: .gptLive))
        case "voice-elevenlabs": return AnyView(VoiceScreen(startExpanded: .elevenLabs))
        case "voice-hd": return AnyView(VoiceScreen(startHD: true))
        case "voice-downloading": return AnyView(VoiceScreen(startDownloading: true))
        case "voice-gemini": return AnyView(VoiceScreen(startGemini: true))
        case "voice-bot": return AnyView(BotVoiceScreen())
        default: return nil
        }
    }
}
