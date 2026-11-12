import Foundation

// The desktop's bot routes, as the phone reads them: one decoder per answer and one function per route.
// Every shape here was read from the desktop source (the Python file and function are named on each type).
//
// Rules these decoders follow:
// - Keys arrive in snake_case and land in camelCase properties (the shared decoder converts them).
//   The same conversion reaches the keys inside every `JSONValue` object and every `[String: X]`
//   dictionary, so look those up in camelCase too ("fd_data" holds "whenLabel", not "when_label").
// - Times are epoch seconds (Double). Nothing on these routes sends ISO text.
// - Every field is optional except an id the desktop always sends.
// - Ids go into paths as they are. They are made by the desktop (hex, or "item:<hex>" for inbox rows).

// MARK: - Looks

/// Helpers for a bot's saved look (desktop `static/js/mascot.js`, `services/agent_service.py`).
nonisolated enum BotAvatarRules {
    /// The six body colours a desktop bot can have, in the desktop's order (agent_service.COLORS).
    static let colors: [UInt32] = [0xD9B260, 0xB9D2E3, 0xE8C39E, 0xD99A92, 0xB5C7A5, 0xCDBFD9]
    /// The three shapes the desktop can store (agent_service.AJAR_SHAPES).
    static let shapes: [MascotShape] = [.round, .squircle, .tall]

    /// "#D9B260" or "d9b260" as a number. nil when the text is not six hex digits.
    static func hex(_ text: String?) -> UInt32? {
        guard let text else { return nil }
        let digits = text.hasPrefix("#") ? String(text.dropFirst()) : text
        guard digits.count == 6 else { return nil }
        return UInt32(digits, radix: 16)
    }

    /// The desktop's id hash (mascot.js hashId, FNV-1a), which picks a look for a bot saved without one.
    static func seed(_ id: String) -> UInt32 {
        var hash: UInt32 = 2166136261
        for unit in (id.isEmpty ? "agent" : id).utf16 {
            hash = (hash ^ UInt32(unit)) &* 16777619
        }
        return hash
    }

    static func defaultShape(_ id: String) -> MascotShape { shapes[Int(seed(id) % 3)] }
    static func defaultColor(_ id: String) -> UInt32 { colors[Int(seed(id) % 6)] }
}

/// A bot's saved look: `avatar` on an agent record (agent_service.py: _validate_ajar, ajar_from_legacy).
/// Always `{version: 3, character: "ajar", shape, color, acc, finish}` once the desktop has loaded it.
nonisolated struct AgentAvatarDTO: Decodable, Hashable, Sendable {
    var version: Double?
    var character: String?
    /// "round", "squircle" or "tall".
    var shape: String?
    /// One of the six pastels as "#RRGGBB", upper case.
    var color: String?
    /// "none", "laurel", "spectacles", "quill", "rays" or "scarf".
    var acc: String?
    /// "flat" or "halftone". The phone draws every bot the same way and ignores it.
    var finish: String?
}

/// A bot's own picture, when it has one: `avatar_image` (bot_avatar_service.py: framing).
/// The image is at GET /api/agents/{agent_id}/avatar-image/{asset_id}.
nonisolated struct AgentAvatarImageDTO: Decodable, Hashable, Sendable {
    var assetId: String?
    var shape: String?
    var zoom: Double?
    var focusX: Double?
    var focusY: Double?
}

/// One folder of a bot's conversations: `folders[]` on an agent record (bot_threads.py: add_folder).
nonisolated struct AgentFolderDTO: Decodable, Hashable, Sendable {
    var id: String
    var name: String?
    var emoji: String?
    var order: Double?
}

/// What a bot is doing right now: `activity` on a roster row
/// (agent_routes.py: _summary; chat_live.py: agent_activity). null when it is doing nothing.
nonisolated struct AgentActivityDTO: Decodable, Hashable, Sendable {
    /// "task" (a card or routine is running) or "chat" (a conversation turn is running).
    var kind: String?
    var working: Bool?
    /// A turn is paused on the person's answer.
    var waiting: Bool?
    /// The task's name, or the conversation's title.
    var name: String?
    /// The start of the prompt, up to 240 characters.
    var detail: String?
    /// How many conversations are running. Only on a "chat" activity.
    var count: Int?
}

// MARK: - Roster

/// One bot: a row of GET /api/agents, the body of PATCH /api/agents/{id}, and `agent` in one bot's detail
/// (agent_routes.py: _summary over the stored record of agent_service.py: create and bot_record.py: new_defaults).
nonisolated struct AgentDTO: Decodable, Hashable, Sendable {
    var id: String
    var name: String?
    var role: String?
    var blurb: String?
    var soul: String?
    var instructions: String?
    var revision: Int?
    /// The model connection this bot uses. null means the first Claude connection.
    var endpointId: String?
    var modelOverride: String?
    var modelEffort: String?
    /// The body colour as "#rrggbb", lower case. The same colour as `avatar.color`.
    var color: String?
    var enabled: Bool?
    var dailyRunCap: Int?
    var deliverToChannel: String?
    var integrationIds: [String]?
    var keepSignedIn: Bool?
    var memoryUpkeep: Bool?
    var peers: JSONValue?
    var createdAt: Double?
    var avatar: AgentAvatarDTO?
    var avatarImage: AgentAvatarImageDTO?
    var mascotExpression: String?
    /// The name of the team (department) this bot sits in, or null.
    var section: String?
    var origin: JSONValue?
    /// An archived bot. The roster still lists it; leave it out of the main list.
    var hidden: Bool?
    var hiddenAt: Double?
    /// A set place in the roster. Kip has -1. null sorts after every set place, by `createdAt`.
    var order: Double?
    var folders: [AgentFolderDTO]?
    /// How many of its conversations may run at once (default 3).
    var threadLimit: Int?
    /// "ask", "edits", "auto", "full" or "custom".
    var approvalMode: String?
    var outbound: JSONValue?
    var fallback: JSONValue?
    var cacheKeepWarm: String?
    var place: String?
    var toolScope: JSONValue?
    var connectorScopes: JSONValue?
    var alwaysAllow: JSONValue?
    /// "front_desk" on Kip, null on every other bot.
    var builtin: String?
    var replyStyle: String?
    var notifications: Bool?
    var speakReplies: Bool?
    var voiceId: String?
    var callMode: String?
    var skillSelection: JSONValue?
    var browserEnabled: Bool?
    var browserProfile: String?
    /// "off", "needs_you", "working", "capped" or "idle".
    var status: String?
    /// The running work's name, or why it cannot run ("Scout reached its 12 runs for today").
    var statusDetail: String?
    var activity: AgentActivityDTO?
    /// How many things wait on the person: open inbox items, results to review, and a paused turn.
    var needsYou: Int?
    var runsToday: Int?

    /// Kip, the front desk. It is drawn as Kairos's own ink Kip, whatever look is stored.
    var isFrontDesk: Bool { builtin == "front_desk" }

    /// The body colour for `Bot.colorHex`.
    var bodyColorHex: UInt32 {
        if isFrontDesk { return 0xF2E8D8 }
        return BotAvatarRules.hex(avatar?.color) ?? BotAvatarRules.hex(color) ?? BotAvatarRules.defaultColor(id)
    }

    /// Kip is always the round ink Kip (`Design/Mascot.swift`), whatever look the desktop stored or seeded for it.
    var mascotShape: MascotShape {
        if isFrontDesk { return .round }
        return MascotShape(rawValue: avatar?.shape ?? "") ?? BotAvatarRules.defaultShape(id)
    }

    var mascotAccessory: MascotAccessory {
        if isFrontDesk { return .none }
        return MascotAccessory(rawValue: avatar?.acc ?? "") ?? MascotAccessory.none
    }

    /// The roster status as the phone's four states, by the desktop's own order
    /// (static/js/botStatus.js: off first, then waiting on the person, then working).
    var botStatus: BotStatus {
        if enabled == false || status == "off" { return .offline }
        if status == "needs_you" || (needsYou ?? 0) > 0 { return .needsYou }
        if status == "working" { return .working }
        return .online
    }
}

/// An item in a bot's old inbox (agent_service.py: add_item). Used inside AgentDetailDTO.
nonisolated struct AgentInboxItemDTO: Decodable, Hashable, Sendable {
    var id: String
    var agentId: String?
    /// "report" or "question".
    var kind: String?
    var createdAt: Double?
    /// "open" until it is answered or dismissed.
    var status: String?
    var title: String?
    var body: String?
    var cardId: String?
    var taskId: String?
    var answer: JSONValue?
    var teamId: String?
}

/// GET /api/agents/{agent_id} (agent_routes.py: get_agent).
nonisolated struct AgentDetailDTO: Decodable, Hashable, Sendable {
    var agent: AgentDTO?
    var soulFile: JSONValue?
    var memory: String?
    var memoryUpkeepJournal: JSONValue?
    var setupReceipts: JSONValue?
    /// The bot's routines (scheduled tasks).
    var goals: [JSONValue]?
    /// The bot's one-off work cards.
    var cards: [JSONValue]?
    var inbox: [AgentInboxItemDTO]?
    var answered: [AgentInboxItemDTO]?
    var runs: [JSONValue]?
    var teams: [JSONValue]?
    var triggers: [JSONValue]?
    var avatarSnapshot: String?
}

/// One bot's row in GET /api/agents/conversations (core/agent_conversations.py: agent_threads).
nonisolated struct AgentConversationDTO: Decodable, Hashable, Sendable {
    /// The bot's id.
    var id: String
    /// The bot's most recently updated conversation, or null when it has none.
    var sessionId: String?
    var preview: String?
    /// "user" or "assistant".
    var lastRole: String?
    var at: Double?
    var messageCount: Int?
    /// The person pinned this bot.
    var pinned: Bool?
    /// How many replies are unread (at least 1 when the person marked it unread).
    var unread: Int?
}

/// GET /api/agents/conversations (agent_routes.py: conversations).
nonisolated struct AgentConversationsDTO: Decodable, Hashable, Sendable {
    var agents: [AgentConversationDTO]?
    /// The raw saved choices, keyed "agent:<bot id>" or "team:<team id>".
    var preferences: JSONValue?
}

/// POST /api/agents/conversations/{kind}/{ident} (core/agent_conversations.py: change): the saved choice.
nonisolated struct AgentConversationPrefDTO: Decodable, Hashable, Sendable {
    var pinned: Bool?
    var unread: Bool?
    var readCount: Int?
    var sessionId: String?
}

// MARK: - Teams

/// A team in the desktop's sense: a named group of bots (services/bot_departments.py: _new).
/// Its members are the bots whose `section` is this name.
nonisolated struct BotDepartmentDTO: Decodable, Hashable, Sendable {
    var id: String
    var name: String?
    var order: Double?
    var chiefBotId: String?
    var alsoManages: JSONValue?
    var createdAt: Double?
    var revision: Int?
    var ownerUser: String?
}

/// One bot in GET /api/bot-team/map `members` (bot_team_routes.py: team_map).
nonisolated struct BotTeamMemberDTO: Decodable, Hashable, Sendable {
    var id: String
    var name: String?
    var role: String?
    var section: String?
    var avatar: AgentAvatarDTO?
    var endpointId: String?
    var modelOverride: String?
    var modelEffort: String?
    var departmentId: String?
    var chief: Bool?
    /// "working", "available" or "unavailable".
    var status: String?
}

/// One bot's seat in a room (services/bot_rooms.py: member_views).
nonisolated struct BotRoomMemberDTO: Decodable, Hashable, Sendable {
    var botId: String?
    var name: String?
    var held: Bool?
    var working: Bool?
    var waiting: Bool?
    var seatSessionId: String?
    var lastSeenSeq: Double?
}

/// One thread of a room (services/bot_rooms.py: public).
nonisolated struct BotRoomThreadDTO: Decodable, Hashable, Sendable {
    var id: String
    var title: String?
    var goal: JSONValue?
}

/// A room: one conversation with several bots (services/bot_rooms.py: public).
nonisolated struct BotRoomDTO: Decodable, Hashable, Sendable {
    var id: String
    var name: String?
    var context: String?
    var description: String?
    var bulletin: String?
    var cwd: String?
    var defaultResponder: JSONValue?
    var turnTimeoutMinutes: Double?
    var setupState: String?
    var pinnedMessageId: String?
    var revision: Int?
    var createdAt: Double?
    var archivedAt: Double?
    var members: [BotRoomMemberDTO]?
    var working: Bool?
    /// How many room messages are unread.
    var unread: Int?
    var lastSeq: Double?
    var threads: [BotRoomThreadDTO]?
}

/// GET /api/bot-rooms (bot_room_routes.py: list_rooms).
nonisolated struct BotRoomListDTO: Decodable, Hashable, Sendable {
    var rooms: [BotRoomDTO]?
}

/// GET /api/bot-team/map (bot_team_routes.py: team_map). `members` and `bots` are the same list.
nonisolated struct BotTeamMapDTO: Decodable, Hashable, Sendable {
    var departments: [BotDepartmentDTO]?
    var members: [BotTeamMemberDTO]?
    var bots: [BotTeamMemberDTO]?
    var rooms: [BotRoomDTO]?
    var handoffs: [JSONValue]?
}

// MARK: - Pulse

/// `versions` in the pulse: a short hash of each list, or null for a list the desktop could not read.
nonisolated struct BotPulseVersionsDTO: Decodable, Hashable, Sendable {
    var agents: String?
    var conversations: String?
    var team: String?
    var automations: String?
}

/// GET /api/bot-pulse (bot_pulse_routes.py: pulse). A list is present only when its version differs
/// from the one sent in the query, so a missing list means "unchanged, keep what you hold".
nonisolated struct BotPulseDTO: Decodable, Hashable, Sendable {
    var versions: BotPulseVersionsDTO?
    /// The exact body of GET /api/agents.
    var agents: [AgentDTO]?
    /// The exact body of GET /api/agents/conversations.
    var conversations: AgentConversationsDTO?
    /// The exact body of GET /api/bot-team/map.
    var team: BotTeamMapDTO?
    /// The exact body of GET /api/bot-automations.
    var automations: JSONValue?
    /// How many inbox rows need the person. Left out when `only` was sent.
    var needsYou: Int?
}

// MARK: - A bot's conversations

/// What a conversation adds to its session: `thread` (bot_threads.py: thread_view, THREAD_DEFAULTS).
nonisolated struct BotThreadMetaDTO: Decodable, Hashable, Sendable {
    /// The bot's main conversation: the one to open when none is named.
    var main: Bool?
    var folderId: String?
    var pinned: Bool?
    var archivedAt: Double?
    /// 0 means "until something new happens"; a time means "until then"; null means not snoozed.
    var snoozedUntil: Double?
    var approvalMode: String?
    var place: String?
    /// A reply arrived that the person has not read.
    var unread: Bool?
    var lastReadIndex: Double?
    var pinnedMessageIndex: Double?
    /// "person", "bot", "routine", "room", "handoff" or "task".
    var openedBy: String?
    var routineRunId: String?
    var titleSource: String?
    var activeLeafId: String?
    var lastReadMessageId: String?
    var pinnedMessageId: String?
    var branchRevision: Int?
    var queueRevision: Int?
    var queuePaused: Bool?
    var link: String?
}

/// One conversation row (bot_threads.py: _row). Also what creating and changing a conversation answer.
nonisolated struct BotThreadDTO: Decodable, Hashable, Sendable {
    /// The session id: the id every /api/bot-chat route takes.
    var id: String
    var title: String?
    var createdAt: Double?
    var updatedAt: Double?
    var messageCount: Int?
    var modelEndpointId: String?
    var modelOverride: String?
    var modelEffort: String?
    var followsBotModel: Bool?
    var thread: BotThreadMetaDTO?
    /// "working" while a turn runs, else "idle".
    var status: String?
    /// The last thing said, on one line, up to 240 characters.
    var preview: String?
}

/// GET /api/agents/{agent_id}/threads (bot_threads.py: list_threads).
nonisolated struct BotThreadListDTO: Decodable, Hashable, Sendable {
    var mainId: String?
    var threads: [BotThreadDTO]?
}

// MARK: - Conversation state

/// The newest turn of a conversation: `turn` in the state (chat_live.py: current_turn).
/// It stays for about five minutes after it ends, so check `status` before calling it running.
nonisolated struct BotTurnDTO: Decodable, Hashable, Sendable {
    var id: String?
    var turnId: String?
    /// "processing", "done", "failed" or "stopped".
    var status: String?
    var stopping: Bool?
    var startedAt: Double?
    /// A permission or question is waiting on the person.
    var permission: Bool?
}

/// `context` in the state (bot_chat_service.py: _context_view).
nonisolated struct BotContextDTO: Decodable, Hashable, Sendable {
    var percent: Double?
    var auto: Bool?
}

/// One waiting message (bot_chat_service.py: _queue_item).
nonisolated struct BotQueueItemDTO: Decodable, Hashable, Sendable {
    var id: String
    /// "pending" (waiting its turn) or "interrupted" (needs Resume). A returned draft says "cancelled".
    var state: String?
    var sendId: String?
    var text: String?
    var attachmentIds: [String]?
    var replyToId: String?
    var citations: [JSONValue]?
    var mode: String?
    var createdAt: Double?
    var resumesMessage: Bool?
}

/// GET /api/bot-chat/{session_id}/queue, and `queue` in the state (bot_chat_service.py: queue_view).
nonisolated struct BotQueueDTO: Decodable, Hashable, Sendable {
    var items: [BotQueueItemDTO]?
    var revision: Int?
    var paused: Bool?
    var consumedQueueIds: [String]?
}

/// A "work until done" run: `goal` in the state and in a bot_goal packet (bot_goal_runs.py: public).
nonisolated struct BotGoalDTO: Decodable, Hashable, Sendable {
    var rootId: String?
    /// "working", "completed", "needs-input", "blocked", "stopped", "failed" or "limit-reached".
    var status: String?
    var label: String?
    var goal: String?
    var turn: Int?
    var maxTurns: Int?
    var detail: String?
    var tail: String?
    var startedAt: Double?
    var updatedAt: Double?
    var turnId: String?
}

/// `model` in the state (bot_chat_service.py: state).
nonisolated struct BotModelDTO: Decodable, Hashable, Sendable {
    /// The line to show, for example "Claude Sonnet".
    var label: String?
    var endpointId: String?
    var name: String?
    var kind: String?
    var model: String?
    var effort: String?
}

/// `capabilities` in the state (bot_chat_service.py: state).
nonisolated struct BotCapabilitiesDTO: Decodable, Hashable, Sendable {
    var queue: Bool?
    /// The text "interrupt": sending a waiting message now stops the reply first.
    var steer: JSONValue?
    var edit: Bool?
    var regenerate: Bool?
    var images: Bool?
    var compact: Bool?
    var threadLimit: Int?
    var steerHint: String?
}

/// GET /api/bot-chat/{session_id}/state (bot_chat_service.py: state).
nonisolated struct BotChatStateDTO: Decodable, Hashable, Sendable {
    var sessionId: String?
    var botId: String?
    /// The newest message of the version on screen. Send it back as `expected_leaf_id`.
    var activeLeafId: String?
    var branchRevision: Int?
    var turn: BotTurnDTO?
    var context: BotContextDTO?
    var queue: BotQueueDTO?
    var goal: BotGoalDTO?
    var model: BotModelDTO?
    var capabilities: BotCapabilitiesDTO?
    var pinnedMessageId: String?
    var lastReadMessageId: String?

    /// The id of the turn that is running now, or nil.
    var runningTurnId: String? {
        guard let turn, (turn.status ?? "processing") == "processing" else { return nil }
        return turn.id ?? turn.turnId
    }
}

// MARK: - Messages

/// One reaction on a message (bot_chat_service.py: reaction_list).
nonisolated struct BotReactionDTO: Decodable, Hashable, Sendable {
    /// "thumbs_up", "thumbs_down", "heart", "laugh", "tada" or "eyes".
    var emoji: String?
    var count: Int?
    var mine: Bool?
}

/// Which version of an edited question or a redone answer this is (bot_chat_service.py: client_message).
nonisolated struct BotMessageVersionDTO: Decodable, Hashable, Sendable {
    /// Counts from 0.
    var index: Int?
    var count: Int?
    /// Every version's message id, oldest first.
    var ids: [String]?
}

/// A file sent with a message (chat_service.py: _user_message_extra).
nonisolated struct BotAttachmentDTO: Decodable, Hashable, Sendable {
    var id: String?
    var filename: String?
    var url: String?
}

/// One message of GET /api/bot-chat/{session_id}/messages (bot_chat_service.py: client_message over the
/// stored row of core/session_manager.py: _append_message).
nonisolated struct BotMessageDTO: Decodable, Hashable, Sendable {
    var id: String
    var parentId: String?
    /// "user" or "assistant".
    var role: String?
    var content: String?
    var ts: Double?
    /// "complete", "failed", "interrupted", or null on an ordinary finished reply.
    var status: String?
    /// Empty on an ordinary message. Otherwise what special row to draw: "stopped", "goal_digest",
    /// "card", "handoff", "fd_card", "bot_created", "widget", "app", "data_result", "compaction",
    /// "digest", "verify".
    var kind: String?
    var type: String?
    /// A row that is shown but never sent to the model (a note, a card).
    var displayOnly: Bool?
    /// The id of the message this one replies to (text, not an object).
    var replyTo: JSONValue?
    var replyToId: String?
    var reactions: [BotReactionDTO]?
    var version: BotMessageVersionDTO?
    var attachments: [BotAttachmentDTO]?
    var references: [JSONValue]?
    var citations: [JSONValue]?
    /// null, "goal" or "spoken" on the person's message.
    var mode: String?
    var botSendId: String?
    var runId: String?
    var turnId: String?
    /// "rate_limited", "request_error" or "model_error" on a failed reply.
    var failureKind: String?
    var failureModelEndpointId: String?
    var failureModelName: String?
    var failureHadTools: Bool?
    var via: String?
    /// Set on the summary a call leaves in the conversation.
    var callSummaryId: String?
    var callDetails: JSONValue?
    var goalStep: JSONValue?
    var goalRoot: String?
    var digest: JSONValue?
    var summary: JSONValue?
    var verify: JSONValue?
    var card: JSONValue?
    var cardType: String?
    var receiptId: String?
    /// A front desk card (services/front_desk_cards.py): "brief", "prep", "reminder", "task_link",
    /// "suggestion", "route", "forge", "make", "chips", "checkin", "welcome", "reach" or "watching".
    var fdKind: String?
    var fdKey: String?
    var fdStatus: String?
    var fdData: JSONValue?
    /// A handoff row (services/agent_handoff.py): "queued", "working", "needs_you", "done" or "failed".
    var handoffStatus: String?
    var note: String?
    var assignmentId: String?
    var cardId: String?
    var partner: JSONValue?
    var agentId: String?
    var inboxItemId: String?
    var questionStatus: String?
    var botCreated: JSONValue?
    var botId: String?
}

/// GET /api/bot-chat/{session_id}/messages, and the answer of choosing another version
/// (bot_chat_service.py: messages). Oldest first.
nonisolated struct BotMessagesPageDTO: Decodable, Hashable, Sendable {
    var messages: [BotMessageDTO]?
    /// Older messages exist: ask again with `before` set to `firstId`.
    var hasBefore: Bool?
    var hasAfter: Bool?
    var firstId: String?
    var lastId: String?
    var total: Int?
    var activeLeafId: String?
    var branchRevision: Int?
    var pinnedMessageId: String?
    var lastReadMessageId: String?
}

/// A message as it is stored, before it is made ready for a page: `message` in a send's answer and in a
/// bot.fd_card packet (core/session_manager.py: _append_message). It has no `id`; its id is `botMessageId`.
nonisolated struct BotStoredMessageDTO: Decodable, Hashable, Sendable {
    var botMessageId: String?
    var parentId: String?
    var role: String?
    var content: String?
    var ts: Double?
    var status: String?
    var kind: String?
    var type: String?
    var displayOnly: Bool?
    var replyToId: String?
    var attachments: [BotAttachmentDTO]?
    var mode: String?
    var botSendId: String?
    var fdKind: String?
    var fdKey: String?
    var fdStatus: String?
    var fdData: JSONValue?
}

// MARK: - Sending and the queue

/// POST /api/bot-chat/{session_id}/send (202), and the answers of editing a question and redoing an
/// answer (core/bot_chat_store.py: accept).
nonisolated struct BotSendResultDTO: Decodable, Hashable, Sendable {
    var accepted: Bool?
    var sendId: String?
    var sessionId: String?
    /// true: the message waits in the queue and no turn started.
    var queued: Bool?
    var queueId: String?
    /// Why it was queued: "busy", "queued-ahead" or "capacity". null when it started.
    var reason: String?
    /// The turn that started. null when queued.
    var turnId: String?
    /// The saved message. Left out when queued.
    var message: BotStoredMessageDTO?
    var messageId: String?
    var messageIndex: Int?
    var activeLeafId: String?
    var branchRevision: Int?
    var queueRevision: Int?
    /// true when this send id was already accepted and this is the first answer again.
    var replayed: Bool?
}

/// The answer of removing a waiting message, taking one back to edit it, and resuming the queue
/// (bot_chat_service.py: queue_cancel, queue_edit, queue_resume). Each also carries the queue as it is now.
nonisolated struct BotQueueChangeDTO: Decodable, Hashable, Sendable {
    var cancelled: Bool?
    var queueId: String?
    /// The message taken back, to put in the composer. Only from the edit route.
    var draft: BotQueueItemDTO?
    /// How many interrupted messages went back to waiting. Only from the resume route.
    var resumed: Int?
    var items: [BotQueueItemDTO]?
    var revision: Int?
    var paused: Bool?
    var consumedQueueIds: [String]?
}

/// POST /api/bot-chat/{session_id}/queue/{queue_id}/steer (bot_chat_service.py: queue_steer).
nonisolated struct BotSteerResultDTO: Decodable, Hashable, Sendable {
    var steered: Bool?
    /// Why not: "not-first", "mixed", "turn-changed", "stop-timeout", "busy", "capacity", "changed",
    /// "references" or "no-bot".
    var blocked: String?
    var consumedIds: [String]?
    var turnId: String?
    var threadId: String?
}

/// POST /api/bot-chat/{session_id}/interrupt (bot_chat_service.py: interrupt).
nonisolated struct BotInterruptResultDTO: Decodable, Hashable, Sendable {
    /// "stopping" or "already-stopped".
    var outcome: String?
    var turnId: String?
}

/// POST /api/bot-chat/{session_id}/goal/stop (bot_goal_runs.py: stop).
nonisolated struct BotGoalStopResultDTO: Decodable, Hashable, Sendable {
    /// "stopping" or "already-stopped".
    var outcome: String?
    var rootId: String?
}

/// POST /api/bot-chat/{session_id}/read (bot_chat_service.py: mark_read).
nonisolated struct BotReadResultDTO: Decodable, Hashable, Sendable {
    var lastReadMessageId: String?
    var unread: Bool?
}

/// POST /api/bot-chat/{session_id}/messages/{message_id}/reaction (bot_chat_service.py: react).
nonisolated struct BotReactionResultDTO: Decodable, Hashable, Sendable {
    var messageId: String?
    var reactions: [BotReactionDTO]?
}

/// PATCH /api/bot-chat/{session_id}/pin (bot_chat_service.py: pin).
nonisolated struct BotPinResultDTO: Decodable, Hashable, Sendable {
    var pinnedMessageId: String?
}

// MARK: - Cards (approvals and questions inside a conversation)

/// One line of a card's details (bot_cards.py: redact_details).
nonisolated struct BotCardLineDTO: Decodable, Hashable, Sendable {
    var label: String?
    var value: String?
}

/// `details` on a card (bot_cards.py: redact_details).
nonisolated struct BotCardDetailsDTO: Decodable, Hashable, Sendable {
    var summary: String?
    var lines: [BotCardLineDTO]?
    /// What an "always" answer would cover.
    var target: String?
    var tool: String?
}

/// One answer an approval card offers (bot_cards.py: open_card).
nonisolated struct BotCardChoiceDTO: Decodable, Hashable, Sendable {
    var id: String?
    var label: String?
    /// "allow" or "deny".
    var behavior: String?
    /// "once", "session", "forever" or "team".
    var scope: String?
}

/// One option of a question (bot_cards.py: normalize_questions).
nonisolated struct BotCardOptionDTO: Decodable, Hashable, Sendable {
    var label: String?
    var description: String?
}

/// One question on a question card (bot_cards.py: normalize_questions).
nonisolated struct BotCardQuestionDTO: Decodable, Hashable, Sendable {
    /// Answers are sent keyed by this id.
    var id: String?
    var question: String?
    var header: String?
    var multiSelect: Bool?
    var allowCustom: Bool?
    var options: [BotCardOptionDTO]?
}

/// How a card was settled: `outcome` (bot_cards.py: _settle_locked, respond, resume_card).
nonisolated struct BotCardOutcomeDTO: Decodable, Hashable, Sendable {
    var reason: String?
    var by: String?
    var choiceId: String?
    var label: String?
    var scope: String?
    /// Question id to the answer: text, or a list of texts for a pick-several question.
    var answers: JSONValue?
    var asNewTurn: Bool?
    var resume: JSONValue?
}

/// A card: the durable record of one request a bot made (bot_cards.py: CardStore.open_card, public).
nonisolated struct BotCardDTO: Decodable, Hashable, Sendable {
    var id: String
    var ownerUser: String?
    var botId: String?
    /// The conversation (session id) the card belongs to.
    var threadId: String?
    var runId: String?
    var generation: Int?
    /// "approval", "question", "connector", "credential", "signin" or "computer".
    var kind: String?
    /// "pending", "settling", "allowed", "denied", "answered", "skipped", "expired", "unavailable"
    /// or "cancelled".
    var status: String?
    /// Send it back as `reviewed_revision`, so an answer to changed details is refused.
    var revision: Int?
    var title: String?
    var details: BotCardDetailsDTO?
    var choices: [BotCardChoiceDTO]?
    var questions: [BotCardQuestionDTO]?
    var persistent: Bool?
    var sourceKey: String?
    var resume: JSONValue?
    var createdAt: Double?
    var expiresAt: Double?
    var settledAt: Double?
    var outcome: BotCardOutcomeDTO?
    /// true while the card is "pending" or "settling".
    var waiting: Bool?
}

/// GET /api/bot-cards (bot_card_routes.py: list_cards). Oldest first.
nonisolated struct BotCardListDTO: Decodable, Hashable, Sendable {
    var cards: [BotCardDTO]?
    /// How many are still waiting.
    var pending: Int?
}

/// What to send as a new message when a kept question is answered after its turn ended
/// (bot_cards.py: respond).
nonisolated struct BotCardResumeDTO: Decodable, Hashable, Sendable {
    var asNewTurn: Bool?
    var cardId: String?
    var botId: String?
    var threadId: String?
    var answers: JSONValue?
    var text: String?
}

/// POST /api/bot-cards/{card_id}/respond and /resume (bot_cards.py: respond, resume_card).
/// `ok` false with a 200 means the request was no longer waiting and nothing ran; `message` says so.
nonisolated struct BotCardRespondResultDTO: Decodable, Hashable, Sendable {
    var ok: Bool?
    var card: BotCardDTO?
    var message: String?
    var resume: BotCardResumeDTO?
}

// MARK: - Attention: the inbox and the notification feed

/// Where a row leads (bot_attention.py: target_for). `tab` is "botsShell" (a bot's conversation:
/// `agentId`, and `sessionId` and `messageId` when known) or "botsRoom" (a room: `roomId`).
nonisolated struct BotTargetDTO: Decodable, Hashable, Sendable {
    var tab: String?
    var agentId: String?
    var sessionId: String?
    var messageId: String?
    var roomId: String?
}

/// `sender` on an inbox row.
nonisolated struct BotInboxSenderDTO: Decodable, Hashable, Sendable {
    var id: String?
    var name: String?
}

/// A question on an inbox row. On a "permission:" row these come from the live request
/// (core/permissions.py: Request.payload) and are answered keyed by the question's own text.
nonisolated struct BotInboxQuestionDTO: Decodable, Hashable, Sendable {
    var id: String?
    var question: String?
    var header: String?
    var multiSelect: Bool?
    /// Each option is `{label, description}`.
    var options: [JSONValue]?
}

/// One inbox row (bot_attention.py: _row, inbox).
nonisolated struct BotInboxRowDTO: Decodable, Hashable, Sendable {
    /// "item:<id>" (a bot's report or question), "review:<card id>" (a result to review) or
    /// "permission:<request id>" (a live approval or question in a conversation).
    var id: String
    var sourceId: String?
    /// "question", "report", "review" or "approval".
    var kind: String?
    var sender: BotInboxSenderDTO?
    var subject: String?
    var snippet: String?
    var body: String?
    var at: Double?
    /// "open" or "resolved".
    var status: String?
    var target: BotTargetDTO?
    /// What `respond` accepts for this row: from "reply", "close", "open", "approve", "respond",
    /// "skip", "allow", "deny". Empty once resolved.
    var actions: [String]?
    /// A hash of the row. Send it back as `expected_revision`.
    var revision: String?
    var answer: String?
    var questions: [BotInboxQuestionDTO]?
    var read: Bool?
    var done: Bool?
    /// "needs-you", "news" or "done".
    var bucket: String?
}

/// GET /api/bot-attention/inbox and /needs-you (bot_attention.py: inbox, needs_you).
/// The needs-you route sends `rows` only.
nonisolated struct BotInboxDTO: Decodable, Hashable, Sendable {
    var rows: [BotInboxRowDTO]?
    /// Keyed "needs-you", "news" and "done".
    var counts: [String: Int]?
    /// The same number as counts["needs-you"].
    var count: Int?
}

/// POST /api/bot-attention/inbox/{id}/respond (bot_attention.py: respond).
nonisolated struct BotInboxRespondResultDTO: Decodable, Hashable, Sendable {
    var ok: Bool?
    var result: String?
}

/// `call_back` on a missed-call notification (services/rings.py: _missed_item).
nonisolated struct BotCallBackDTO: Decodable, Hashable, Sendable {
    var ringId: String?
}

/// One kept notification (core/bot_attention_store.py: publish, notifications).
nonisolated struct BotNotificationDTO: Decodable, Hashable, Sendable {
    var id: String
    var sourceId: String?
    /// "approval", "question", "done", "turn-failed", "sign-in", "brief", "missed-call" and the other
    /// kinds of bot_attention.NOTIFICATION_KINDS.
    var kind: String?
    var agentId: String?
    var title: String?
    var body: String?
    var target: BotTargetDTO?
    var at: Double?
    /// The inbox row this is about, when there is one.
    var inboxId: String?
    var backlog: Bool?
    var read: Bool?
    var pinned: Bool?
    var callBack: BotCallBackDTO?
}

/// GET /api/bot-attention/notifications (bot_attention.py: notifications). Pinned first, then newest.
nonisolated struct BotNotificationsDTO: Decodable, Hashable, Sendable {
    var rows: [BotNotificationDTO]?
    var unread: Int?
}

// MARK: - Approvals

/// POST /api/permissions/{request_id}/answer and /respond (permission_routes.py: answer, respond).
nonisolated struct BotPermissionResultDTO: Decodable, Hashable, Sendable {
    /// "answered" or "skipped".
    var status: String?
}

/// One approval level and whether this bot's model supports it (core/bot_policy.py: view).
nonisolated struct BotApprovalLevelDTO: Decodable, Hashable, Sendable {
    var mode: String?
    var label: String?
    var blurb: String?
    var available: Bool?
    var reason: String?
}

/// GET /api/bots-approvals/{bot_id} and POST .../mode (core/bot_policy.py: view, change_mode).
nonisolated struct BotApprovalPolicyDTO: Decodable, Hashable, Sendable {
    var botId: String?
    var threadId: String?
    /// The level in force: "ask", "edits", "auto", "full" or "custom".
    var mode: String?
    var stored: String?
    var source: String?
    var inherited: Bool?
    var revision: Int?
    var reason: String?
    var supported: Bool?
    var provider: String?
    var botMode: String?
    var threadMode: String?
    var levels: [BotApprovalLevelDTO]?
    var storedBot: String?
    var commands: Int?
    var stateCorrupt: Bool?
    /// Only after a change: what lowering the level stopped.
    var enforcement: JSONValue?
}

// MARK: - Rings

/// A ring that is ringing now (services/rings.py: _view).
nonisolated struct RingDTO: Decodable, Hashable, Sendable {
    var id: String
    var agentId: String?
    var botName: String?
    /// What the call is about, in one short line.
    var reason: String?
    var createdAt: Double?
    var expiresAt: Double?
    /// "ringing", "answered", "declined" or "missed".
    var status: String?
    var secondsLeft: Int?
}

/// GET /api/rings/pending (ring_routes.py: pending).
nonisolated struct RingPendingDTO: Decodable, Hashable, Sendable {
    var rings: [RingDTO]?
    /// How many calls to other people are going.
    var outbound: Int?
}

/// POST /api/rings/{ring_id}/answer (services/rings.py: answer): where the call opens.
nonisolated struct RingAnswerDTO: Decodable, Hashable, Sendable {
    var ringId: String?
    var agentId: String?
    var botName: String?
    var reason: String?
    /// true when this answered a missed or declined ring (a call back).
    var callback: Bool?
    var target: BotTargetDTO?
}

// MARK: - Live packets

/// Every bot packet on GET /api/chat/live/events that is not an ordinary run packet, as one loose shape.
/// Read `type` first, then the fields that type sends:
/// - "bot_queue": sessionId, why, queueId, revision, paused, items, consumedQueueIds
///   (bot_chat_service.py: _announce)
/// - "bot_branch": sessionId, activeLeafId, branchRevision (bot_chat_service.py: _announce_branch)
/// - "bot_goal": sessionId, goal (bot_goal_runs.py: _frame)
/// - "bot_rich": sessionId, messageId, kind (bot_widgets.py: append_rich_row; bot_apps.py)
/// - "bot.fd_card": sessionId, event ("posted" or "updated"), message (front_desk_cards.py: _publish)
/// - "bot_card": sessionId, event ("opened", "updated" or "settled"), card
///   (bot_cards.py: CardStore._emit, sent on by app.py: publish_bot_resource)
/// - "bot_automation_change": sessionId, event, receipt (bot_automation_changes.py: _emit)
nonisolated struct BotLivePacketDTO: Decodable, Hashable, Sendable {
    var type: String?
    var sessionId: String?
    var event: String?
    /// bot_queue: "queued", "turn-ended", "dispatched", "cancelled", "edited", "resumed" or
    /// "references-changed".
    var why: String?
    var queueId: String?
    var revision: Int?
    var paused: Bool?
    var items: [BotQueueItemDTO]?
    var consumedQueueIds: [String]?
    var activeLeafId: String?
    var branchRevision: Int?
    var goal: BotGoalDTO?
    var messageId: String?
    var kind: String?
    var message: BotStoredMessageDTO?
    var card: BotCardDTO?
    var receipt: JSONValue?
}

// MARK: - Routes

extension APIClient {

    // MARK: Roster

    /// GET /api/agents: every bot of this account, Kip and archived ones included.
    func agentRoster() async throws -> [AgentDTO] {
        try await get("/api/agents")
    }

    /// GET /api/agents/{agent_id}: one bot with its notes, routines, cards and inbox. 404 when unknown.
    func agentDetail(_ agentId: String) async throws -> AgentDetailDTO {
        try await get("/api/agents/\(agentId)")
    }

    /// PATCH /api/agents/{agent_id}: change the named fields (for example `["enabled": false]`).
    /// Keys are the desktop's own (agent_routes.py: AgentBody). Answers the bot as the roster shows it.
    func agentUpdate(_ agentId: String, fields: [String: Any]) async throws -> AgentDTO {
        try await request("PATCH", "/api/agents/\(agentId)", json: fields)
    }

    /// GET /api/agents/conversations: each bot's latest conversation, its preview, unread count and pin.
    func agentConversations() async throws -> AgentConversationsDTO {
        try await get("/api/agents/conversations")
    }

    /// POST /api/agents/conversations/agent/{agent_id}: `action` is "pin", "unpin", "read" or "unread".
    func agentOrganize(_ agentId: String, action: String) async throws -> AgentConversationPrefDTO {
        try await post("/api/agents/conversations/agent/\(agentId)", json: ["action": action])
    }

    /// GET /api/bot-pulse: the slim poll. Send the versions you hold; only lists that changed come back.
    /// `only` (for example ["agents"]) reads just those lists and leaves the needs-you count out.
    func botPulse(
        agents: String? = nil,
        conversations: String? = nil,
        team: String? = nil,
        automations: String? = nil,
        only: [String] = []
    ) async throws -> BotPulseDTO {
        try await get("/api/bot-pulse", query: [
            "agents": agents,
            "conversations": conversations,
            "team": team,
            "automations": automations,
            "only": only.isEmpty ? nil : only.joined(separator: ","),
        ])
    }

    /// GET /api/bot-team/map: teams (departments), their bots, and rooms.
    func botTeamMap() async throws -> BotTeamMapDTO {
        try await get("/api/bot-team/map")
    }

    /// GET /api/bot-rooms: the rooms (conversations with several bots) and their members.
    func botRooms(includeArchived: Bool = false) async throws -> BotRoomListDTO {
        try await get("/api/bot-rooms", query: ["include_archived": includeArchived ? "true" : nil])
    }

    // MARK: A bot's conversations

    /// GET /api/agents/{agent_id}/threads: the bot's conversations and which one is its main.
    func agentThreads(_ agentId: String, includeArchived: Bool = false) async throws -> BotThreadListDTO {
        try await get("/api/agents/\(agentId)/threads", query: ["include_archived": includeArchived ? "1" : nil])
    }

    /// POST /api/agents/{agent_id}/threads: a new conversation. The answer's `id` is its session id.
    func agentCreateThread(_ agentId: String, title: String? = nil) async throws -> BotThreadDTO {
        var body: [String: Any] = [:]
        if let title { body["title"] = title }
        return try await post("/api/agents/\(agentId)/threads", json: body)
    }

    /// PATCH /api/agents/{agent_id}/threads/{session_id}: change the named fields. Keys the desktop takes:
    /// title, folder_id, pinned, archived, snooze, approval_mode, place, unread, timezone, main, link.
    func agentUpdateThread(_ agentId: String, sessionId: String, fields: [String: Any]) async throws -> BotThreadDTO {
        try await request("PATCH", "/api/agents/\(agentId)/threads/\(sessionId)", json: fields)
    }

    // MARK: One conversation

    /// GET /api/bot-chat/{session_id}/state: the leaf to send against, the running turn, the queue,
    /// the model line and the read cursor.
    func botChatState(_ sessionId: String) async throws -> BotChatStateDTO {
        try await get("/api/bot-chat/\(sessionId)/state")
    }

    /// GET /api/bot-chat/{session_id}/messages: a page of the version on screen, oldest first.
    /// No cursor gives the newest `limit` (1 to 200). Use one of `before`, `after`, `around` at most.
    func botChatMessages(
        _ sessionId: String,
        limit: Int = 50,
        before: String? = nil,
        after: String? = nil,
        around: String? = nil
    ) async throws -> BotMessagesPageDTO {
        try await get("/api/bot-chat/\(sessionId)/messages", query: [
            "limit": String(limit),
            "before": before,
            "after": after,
            "around": around,
        ])
    }

    /// POST /api/bot-chat/{session_id}/send (202). `sendId` is a fresh id of 8 to 80 characters made by
    /// the phone (a UUID); sending the same id again returns the first answer. `expectedLeafId` is the
    /// state's `activeLeafId` (nil for an empty conversation). `mode` is nil, "goal" or "spoken".
    func botChatSend(
        _ sessionId: String,
        sendId: String,
        text: String,
        expectedLeafId: String?,
        attachmentIds: [String] = [],
        replyToId: String? = nil,
        mode: String? = nil
    ) async throws -> BotSendResultDTO {
        var body: [String: Any] = ["send_id": sendId, "text": text]
        if let expectedLeafId { body["expected_leaf_id"] = expectedLeafId }
        if !attachmentIds.isEmpty { body["attachment_ids"] = attachmentIds }
        if let replyToId { body["reply_to_id"] = replyToId }
        if let mode { body["mode"] = mode }
        return try await post("/api/bot-chat/\(sessionId)/send", json: body)
    }

    /// GET /api/bot-chat/{session_id}/queue: the messages waiting to be sent.
    func botChatQueue(_ sessionId: String) async throws -> BotQueueDTO {
        try await get("/api/bot-chat/\(sessionId)/queue")
    }

    /// POST /api/bot-chat/{session_id}/queue/{queue_id}/edit: take a waiting message back out of the
    /// queue. `draft` is its text, to put in the composer.
    func botChatQueueEdit(_ sessionId: String, queueId: String) async throws -> BotQueueChangeDTO {
        try await request("POST", "/api/bot-chat/\(sessionId)/queue/\(queueId)/edit")
    }

    /// DELETE /api/bot-chat/{session_id}/queue/{queue_id}: remove a waiting message.
    func botChatQueueRemove(_ sessionId: String, queueId: String) async throws -> BotQueueChangeDTO {
        try await request("DELETE", "/api/bot-chat/\(sessionId)/queue/\(queueId)")
    }

    /// POST /api/bot-chat/{session_id}/queue/resume: let a paused queue run again.
    func botChatQueueResume(_ sessionId: String) async throws -> BotQueueChangeDTO {
        try await request("POST", "/api/bot-chat/\(sessionId)/queue/resume")
    }

    /// POST /api/bot-chat/{session_id}/queue/{queue_id}/steer: send the first waiting message now.
    /// It stops the running turn first. `turnId` is the running turn (nil when none runs) and
    /// `queueRevision` is the queue's `revision` as last read.
    func botChatSteer(
        _ sessionId: String,
        queueId: String,
        turnId: String?,
        queueRevision: Int,
        groupIds: [String]? = nil
    ) async throws -> BotSteerResultDTO {
        var body: [String: Any] = ["queue_revision": queueRevision]
        if let turnId { body["turn_id"] = turnId }
        if let groupIds { body["group_ids"] = groupIds }
        return try await post("/api/bot-chat/\(sessionId)/queue/\(queueId)/steer", json: body)
    }

    /// POST /api/bot-chat/{session_id}/interrupt: stop the named turn. Stopping one that is already
    /// over answers "already-stopped" and changes nothing.
    func botChatInterrupt(_ sessionId: String, turnId: String) async throws -> BotInterruptResultDTO {
        try await post("/api/bot-chat/\(sessionId)/interrupt", json: ["turn_id": turnId])
    }

    /// POST /api/bot-chat/{session_id}/goal/stop: stop a "work until done" run by its `rootId`.
    func botChatGoalStop(_ sessionId: String, rootId: String) async throws -> BotGoalStopResultDTO {
        try await post("/api/bot-chat/\(sessionId)/goal/stop", json: ["root_id": rootId])
    }

    /// POST /api/bot-chat/{session_id}/read: move the read cursor to this message (nil means the
    /// newest). Reading the last reply clears the conversation's unread mark.
    func botChatMarkRead(_ sessionId: String, messageId: String? = nil) async throws -> BotReadResultDTO {
        var body: [String: Any] = [:]
        if let messageId { body["message_id"] = messageId }
        return try await post("/api/bot-chat/\(sessionId)/read", json: body)
    }

    /// POST /api/bot-chat/{session_id}/messages/{message_id}/edit (202): edit one of the person's
    /// questions. The old version stays and can be chosen again. Refused with 409 while a reply runs.
    func botChatEdit(
        _ sessionId: String,
        messageId: String,
        sendId: String,
        text: String,
        expectedLeafId: String?,
        expectedRevision: Int
    ) async throws -> BotSendResultDTO {
        var body: [String: Any] = ["send_id": sendId, "text": text, "expected_revision": expectedRevision]
        if let expectedLeafId { body["expected_leaf_id"] = expectedLeafId }
        return try await post("/api/bot-chat/\(sessionId)/messages/\(messageId)/edit", json: body)
    }

    /// POST /api/bot-chat/{session_id}/regenerate (202): answer the last question again.
    func botChatRegenerate(
        _ sessionId: String,
        sendId: String,
        expectedLeafId: String?,
        expectedRevision: Int
    ) async throws -> BotSendResultDTO {
        var body: [String: Any] = ["send_id": sendId, "expected_revision": expectedRevision]
        if let expectedLeafId { body["expected_leaf_id"] = expectedLeafId }
        return try await post("/api/bot-chat/\(sessionId)/regenerate", json: body)
    }

    /// POST /api/bot-chat/{session_id}/active-branch: show another version. Answers the newest page.
    func botChatSelectBranch(_ sessionId: String, messageId: String, expectedRevision: Int) async throws -> BotMessagesPageDTO {
        try await post("/api/bot-chat/\(sessionId)/active-branch", json: [
            "message_id": messageId,
            "expected_revision": expectedRevision,
        ])
    }

    /// POST /api/bot-chat/{session_id}/messages/{message_id}/reaction: `emoji` is one of thumbs_up,
    /// thumbs_down, heart, laugh, tada, eyes.
    func botChatReact(_ sessionId: String, messageId: String, emoji: String, on: Bool) async throws -> BotReactionResultDTO {
        try await post("/api/bot-chat/\(sessionId)/messages/\(messageId)/reaction", json: ["emoji": emoji, "on": on])
    }

    /// PATCH /api/bot-chat/{session_id}/pin: pin one message, or unpin with nil.
    func botChatPin(_ sessionId: String, messageId: String?) async throws -> BotPinResultDTO {
        var body: [String: Any] = ["message_id": NSNull()]
        if let messageId { body["message_id"] = messageId }
        return try await request("PATCH", "/api/bot-chat/\(sessionId)/pin", json: body)
    }

    /// POST /api/bot-chat/presence: tell the desktop which conversation is on screen, at most once a
    /// minute. It holds back alerts for that conversation.
    func botChatPresence(timezone: String?, language: String?, focusedThread: String?) async throws {
        var body: [String: Any] = [:]
        if let timezone { body["timezone"] = timezone }
        if let language { body["language"] = language }
        if let focusedThread { body["focused_thread"] = focusedThread }
        try await call("POST", "/api/bot-chat/presence", json: body)
    }

    // MARK: Cards

    /// GET /api/bot-cards: the person's cards, oldest first. `status` "pending" means still waiting.
    func botCards(threadId: String? = nil, botId: String? = nil, status: String? = nil) async throws -> BotCardListDTO {
        try await get("/api/bot-cards", query: ["thread_id": threadId, "bot_id": botId, "status": status])
    }

    /// POST /api/bot-cards/{card_id}/respond. `action` is "allow" or "deny" on an approval card and
    /// "answer" or "skip" on a question card. `remember` is "once", "session" or "always" (only what
    /// the card's choices offer). `answers` is keyed by question id, each a text or a list of texts.
    func botCardRespond(
        _ cardId: String,
        action: String,
        choiceId: String? = nil,
        remember: String? = nil,
        answers: [String: Any]? = nil,
        reviewedRevision: Int? = nil
    ) async throws -> BotCardRespondResultDTO {
        var body: [String: Any] = ["action": action]
        if let choiceId { body["choice_id"] = choiceId }
        if let remember { body["remember"] = remember }
        if let answers { body["answers"] = answers }
        if let reviewedRevision { body["reviewed_revision"] = reviewedRevision }
        return try await post("/api/bot-cards/\(cardId)/respond", json: body)
    }

    /// POST /api/bot-cards/{card_id}/resume: finish ("done") or decline ("skipped") a connector,
    /// credential, sign-in or computer card.
    func botCardResume(_ cardId: String, outcome: String) async throws -> BotCardRespondResultDTO {
        try await post("/api/bot-cards/\(cardId)/resume", json: ["outcome": outcome])
    }

    // MARK: Attention

    /// GET /api/bot-attention/inbox: everything bots have for the person, newest first.
    func botInbox() async throws -> BotInboxDTO {
        try await get("/api/bot-attention/inbox")
    }

    /// GET /api/bot-attention/needs-you: only the rows still waiting on the person.
    func botNeedsYou() async throws -> BotInboxDTO {
        try await get("/api/bot-attention/needs-you")
    }

    /// POST /api/bot-attention/inbox/{id}/read.
    func botInboxMarkRead(_ rowId: String) async throws {
        try await call("POST", "/api/bot-attention/inbox/\(rowId)/read")
    }

    /// POST /api/bot-attention/inbox/{id}/done: file the row away. It answers nothing.
    func botInboxMarkDone(_ rowId: String) async throws {
        try await call("POST", "/api/bot-attention/inbox/\(rowId)/done")
    }

    /// POST /api/bot-attention/inbox/{id}/reopen.
    func botInboxReopen(_ rowId: String) async throws {
        try await call("POST", "/api/bot-attention/inbox/\(rowId)/reopen")
    }

    /// POST /api/bot-attention/inbox/{id}/respond. `action` is one of the row's `actions` (never
    /// "open"); `expectedRevision` is the row's `revision`. `answers` is for a question row with the
    /// "respond" action, keyed by each question's text.
    func botInboxRespond(
        _ rowId: String,
        action: String,
        expectedRevision: String,
        text: String = "",
        answers: [String: Any]? = nil
    ) async throws -> BotInboxRespondResultDTO {
        var body: [String: Any] = ["action": action, "expected_revision": expectedRevision, "text": text]
        if let answers { body["answers"] = answers }
        return try await post("/api/bot-attention/inbox/\(rowId)/respond", json: body)
    }

    /// GET /api/bot-attention/notifications: the kept notification feed (newest 500).
    func botNotifications() async throws -> BotNotificationsDTO {
        try await get("/api/bot-attention/notifications")
    }

    /// POST /api/bot-attention/notifications/read-all.
    func botNotificationsReadAll() async throws {
        try await call("POST", "/api/bot-attention/notifications/read-all")
    }

    /// POST /api/bot-attention/notifications/{id}/read.
    func botNotificationMarkRead(_ notificationId: String) async throws {
        try await call("POST", "/api/bot-attention/notifications/\(notificationId)/read")
    }

    /// POST /api/bot-attention/notifications/{id}/pin.
    func botNotificationPin(_ notificationId: String, pinned: Bool) async throws {
        try await call("POST", "/api/bot-attention/notifications/\(notificationId)/pin", json: ["pinned": pinned])
    }

    /// POST /api/bot-attention/threads/{session_id}/read: mark this conversation's notifications read.
    /// The desktop already does this when `botChatMarkRead` moves the cursor.
    func botAttentionThreadRead(_ sessionId: String, messageId: String? = nil) async throws {
        var body: [String: Any] = [:]
        if let messageId { body["message_id"] = messageId }
        try await call("POST", "/api/bot-attention/threads/\(sessionId)/read", json: body)
    }

    // MARK: Approvals

    /// POST /api/permissions/{request_id}/answer: answer a live approval with one of its choice ids
    /// ("once", "session", "forever" or "reject"). 409 when it is no longer waiting.
    func botPermissionAnswer(_ requestId: String, choice: String) async throws -> BotPermissionResultDTO {
        try await post("/api/permissions/\(requestId)/answer", json: ["choice": choice])
    }

    /// POST /api/permissions/{request_id}/respond: answer a live question, keyed by each question's
    /// text, or skip it.
    func botPermissionRespond(_ requestId: String, answers: [String: Any]?, skip: Bool = false) async throws -> BotPermissionResultDTO {
        var body: [String: Any] = ["skip": skip]
        if let answers { body["answers"] = answers }
        return try await post("/api/permissions/\(requestId)/respond", json: body)
    }

    /// GET /api/bots-approvals/{bot_id}: the bot's approval level, and a conversation's when named.
    func botApprovalPolicy(_ botId: String, threadId: String? = nil) async throws -> BotApprovalPolicyDTO {
        try await get("/api/bots-approvals/\(botId)", query: ["thread_id": threadId])
    }

    /// POST /api/bots-approvals/{bot_id}/mode: lower the level, or set one that is not higher. Raising
    /// it is refused here: only the desktop app can confirm that. `scope` is "bot", "thread" or
    /// "all_threads"; `mode` nil (with scope "thread") makes a conversation follow its bot again.
    func botApprovalSetMode(
        _ botId: String,
        mode: String?,
        scope: String = "bot",
        threadId: String? = nil,
        expectedRevision: Int? = nil
    ) async throws -> BotApprovalPolicyDTO {
        var body: [String: Any] = ["scope": scope]
        if let mode { body["mode"] = mode }
        if let threadId { body["thread_id"] = threadId }
        if let expectedRevision { body["expected_revision"] = expectedRevision }
        return try await post("/api/bots-approvals/\(botId)/mode", json: body)
    }

    // MARK: Rings

    /// GET /api/rings/pending: the rings ringing for this person now.
    func ringPending() async throws -> RingPendingDTO {
        try await get("/api/rings/pending")
    }

    /// POST /api/rings/{ring_id}/answer. `viaLink` true (a notification's Answer) only answers a ring
    /// that is still ringing; false also calls back a missed or declined one. 409 when it has ended.
    func ringAnswer(_ ringId: String, viaLink: Bool = false) async throws -> RingAnswerDTO {
        try await request("POST", "/api/rings/\(ringId)/answer", query: ["via": viaLink ? "link" : nil])
    }

    /// POST /api/rings/{ring_id}/decline. 409 when it is no longer ringing.
    func ringDecline(_ ringId: String) async throws {
        try await call("POST", "/api/rings/\(ringId)/decline")
    }
}
