import Foundation

/// What a sample check throws when a value the desktop always sends came back nil or wrong.
nonisolated struct BotSampleError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

/// A sample answer for every bot route and bot live packet in `BotAPI.swift`, shaped exactly like the
/// desktop's own (the structure was copied from its source; the content is made up).
/// `checks` decodes each one through the real decoder, so a wrong decoder fails where it can be seen.
nonisolated enum BotSamples {

    // MARK: - Roster

    /// GET /api/agents
    static let roster = #"""
    [
      {
        "id": "0f1e2d3c4b", "name": "Kip", "role": "Your front desk",
        "blurb": "Takes requests and hands them to the right bot.", "revision": 3,
        "endpoint_id": null, "color": "#d9b260", "enabled": true, "daily_run_cap": 100,
        "deliver_to_channel": null, "integration_ids": null, "keep_signed_in": false,
        "memory_upkeep": false, "peers": [], "created_at": 1793000000.5,
        "section": null, "origin": {"kind": "blank"}, "hidden": false, "hidden_at": null, "order": -1,
        "folders": [], "thread_limit": 3, "approval_mode": "ask",
        "outbound": {"policy": "ask", "daily_cap": 25}, "fallback": [], "cache_keep_warm": "follow",
        "place": "auto", "tool_scope": {"allow": [], "deny": []}, "connector_scopes": {},
        "always_allow": [], "builtin": "front_desk", "reply_style": "conversational",
        "notifications": true, "speak_replies": false, "voice_id": null, "call_mode": "turns",
        "skill_selection": {"mode": "all", "disabled": []}, "avatar_image": null,
        "mascot_expression": null, "browser_enabled": true, "browser_profile": "own",
        "avatar": {"version": 3, "character": "ajar", "shape": "round", "color": "#D9B260", "acc": "none", "finish": "flat"},
        "soul": "Greet the person and route the work.",
        "instructions": "Greet the person and route the work.",
        "status": "idle", "status_detail": "", "activity": null, "needs_you": 0, "runs_today": 2
      },
      {
        "id": "a1b2c3d4e5", "name": "Scout", "role": "Research",
        "blurb": "Finds prices and suppliers for the bike shop.", "revision": 5,
        "endpoint_id": "m1", "model_override": "sonnet", "model_effort": "medium",
        "color": "#e8c39e", "enabled": true, "daily_run_cap": 12,
        "deliver_to_channel": null, "integration_ids": ["int01"], "keep_signed_in": true,
        "memory_upkeep": true, "peers": ["b2c3d4e5f6"], "created_at": 1793100000.25,
        "section": "Content", "origin": {"kind": "ready", "id": "scout"}, "hidden": false,
        "hidden_at": null, "order": null,
        "folders": [{"id": "f01a2b3c4d", "name": "Suppliers", "emoji": "", "order": 0}],
        "thread_limit": 3, "approval_mode": "ask",
        "outbound": {"policy": "ask", "daily_cap": 25}, "fallback": [], "cache_keep_warm": "follow",
        "place": "auto", "tool_scope": {"allow": [], "deny": []}, "connector_scopes": {},
        "always_allow": [], "builtin": null, "reply_style": "default",
        "notifications": true, "speak_replies": false, "voice_id": "ryan", "call_mode": "turns",
        "skill_selection": {"mode": "all", "disabled": []}, "avatar_image": null,
        "mascot_expression": null, "browser_enabled": true, "browser_profile": "own",
        "avatar": {"version": 3, "character": "ajar", "shape": "round", "color": "#E8C39E", "acc": "rays", "finish": "flat"},
        "soul": "Be brief.", "instructions": "Be brief.",
        "status": "needs_you", "status_detail": "Tyre prices",
        "activity": {"kind": "chat", "working": true, "waiting": true, "name": "Tyre prices", "detail": "Compare three suppliers for touring tyres.", "count": 1},
        "needs_you": 2, "runs_today": 3
      },
      {
        "id": "b2c3d4e5f6", "name": "Quill", "role": "Writing",
        "blurb": "", "revision": 1,
        "endpoint_id": null, "color": "#cdbfd9", "enabled": false, "daily_run_cap": 12,
        "deliver_to_channel": null, "integration_ids": null, "keep_signed_in": false,
        "memory_upkeep": false, "peers": [], "created_at": 1793200000,
        "section": "Content", "origin": {"kind": "blank"}, "hidden": false, "hidden_at": null, "order": null,
        "folders": [], "thread_limit": 3, "approval_mode": "full",
        "outbound": {"policy": "ask", "daily_cap": 25}, "fallback": [], "cache_keep_warm": "follow",
        "place": "auto", "tool_scope": {"allow": [], "deny": []}, "connector_scopes": {},
        "always_allow": [], "builtin": null, "reply_style": "default",
        "notifications": true, "speak_replies": false, "voice_id": null, "call_mode": "turns",
        "skill_selection": {"mode": "all", "disabled": []},
        "avatar_image": {"asset_id": "00112233445566778899aabbccddeeff", "shape": "circle", "zoom": 1.2, "focus_x": 0.5, "focus_y": 0.4},
        "mascot_expression": null, "browser_enabled": true, "browser_profile": "own",
        "avatar": {"version": 3, "character": "ajar", "shape": "tall", "color": "#CDBFD9", "acc": "quill", "finish": "flat"},
        "soul": null, "instructions": "",
        "status": "off", "status_detail": "Quill is turned off", "activity": null,
        "needs_you": 0, "runs_today": 0
      }
    ]
    """#

    /// GET /api/agents/{agent_id}
    static let agentDetail = #"""
    {
      "agent": {
        "id": "a1b2c3d4e5", "name": "Scout", "role": "Research", "blurb": "", "revision": 5,
        "endpoint_id": "m1", "color": "#e8c39e", "enabled": true, "daily_run_cap": 12,
        "created_at": 1793100000.25, "builtin": null, "approval_mode": "ask", "voice_id": "ryan",
        "avatar": {"version": 3, "character": "ajar", "shape": "round", "color": "#E8C39E", "acc": "rays", "finish": "flat"},
        "soul": "Be brief.", "instructions": "Be brief.",
        "status": "idle", "status_detail": "", "activity": null, "needs_you": 1, "runs_today": 3
      },
      "soul_file": {"soul": "Be brief.", "file_text": "Be brief.", "in_sync": true, "revision": 5, "bytes": 9, "limit": 24000},
      "memory": "# Scout's notes\n\n## About this work\n- Prices for the bike shop\n",
      "memory_upkeep_journal": [],
      "setup_receipts": [],
      "goals": [
        {"id": "g1", "name": "Weekly prices", "prompt": "Check tyre prices.", "schedule_kind": "daily", "run_time": "08:00", "enabled": true, "agent_id": "a1b2c3d4e5"}
      ],
      "cards": [
        {"id": "c9", "name": "Shortlist five suppliers", "schedule_kind": "card", "status": "ready", "agent_id": "a1b2c3d4e5", "comments": []}
      ],
      "inbox": [
        {"id": "9a8b7c6d5e4f", "agent_id": "a1b2c3d4e5", "kind": "question", "created_at": 1794441000.0, "status": "open", "title": "Which supplier first?", "body": "Two suppliers answered. Which one should I ask for a quote?", "card_id": null, "task_id": null, "answer": null}
      ],
      "answered": [
        {"id": "1a2b3c4d5e6f", "agent_id": "a1b2c3d4e5", "kind": "report", "created_at": 1794400000.0, "status": "answered", "title": "Tyre prices", "body": "Three suppliers compared.", "card_id": "c7", "task_id": null, "answer": "Thanks."}
      ],
      "runs": [],
      "teams": [{"id": "s1", "name": "Launch team", "state": "active", "member_id": "s1-m2", "is_lead": 0}],
      "triggers": [],
      "avatar_snapshot": "9f8e7d6c5b4a3921"
    }
    """#

    /// GET /api/agents/conversations
    static let conversations = #"""
    {
      "agents": [
        {"id": "0f1e2d3c4b", "session_id": "5e55100a0001", "preview": "Good morning. Two things need you today.", "last_role": "assistant", "at": 1794441600.0, "message_count": 8, "pinned": true, "unread": 1},
        {"id": "a1b2c3d4e5", "session_id": "5e55100a0002", "preview": "Which supplier should I ask first?", "last_role": "assistant", "at": 1794441000.0, "message_count": 4, "pinned": false, "unread": 0},
        {"id": "b2c3d4e5f6", "session_id": null, "preview": "", "last_role": null, "at": 0, "message_count": 0, "pinned": false, "unread": 0}
      ],
      "preferences": {"agent:0f1e2d3c4b": {"pinned": true, "unread": false, "read_count": 7, "session_id": "5e55100a0001"}}
    }
    """#

    /// POST /api/agents/conversations/agent/{agent_id}
    static let conversationPref = #"""
    {"pinned": true, "unread": false, "read_count": 7, "session_id": "5e55100a0001"}
    """#

    /// GET /api/bot-pulse, first read: every list.
    static let pulse = #"""
    {
      "versions": {"agents": "3f9c2a7d41be08a5c6d2", "conversations": "0a1b2c3d4e5f60718293", "team": "aa11bb22cc33dd44ee55", "automations": null},
      "agents": [
        {"id": "0f1e2d3c4b", "name": "Kip", "role": "Your front desk", "color": "#d9b260", "enabled": true, "builtin": "front_desk", "order": -1,
         "avatar": {"version": 3, "character": "ajar", "shape": "round", "color": "#D9B260", "acc": "none", "finish": "flat"},
         "status": "idle", "status_detail": "", "activity": null, "needs_you": 0, "runs_today": 2},
        {"id": "c3d4e5f6a7", "name": "Producer", "role": "Runs the content team", "color": "#b9d2e3", "enabled": true, "builtin": null, "order": null,
         "avatar": {"version": 3, "character": "ajar", "shape": "squircle", "color": "#B9D2E3", "acc": "spectacles", "finish": "flat"},
         "status": "working", "status_detail": "Draft the Friday report",
         "activity": {"kind": "task", "working": true, "waiting": false, "name": "Draft the Friday report", "detail": "Write the weekly report for the bike shop."},
         "needs_you": 0, "runs_today": 1}
      ],
      "conversations": {
        "agents": [
          {"id": "0f1e2d3c4b", "session_id": "5e55100a0001", "preview": "Good morning.", "last_role": "assistant", "at": 1794441600.0, "message_count": 8, "pinned": true, "unread": 1}
        ],
        "preferences": {}
      },
      "team": {"departments": [], "members": [], "bots": [], "rooms": [], "handoffs": []},
      "needs_you": 2
    }
    """#

    /// GET /api/bot-pulse when nothing changed: versions and the count only.
    static let pulseQuiet = #"""
    {
      "versions": {"agents": "3f9c2a7d41be08a5c6d2", "conversations": "0a1b2c3d4e5f60718293", "team": "aa11bb22cc33dd44ee55", "automations": "1122334455667788990a"},
      "needs_you": 0
    }
    """#

    /// GET /api/bot-team/map
    static let teamMap = #"""
    {
      "departments": [
        {"id": "d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5", "name": "Content", "order": 0, "chief_bot_id": "c3d4e5f6a7", "also_manages": [], "created_at": 1793300000.0, "revision": 2, "owner_user": "owner"}
      ],
      "members": [
        {"id": "c3d4e5f6a7", "name": "Producer", "role": "Runs the content team", "section": "Content",
         "avatar": {"version": 3, "character": "ajar", "shape": "squircle", "color": "#B9D2E3", "acc": "spectacles", "finish": "flat"},
         "endpoint_id": null, "model_override": null, "model_effort": null,
         "department_id": "d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5", "chief": true, "status": "working"},
        {"id": "a1b2c3d4e5", "name": "Scout", "role": "Research", "section": "Content",
         "avatar": {"version": 3, "character": "ajar", "shape": "round", "color": "#E8C39E", "acc": "rays", "finish": "flat"},
         "endpoint_id": "m1", "model_override": "sonnet", "model_effort": "medium",
         "department_id": "d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5", "chief": false, "status": "available"}
      ],
      "bots": [
        {"id": "c3d4e5f6a7", "name": "Producer", "role": "Runs the content team", "section": "Content",
         "avatar": {"version": 3, "character": "ajar", "shape": "squircle", "color": "#B9D2E3", "acc": "spectacles", "finish": "flat"},
         "endpoint_id": null, "model_override": null, "model_effort": null,
         "department_id": "d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5", "chief": true, "status": "working"}
      ],
      "rooms": [
        {"id": "r00m00000001", "name": "Content team", "context": "", "description": "Producer, Scout and Quill",
         "bulletin": "", "cwd": null, "default_responder": {"kind": "auto"}, "turn_timeout_minutes": 5,
         "setup_state": "done", "pinned_message_id": null, "revision": 4, "created_at": 1793400000.0, "archived_at": null,
         "members": [
           {"bot_id": "c3d4e5f6a7", "name": "Producer", "held": false, "working": true, "waiting": false, "seat_session_id": "5ea7000000a1", "last_seen_seq": 12},
           {"bot_id": "a1b2c3d4e5", "name": "Scout", "held": false, "working": false, "waiting": false, "seat_session_id": "5ea7000000a2", "last_seen_seq": 12}
         ],
         "working": true, "unread": 2, "last_seq": 14,
         "threads": [{"id": "th0000000001", "title": "General", "goal": null}]}
      ],
      "handoffs": []
    }
    """#

    /// GET /api/bot-rooms
    static let rooms = #"""
    {
      "rooms": [
        {"id": "r00m00000001", "name": "Content team", "context": "", "description": "Producer, Scout and Quill",
         "bulletin": "", "cwd": null, "default_responder": {"kind": "auto"}, "turn_timeout_minutes": 5,
         "setup_state": "done", "pinned_message_id": null, "revision": 4, "created_at": 1793400000.0, "archived_at": null,
         "members": [
           {"bot_id": "c3d4e5f6a7", "name": "Producer", "held": false, "working": false, "waiting": false, "seat_session_id": "5ea7000000a1", "last_seen_seq": 14},
           {"bot_id": "a1b2c3d4e5", "name": "Scout", "held": false, "working": false, "waiting": false, "seat_session_id": "5ea7000000a2", "last_seen_seq": 14},
           {"bot_id": "b2c3d4e5f6", "name": "Quill", "held": true, "working": false, "waiting": false, "seat_session_id": null, "last_seen_seq": 9}
         ],
         "working": false, "unread": 0, "last_seq": 14,
         "threads": [{"id": "th0000000001", "title": "General", "goal": null}]}
      ]
    }
    """#

    // MARK: - A bot's conversations

    /// GET /api/agents/{agent_id}/threads
    static let threads = #"""
    {
      "main_id": "5e55100a0002",
      "threads": [
        {
          "id": "5e55100a0002", "title": "Tyre prices", "created_at": 1794300000.0, "updated_at": 1794441000.0,
          "message_count": 4, "model_endpoint_id": "m1", "model_override": null, "model_effort": null,
          "follows_bot_model": true,
          "thread": {
            "main": true, "folder_id": null, "pinned": false, "archived_at": null, "snoozed_until": null,
            "approval_mode": null, "place": null, "unread": true, "last_read_index": 2,
            "pinned_message_index": null, "opened_by": "person", "routine_run_id": null,
            "title_source": "machine", "active_leaf_id": "4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d",
            "last_read_message_id": "2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b", "pinned_message_id": null,
            "branch_revision": 4, "queue_revision": 3, "queue_paused": false, "link": null
          },
          "status": "working", "preview": "Which supplier should I ask first?"
        },
        {
          "id": "5e55100a0003", "title": "Friday report", "created_at": 1794100000.0, "updated_at": 1794200000.0,
          "message_count": 2, "model_endpoint_id": "m1", "model_override": null, "model_effort": null,
          "follows_bot_model": true,
          "thread": {
            "main": false, "folder_id": "f01a2b3c4d", "pinned": true, "archived_at": null, "snoozed_until": 0,
            "approval_mode": "ask", "place": null, "unread": false, "last_read_index": 1,
            "pinned_message_index": null, "opened_by": "routine", "routine_run_id": "run77",
            "title_source": "person", "active_leaf_id": "7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e",
            "last_read_message_id": "7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e", "pinned_message_id": null,
            "branch_revision": 2, "queue_revision": 0, "queue_paused": false, "link": null
          },
          "status": "idle", "preview": "The report is due Friday. Here is the outline."
        }
      ]
    }
    """#

    /// GET /api/bot-chat/{session_id}/state
    static let chatState = #"""
    {
      "session_id": "5e55100a0002", "bot_id": "a1b2c3d4e5",
      "active_leaf_id": "4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d", "branch_revision": 4,
      "turn": {"id": "7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a", "turn_id": "7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a", "status": "processing", "stopping": false, "started_at": 1794441590.2, "permission": false},
      "context": {"percent": 42.5, "auto": true},
      "queue": {
        "items": [
          {"id": "9191919191919191919191919191aaaa", "state": "pending", "send_id": "0c7d2a52-6a1b-4a59-9d0e-2f1f3a9b8c01", "text": "Also check the delivery times.", "attachment_ids": [], "reply_to_id": null, "citations": [], "mode": null, "created_at": 1794441595.0, "resumes_message": false}
        ],
        "revision": 3, "paused": false, "consumed_queue_ids": ["8080808080808080808080808080bbbb"]
      },
      "goal": null,
      "model": {"label": "Claude sonnet", "endpoint_id": "m1", "name": "Claude", "kind": "claude_cli", "model": "sonnet", "effort": null},
      "capabilities": {"queue": true, "steer": "interrupt", "edit": true, "regenerate": true, "images": true, "compact": true, "thread_limit": 3, "steer_hint": "This stops the current reply, then sends your message."},
      "pinned_message_id": null,
      "last_read_message_id": "2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b"
    }
    """#

    /// GET /api/bot-chat/{session_id}/messages
    static let messages = #"""
    {
      "messages": [
        {
          "id": "1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a", "bot_message_id": "1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a", "parent_id": null,
          "role": "user", "content": "Compare three suppliers for touring tyres.", "ts": 1794441000.0, "status": "complete",
          "bot_send_id": "5b0a6c2e-93d4-4f0e-8a44-0d5f6e7a8b90", "reply_to_id": null, "reply_to": null,
          "citations": [], "mode": null,
          "attachments": [{"id": "att01", "filename": "price-list.pdf", "url": "/api/chat/files/att01-price-list.pdf"}],
          "reactions": [],
          "version": {"index": 1, "count": 2, "ids": ["0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f", "1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a"]}
        },
        {
          "id": "2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b", "bot_message_id": "2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b", "parent_id": "1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a",
          "role": "assistant", "content": "Here are three suppliers.\n\n1. North Road Cycles\n2. Hill Street Wheels\n3. Canal Bikes", "ts": 1794441060.5, "status": null,
          "run_id": "run0001", "reply_to": null,
          "reactions": [{"emoji": "thumbs_up", "count": 1, "mine": true}]
        },
        {
          "id": "3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c", "bot_message_id": "3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c", "parent_id": "2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b",
          "role": "assistant", "content": "You stopped this.", "ts": 1794441200.0, "status": "complete",
          "display_only": true, "kind": "stopped", "turn_id": "6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f",
          "reply_to": null, "reactions": []
        },
        {
          "id": "4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d", "bot_message_id": "4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d", "parent_id": "3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c",
          "role": "assistant", "content": "", "ts": 1794441300.0, "status": "failed",
          "run_id": "run0002", "failure_kind": "rate_limited", "failure_model_endpoint_id": "m1", "failure_model_name": "Claude", "failure_had_tools": false,
          "reply_to": null, "reactions": []
        }
      ],
      "has_before": true, "has_after": false,
      "first_id": "1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a", "last_id": "4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d",
      "total": 54, "active_leaf_id": "4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d", "branch_revision": 4,
      "pinned_message_id": null, "last_read_message_id": "2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b"
    }
    """#

    /// GET /api/bot-chat/{session_id}/messages in Kip's conversation: a front desk card and a handoff.
    static let messagesFrontDesk = #"""
    {
      "messages": [
        {
          "id": "a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0", "bot_message_id": "a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0", "parent_id": null,
          "role": "assistant", "content": "", "ts": 1794300000.0, "status": "complete",
          "type": "fd_card", "kind": "fd_card", "fd_kind": "reminder", "fd_key": "fd:report-friday", "fd_status": "open",
          "fd_data": {"title": "Report due Friday", "when_label": "Friday 5 pm", "lines": ["The weekly report for the bike shop is due."]},
          "fd_server": true, "display_only": true, "reply_to": null, "reactions": []
        },
        {
          "id": "b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0", "bot_message_id": "b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0", "parent_id": "a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0",
          "role": "assistant", "content": "Scout is looking into tyre prices.", "ts": 1794300100.0, "status": "complete",
          "type": "handoff", "kind": "handoff", "agent_id": "a1b2c3d4e5", "handoff_status": "working", "note": "",
          "assignment_id": "as01", "card_id": "c7", "mode": "report",
          "partner": {"id": "a1b2c3d4e5", "name": "Scout"}, "reply_to": null, "reactions": []
        }
      ],
      "has_before": false, "has_after": false,
      "first_id": "a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0", "last_id": "b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0",
      "total": 2, "active_leaf_id": "b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0", "branch_revision": 2,
      "pinned_message_id": null, "last_read_message_id": null
    }
    """#

    // MARK: - Sending and the queue

    /// POST /api/bot-chat/{session_id}/send (202) when the turn started.
    static let sendStarted = #"""
    {
      "accepted": true, "send_id": "5b0a6c2e-93d4-4f0e-8a44-0d5f6e7a8b90", "session_id": "5e55100a0002",
      "queued": false, "queue_id": null, "reason": null, "turn_id": "7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a",
      "message": {
        "bot_send_id": "5b0a6c2e-93d4-4f0e-8a44-0d5f6e7a8b90", "reply_to_id": null, "citations": [], "mode": null,
        "bot_message_id": "5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e", "parent_id": "4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d",
        "role": "user", "content": "Which one delivers fastest?", "ts": 1794441590.0, "status": "complete"
      },
      "message_id": "5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e", "message_index": 4,
      "active_leaf_id": "5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e", "branch_revision": 5, "queue_revision": 4
    }
    """#

    /// POST /api/bot-chat/{session_id}/send (202) when the bot was busy: the message waits.
    static let sendQueued = #"""
    {
      "accepted": true, "send_id": "0c7d2a52-6a1b-4a59-9d0e-2f1f3a9b8c01", "session_id": "5e55100a0002",
      "queued": true, "queue_id": "9191919191919191919191919191aaaa", "reason": "busy", "turn_id": null,
      "active_leaf_id": "5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e", "branch_revision": 5, "queue_revision": 5
    }
    """#

    /// GET /api/bot-chat/{session_id}/queue
    static let queue = #"""
    {
      "items": [
        {"id": "9191919191919191919191919191aaaa", "state": "pending", "send_id": "0c7d2a52-6a1b-4a59-9d0e-2f1f3a9b8c01", "text": "Also check the delivery times.", "attachment_ids": [], "reply_to_id": null, "citations": [], "mode": null, "created_at": 1794441595.0, "resumes_message": false},
        {"id": "9292929292929292929292929292aaaa", "state": "interrupted", "send_id": "7e1f0a33-58c2-4b7d-a2c1-9d0e4f5a6b12", "text": "And the price for a set of four.", "attachment_ids": ["att02"], "reply_to_id": null, "citations": [], "mode": null, "created_at": 1794441598.0, "resumes_message": true}
      ],
      "revision": 5, "paused": true, "consumed_queue_ids": ["8080808080808080808080808080bbbb"]
    }
    """#

    /// POST /api/bot-chat/{session_id}/queue/{queue_id}/edit
    static let queueEdit = #"""
    {
      "queue_id": "9191919191919191919191919191aaaa",
      "draft": {"id": "9191919191919191919191919191aaaa", "state": "cancelled", "send_id": "0c7d2a52-6a1b-4a59-9d0e-2f1f3a9b8c01", "text": "Also check the delivery times.", "attachment_ids": [], "reply_to_id": null, "citations": [], "mode": null, "created_at": 1794441595.0, "resumes_message": false},
      "items": [], "revision": 6, "paused": false,
      "consumed_queue_ids": ["9191919191919191919191919191aaaa", "8080808080808080808080808080bbbb"]
    }
    """#

    /// DELETE /api/bot-chat/{session_id}/queue/{queue_id}
    static let queueRemove = #"""
    {"cancelled": true, "queue_id": "9191919191919191919191919191aaaa", "items": [], "revision": 6, "paused": false, "consumed_queue_ids": ["9191919191919191919191919191aaaa"]}
    """#

    /// POST /api/bot-chat/{session_id}/queue/{queue_id}/steer
    static let steer = #"""
    {"steered": true, "consumed_ids": ["9191919191919191919191919191aaaa"], "turn_id": "8b8b8b8b8b8b8b8b8b8b8b8b8b8b8b8b", "thread_id": "5e55100a0002"}
    """#

    /// The same route when it could not send now.
    static let steerBlocked = #"""
    {"steered": false, "blocked": "turn-changed"}
    """#

    /// POST /api/bot-chat/{session_id}/interrupt
    static let interrupt = #"""
    {"outcome": "stopping", "turn_id": "7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a"}
    """#

    /// POST /api/bot-chat/{session_id}/read
    static let markRead = #"""
    {"last_read_message_id": "4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d", "unread": false}
    """#

    /// POST /api/bot-chat/{session_id}/messages/{message_id}/reaction
    static let reaction = #"""
    {"message_id": "2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b", "reactions": [{"emoji": "heart", "count": 1, "mine": true}]}
    """#

    // MARK: - Cards

    /// GET /api/bot-cards?thread_id=...
    static let cards = #"""
    {
      "cards": [
        {
          "id": "c0ffee0000000001", "owner_user": "owner", "bot_id": "a1b2c3d4e5", "thread_id": "5e55100a0002",
          "run_id": "run0001", "generation": 3, "kind": "question", "status": "answered", "revision": 1,
          "title": "Waiting for your response",
          "details": {"summary": "", "lines": [], "target": "", "tool": ""},
          "choices": [],
          "questions": [
            {"id": "q1", "question": "Which supplier should I ask first?", "header": "Supplier", "multi_select": false, "allow_custom": true,
             "options": [{"label": "North Road Cycles", "description": "Cheapest"}, {"label": "Hill Street Wheels", "description": "Fastest delivery"}]}
          ],
          "persistent": false, "source_key": null, "resume": null,
          "created_at": 1794441100.0, "expires_at": 1794442900.0, "settled_at": 1794441150.0,
          "outcome": {"reason": "", "by": "owner", "answers": {"q1": "North Road Cycles"}},
          "waiting": false
        },
        {
          "id": "c0ffee0000000002", "owner_user": "owner", "bot_id": "a1b2c3d4e5", "thread_id": "5e55100a0002",
          "run_id": "run0003", "generation": 4, "kind": "approval", "status": "pending", "revision": 1,
          "title": "Send an email",
          "details": {"summary": "Ask North Road Cycles for a quote.", "lines": [{"label": "to", "value": "sales@example.com"}, {"label": "subject", "value": "Quote for touring tyres"}], "target": "sales@example.com", "tool": "send_email"},
          "choices": [
            {"id": "once", "label": "Allow once", "behavior": "allow", "scope": "once"},
            {"id": "session", "label": "Always in this chat (sales@example.com)", "behavior": "allow", "scope": "session"},
            {"id": "forever", "label": "Always allow sales@example.com", "behavior": "allow", "scope": "forever"},
            {"id": "reject", "label": "Reject", "behavior": "deny", "scope": "once"}
          ],
          "questions": null, "persistent": false, "source_key": null, "resume": null,
          "created_at": 1794441580.0, "expires_at": 1794441700.0, "settled_at": null, "outcome": null,
          "waiting": true
        }
      ],
      "pending": 1
    }
    """#

    /// POST /api/bot-cards/{card_id}/respond
    static let cardRespond = #"""
    {
      "ok": true,
      "card": {
        "id": "c0ffee0000000002", "owner_user": "owner", "bot_id": "a1b2c3d4e5", "thread_id": "5e55100a0002",
        "run_id": "run0003", "generation": 4, "kind": "approval", "status": "allowed", "revision": 1,
        "title": "Send an email",
        "details": {"summary": "Ask North Road Cycles for a quote.", "lines": [], "target": "sales@example.com", "tool": "send_email"},
        "choices": [
          {"id": "once", "label": "Allow once", "behavior": "allow", "scope": "once"},
          {"id": "reject", "label": "Reject", "behavior": "deny", "scope": "once"}
        ],
        "questions": null, "persistent": false, "source_key": null, "resume": null,
        "created_at": 1794441580.0, "expires_at": 1794441700.0, "settled_at": 1794441600.0,
        "outcome": {"reason": "", "by": "owner", "choice_id": "once", "label": "Allow once", "scope": "once"},
        "waiting": false
      },
      "message": ""
    }
    """#

    /// The same route when the request was no longer waiting: 200, ok false, nothing ran.
    static let cardRespondGone = #"""
    {
      "ok": false,
      "card": {
        "id": "c0ffee0000000002", "bot_id": "a1b2c3d4e5", "thread_id": "5e55100a0002", "kind": "approval",
        "status": "unavailable", "revision": 1, "title": "Send an email",
        "details": {"summary": "", "lines": [], "target": "", "tool": "send_email"},
        "choices": [], "questions": null,
        "created_at": 1794441580.0, "expires_at": 1794441700.0, "settled_at": 1794441710.0,
        "outcome": {"reason": "This request is no longer waiting, so the action did not run."},
        "waiting": false
      },
      "message": "This request is no longer waiting, so the action did not run."
    }
    """#

    // MARK: - Attention

    /// GET /api/bot-attention/inbox
    static let inbox = #"""
    {
      "rows": [
        {
          "id": "permission:5f5f5f5f5f5f5f5f", "source_id": "permission:5f5f5f5f5f5f5f5f", "kind": "approval",
          "sender": {"id": "a1b2c3d4e5", "name": "Scout"},
          "subject": "Send an email", "snippet": "Ask North Road Cycles for a quote.", "body": "Ask North Road Cycles for a quote.",
          "at": 1794441580.0, "status": "open",
          "target": {"tab": "botsShell", "agentId": "a1b2c3d4e5", "sessionId": "5e55100a0002"},
          "actions": ["allow", "deny"], "revision": "0123456789abcdef0123456789abcdef",
          "answer": null, "questions": [], "read": false, "done": false, "bucket": "needs-you"
        },
        {
          "id": "item:9a8b7c6d5e4f", "source_id": "item:9a8b7c6d5e4f", "kind": "question",
          "sender": {"id": "a1b2c3d4e5", "name": "Scout"},
          "subject": "Which supplier first?", "snippet": "Two suppliers answered. Which one should I ask for a quote?",
          "body": "Two suppliers answered. Which one should I ask for a quote?",
          "at": 1794441000.0, "status": "open",
          "target": {"tab": "botsShell", "agentId": "a1b2c3d4e5", "sessionId": "5e55100a0002", "messageId": "2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b"},
          "actions": ["reply", "close"], "revision": "fedcba9876543210fedcba9876543210",
          "answer": null, "questions": [], "read": true, "done": false, "bucket": "needs-you"
        },
        {
          "id": "review:c7", "source_id": "review:c7", "kind": "review",
          "sender": {"id": "c3d4e5f6a7", "name": "Producer"},
          "subject": "Draft the Friday report", "snippet": "The draft is ready for you to read.", "body": "The draft is ready for you to read.",
          "at": 1794400000.0, "status": "resolved",
          "target": {"tab": "botsRoom", "roomId": "r00m00000001"},
          "actions": [], "revision": "00112233445566778899aabbccddeeff",
          "answer": null, "questions": [], "read": true, "done": true, "bucket": "done"
        }
      ],
      "counts": {"needs-you": 2, "news": 0, "done": 1},
      "count": 2
    }
    """#

    /// GET /api/bot-attention/needs-you: rows only. Here a live question from a conversation.
    static let needsYou = #"""
    {
      "rows": [
        {
          "id": "permission:6a6a6a6a6a6a6a6a", "source_id": "permission:6a6a6a6a6a6a6a6a", "kind": "question",
          "sender": {"id": "b2c3d4e5f6", "name": "Quill"},
          "subject": "Waiting for your response", "snippet": "", "body": "",
          "at": 1794441500.0, "status": "open",
          "target": {"tab": "botsShell", "agentId": "b2c3d4e5f6", "sessionId": "5e55100a0003"},
          "actions": ["respond", "skip"], "revision": "aabbccddeeff00112233445566778899",
          "answer": null,
          "questions": [
            {"question": "Which tone for the report?", "header": "Tone", "multiSelect": false,
             "options": [{"label": "Plain", "description": "Short and direct"}, {"label": "Warm", "description": "A little friendlier"}]}
          ],
          "read": false, "done": false, "bucket": "needs-you"
        }
      ]
    }
    """#

    /// POST /api/bot-attention/inbox/{id}/respond
    static let inboxRespond = #"""
    {"ok": true, "result": "answered"}
    """#

    /// GET /api/bot-attention/notifications
    static let notifications = #"""
    {
      "rows": [
        {
          "kind": "missed-call", "agent_id": "a1b2c3d4e5", "title": "Missed call from Scout", "body": "The supplier answered about the tyres.",
          "target": {"tab": "botsShell", "agentId": "a1b2c3d4e5", "sessionId": "5e55100a0002"},
          "at": 1794441650.0, "call_back": {"ring_id": "0123456789abcdef0123456789abcdef"},
          "id": "11111111111111111111111111111111", "source_id": "ring:0123456789abcdef0123456789abcdef",
          "read": false, "pinned": true
        },
        {
          "kind": "done", "agent_id": "c3d4e5f6a7", "title": "Reply ready", "body": "Reply ready",
          "target": {"tab": "botsShell", "agentId": "c3d4e5f6a7", "sessionId": "5e55100a0004", "messageId": "9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c"},
          "inbox_id": null, "at": 1794441400.0, "backlog": false,
          "id": "22222222222222222222222222222222", "source_id": "turn:5e55100a0004:7b7b7b7b:done",
          "read": false, "pinned": false
        },
        {
          "kind": "question", "agent_id": "a1b2c3d4e5", "title": "Which supplier first?", "body": "Two suppliers answered. Which one should I ask for a quote?",
          "target": {"tab": "botsShell", "agentId": "a1b2c3d4e5", "sessionId": "5e55100a0002"},
          "at": 1794441000.0, "inbox_id": "item:9a8b7c6d5e4f", "backlog": true,
          "id": "33333333333333333333333333333333", "source_id": "item:9a8b7c6d5e4f",
          "read": true, "pinned": false
        }
      ],
      "unread": 2
    }
    """#

    // MARK: - Approvals

    /// POST /api/permissions/{request_id}/answer
    static let permissionAnswer = #"""
    {"status": "answered"}
    """#

    /// GET /api/bots-approvals/{bot_id}
    static let approvalPolicy = #"""
    {
      "bot_id": "a1b2c3d4e5", "thread_id": null, "mode": "ask", "stored": "ask", "source": "bot",
      "inherited": false, "revision": 2, "reason": null, "supported": true, "provider": "claude",
      "bot_mode": "ask", "thread_mode": null,
      "levels": [
        {"mode": "ask", "label": "Ask", "blurb": "Reads go ahead. Changes and running things ask you first.", "available": true, "reason": null},
        {"mode": "edits", "label": "Edits", "blurb": "Edits to its own folders go ahead. Running things and outside changes ask.", "available": true, "reason": null},
        {"mode": "custom", "label": "Custom", "blurb": "Codex only. Exact commands you have approved go ahead. Everything else asks.", "available": false, "reason": "Only Codex supports this level."}
      ],
      "stored_bot": "ask", "commands": 0, "state_corrupt": false
    }
    """#

    // MARK: - Rings

    /// GET /api/rings/pending
    static let ringsPending = #"""
    {
      "rings": [
        {"id": "0123456789abcdef0123456789abcdef", "agent_id": "a1b2c3d4e5", "bot_name": "Scout", "reason": "The supplier answered about the tyres.", "created_at": 1794441600.0, "expires_at": 1794441660.0, "status": "ringing", "seconds_left": 41}
      ],
      "outbound": 0
    }
    """#

    /// POST /api/rings/{ring_id}/answer
    static let ringAnswer = #"""
    {
      "ring_id": "0123456789abcdef0123456789abcdef", "agent_id": "a1b2c3d4e5", "bot_name": "Scout",
      "reason": "The supplier answered about the tyres.", "callback": false,
      "target": {"tab": "botsShell", "agentId": "a1b2c3d4e5", "sessionId": "5e55100a0002"}
    }
    """#

    // MARK: - Live packets (GET /api/chat/live/events)

    /// A message was queued, sent, removed, or a turn ended.
    static let packetQueue = #"""
    {
      "type": "bot_queue", "sessionId": "5e55100a0002", "why": "queued", "queueId": "9191919191919191919191919191aaaa",
      "revision": 5, "paused": false,
      "items": [
        {"id": "9191919191919191919191919191aaaa", "state": "pending", "send_id": "0c7d2a52-6a1b-4a59-9d0e-2f1f3a9b8c01", "text": "Also check the delivery times.", "attachment_ids": [], "reply_to_id": null, "citations": [], "mode": null, "created_at": 1794441595.0, "resumes_message": false}
      ],
      "consumedQueueIds": ["8080808080808080808080808080bbbb"]
    }
    """#

    /// Another version of the conversation was chosen.
    static let packetBranch = #"""
    {"type": "bot_branch", "sessionId": "5e55100a0002", "activeLeafId": "0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f", "branchRevision": 6}
    """#

    /// A "work until done" run moved on.
    static let packetGoal = #"""
    {
      "type": "bot_goal", "sessionId": "5e55100a0003",
      "goal": {
        "root_id": "600d600d600d600d600d600d600d600d", "status": "working", "label": "Working",
        "goal": "Write the weekly report for the bike shop.", "turn": 2, "max_turns": 13,
        "detail": "The sales section is done.", "tail": "Now the repairs section.",
        "started_at": 1794441000.0, "updated_at": 1794441300.0, "turn_id": "7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c"
      }
    }
    """#

    /// A card, small app or data result was added to the conversation.
    static let packetRich = #"""
    {"type": "bot_rich", "sessionId": "5e55100a0002", "messageId": "d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1", "kind": "widget"}
    """#

    /// Kip posted or changed a front desk card.
    static let packetFrontDeskCard = #"""
    {
      "type": "bot.fd_card", "sessionId": "5e55100a0001", "event": "posted",
      "message": {
        "type": "fd_card", "fd_kind": "reminder", "fd_key": "fd:report-friday", "fd_status": "open",
        "fd_data": {"title": "Report due Friday", "when_label": "Friday 5 pm", "lines": ["The weekly report for the bike shop is due."]},
        "fd_server": true, "display_only": true,
        "bot_message_id": "a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0", "parent_id": null,
        "role": "assistant", "content": "", "ts": 1794300000.0, "status": "complete"
      }
    }
    """#

    /// An approval or question card opened, changed or was settled.
    static let packetCard = #"""
    {
      "type": "bot_card", "event": "opened", "sessionId": "5e55100a0002",
      "card": {
        "id": "c0ffee0000000002", "owner_user": "owner", "bot_id": "a1b2c3d4e5", "thread_id": "5e55100a0002",
        "run_id": "run0003", "generation": 4, "kind": "approval", "status": "pending", "revision": 1,
        "title": "Send an email",
        "details": {"summary": "Ask North Road Cycles for a quote.", "lines": [{"label": "to", "value": "sales@example.com"}], "target": "sales@example.com", "tool": "send_email"},
        "choices": [
          {"id": "once", "label": "Allow once", "behavior": "allow", "scope": "once"},
          {"id": "reject", "label": "Reject", "behavior": "deny", "scope": "once"}
        ],
        "questions": null, "persistent": false, "source_key": null, "resume": null,
        "created_at": 1794441580.0, "expires_at": 1794441700.0, "settled_at": null, "outcome": null,
        "waiting": true
      }
    }
    """#

    /// A bot changed one of its own routines.
    static let packetAutomationChange = #"""
    {
      "type": "bot_automation_change", "event": "applied", "sessionId": "5e55100a0002",
      "receipt": {"id": "ac01ac01ac01ac01", "bot_id": "a1b2c3d4e5", "thread_id": "5e55100a0002", "state": "applied", "action": "update", "created_at": 1794441500.0, "undoable": true}
    }
    """#

    // MARK: - Checks

    static func need<T>(_ value: T?, _ what: String) throws -> T {
        guard let value else { throw BotSampleError("\(what) came back nil") }
        return value
    }

    static func expect(_ condition: Bool, _ what: String) throws {
        if !condition { throw BotSampleError("\(what) is wrong") }
    }

    static func checkRoster() throws -> String {
        let bots = try KJSON.decode([AgentDTO].self, from: roster)
        try expect(bots.count == 3, "roster count")
        let kip = try need(bots.first, "roster[0]")
        try expect(kip.isFrontDesk, "roster[0].builtin")
        try expect(try need(kip.name, "roster[0].name") == "Kip", "roster[0].name")
        try expect(try need(kip.order, "roster[0].order") == -1, "roster[0].order")
        try expect(try need(kip.dailyRunCap, "roster[0].daily_run_cap") == 100, "roster[0].daily_run_cap")
        try expect(try need(kip.threadLimit, "roster[0].thread_limit") == 3, "roster[0].thread_limit")
        try expect(try need(kip.approvalMode, "roster[0].approval_mode") == "ask", "roster[0].approval_mode")
        try expect(try need(kip.replyStyle, "roster[0].reply_style") == "conversational", "roster[0].reply_style")
        try expect(kip.botStatus == .online, "roster[0] status")
        let scout = bots[1]
        try expect(try need(scout.endpointId, "roster[1].endpoint_id") == "m1", "roster[1].endpoint_id")
        try expect(try need(scout.modelOverride, "roster[1].model_override") == "sonnet", "roster[1].model_override")
        try expect(try need(scout.voiceId, "roster[1].voice_id") == "ryan", "roster[1].voice_id")
        try expect(try need(scout.statusDetail, "roster[1].status_detail") == "Tyre prices", "roster[1].status_detail")
        try expect(try need(scout.needsYou, "roster[1].needs_you") == 2, "roster[1].needs_you")
        try expect(try need(scout.runsToday, "roster[1].runs_today") == 3, "roster[1].runs_today")
        try expect(try need(scout.keepSignedIn, "roster[1].keep_signed_in"), "roster[1].keep_signed_in")
        try expect(try need(scout.section, "roster[1].section") == "Content", "roster[1].section")
        let activity = try need(scout.activity, "roster[1].activity")
        try expect(try need(activity.waiting, "roster[1].activity.waiting"), "roster[1].activity.waiting")
        try expect(try need(activity.count, "roster[1].activity.count") == 1, "roster[1].activity.count")
        try expect(try need(scout.folders?.first?.name, "roster[1].folders[0].name") == "Suppliers", "roster[1].folders[0].name")
        try expect(scout.botStatus == .needsYou, "roster[1] status")
        try expect(scout.bodyColorHex == 0xE8C39E, "roster[1] colour")
        try expect(scout.mascotShape == .round, "roster[1] shape")
        try expect(scout.mascotAccessory == .rays, "roster[1] accessory")
        let quill = bots[2]
        try expect(try need(quill.enabled, "roster[2].enabled") == false, "roster[2].enabled")
        try expect(quill.botStatus == .offline, "roster[2] status")
        try expect(quill.mascotShape == .tall, "roster[2] shape")
        try expect(quill.mascotAccessory == .quill, "roster[2] accessory")
        try expect(quill.bodyColorHex == 0xCDBFD9, "roster[2] colour")
        let picture = try need(quill.avatarImage, "roster[2].avatar_image")
        _ = try need(picture.assetId, "roster[2].avatar_image.asset_id")
        try expect(try need(picture.focusY, "roster[2].avatar_image.focus_y") == 0.4, "roster[2].avatar_image.focus_y")
        return "\(bots.count) bots"
    }

    static func checkAgentDetail() throws -> String {
        let detail = try KJSON.decode(AgentDetailDTO.self, from: agentDetail)
        let agent = try need(detail.agent, "detail.agent")
        try expect(agent.id == "a1b2c3d4e5", "detail.agent.id")
        _ = try need(detail.memory, "detail.memory")
        _ = try need(detail.soulFile, "detail.soul_file")
        _ = try need(detail.avatarSnapshot, "detail.avatar_snapshot")
        try expect(try need(detail.goals, "detail.goals").count == 1, "detail.goals")
        try expect(try need(detail.cards, "detail.cards").count == 1, "detail.cards")
        try expect(try need(detail.teams, "detail.teams").count == 1, "detail.teams")
        let waiting = try need(detail.inbox?.first, "detail.inbox[0]")
        try expect(try need(waiting.kind, "detail.inbox[0].kind") == "question", "detail.inbox[0].kind")
        _ = try need(waiting.createdAt, "detail.inbox[0].created_at")
        let answered = try need(detail.answered?.first, "detail.answered[0]")
        _ = try need(answered.answer, "detail.answered[0].answer")
        try expect(try need(answered.cardId, "detail.answered[0].card_id") == "c7", "detail.answered[0].card_id")
        return "\(agent.name ?? "?") in detail"
    }

    static func checkConversations() throws -> String {
        let list = try KJSON.decode(AgentConversationsDTO.self, from: conversations)
        let rows = try need(list.agents, "conversations.agents")
        try expect(rows.count == 3, "conversations count")
        try expect(try need(rows[0].sessionId, "conversations[0].session_id") == "5e55100a0001", "conversations[0].session_id")
        try expect(try need(rows[0].pinned, "conversations[0].pinned"), "conversations[0].pinned")
        try expect(try need(rows[0].unread, "conversations[0].unread") == 1, "conversations[0].unread")
        try expect(try need(rows[0].messageCount, "conversations[0].message_count") == 8, "conversations[0].message_count")
        try expect(try need(rows[0].lastRole, "conversations[0].last_role") == "assistant", "conversations[0].last_role")
        try expect(rows[2].sessionId == nil, "conversations[2].session_id")
        _ = try need(list.preferences, "conversations.preferences")
        let pref = try KJSON.decode(AgentConversationPrefDTO.self, from: conversationPref)
        try expect(try need(pref.readCount, "pref.read_count") == 7, "pref.read_count")
        return "\(rows.count) conversations"
    }

    static func checkPulse() throws -> String {
        let full = try KJSON.decode(BotPulseDTO.self, from: pulse)
        let versions = try need(full.versions, "pulse.versions")
        _ = try need(versions.agents, "pulse.versions.agents")
        try expect(versions.automations == nil, "pulse.versions.automations")
        let bots = try need(full.agents, "pulse.agents")
        try expect(bots.count == 2, "pulse.agents count")
        try expect(bots[1].botStatus == .working, "pulse.agents[1] status")
        try expect(try need(bots[1].activity?.kind, "pulse.agents[1].activity.kind") == "task", "pulse.agents[1].activity.kind")
        _ = try need(full.conversations?.agents?.first, "pulse.conversations.agents[0]")
        _ = try need(full.team, "pulse.team")
        try expect(try need(full.needsYou, "pulse.needs_you") == 2, "pulse.needs_you")
        let quiet = try KJSON.decode(BotPulseDTO.self, from: pulseQuiet)
        try expect(quiet.agents == nil && quiet.conversations == nil && quiet.team == nil, "quiet pulse lists")
        _ = try need(quiet.versions?.automations, "quiet pulse versions.automations")
        try expect(try need(quiet.needsYou, "quiet pulse needs_you") == 0, "quiet pulse needs_you")
        return "\(bots.count) bots changed, \(full.needsYou ?? 0) need you"
    }

    static func checkTeams() throws -> String {
        let map = try KJSON.decode(BotTeamMapDTO.self, from: teamMap)
        let team = try need(map.departments?.first, "team.departments[0]")
        try expect(try need(team.chiefBotId, "team.departments[0].chief_bot_id") == "c3d4e5f6a7", "team.departments[0].chief_bot_id")
        try expect(try need(team.revision, "team.departments[0].revision") == 2, "team.departments[0].revision")
        let members = try need(map.members, "team.members")
        try expect(members.count == 2, "team.members count")
        try expect(try need(members[0].chief, "team.members[0].chief"), "team.members[0].chief")
        try expect(try need(members[0].departmentId, "team.members[0].department_id") == team.id, "team.members[0].department_id")
        try expect(try need(members[0].avatar?.shape, "team.members[0].avatar.shape") == "squircle", "team.members[0].avatar.shape")
        let room = try need(map.rooms?.first, "team.rooms[0]")
        try expect(try need(room.unread, "team.rooms[0].unread") == 2, "team.rooms[0].unread")
        try expect(try need(room.turnTimeoutMinutes, "team.rooms[0].turn_timeout_minutes") == 5, "team.rooms[0].turn_timeout_minutes")
        let seat = try need(room.members?.first, "team.rooms[0].members[0]")
        try expect(try need(seat.botId, "team.rooms[0].members[0].bot_id") == "c3d4e5f6a7", "team.rooms[0].members[0].bot_id")
        _ = try need(seat.seatSessionId, "team.rooms[0].members[0].seat_session_id")
        let list = try KJSON.decode(BotRoomListDTO.self, from: rooms)
        let listed = try need(list.rooms?.first, "rooms[0]")
        try expect(try need(listed.members, "rooms[0].members").count == 3, "rooms[0].members count")
        try expect(try need(listed.setupState, "rooms[0].setup_state") == "done", "rooms[0].setup_state")
        try expect(try need(listed.threads?.first?.title, "rooms[0].threads[0].title") == "General", "rooms[0].threads[0].title")
        return "1 team, \(members.count) members, 1 room"
    }

    static func checkThreads() throws -> String {
        let list = try KJSON.decode(BotThreadListDTO.self, from: threads)
        try expect(try need(list.mainId, "threads.main_id") == "5e55100a0002", "threads.main_id")
        let rows = try need(list.threads, "threads.threads")
        try expect(rows.count == 2, "threads count")
        let first = rows[0]
        try expect(try need(first.messageCount, "threads[0].message_count") == 4, "threads[0].message_count")
        try expect(try need(first.followsBotModel, "threads[0].follows_bot_model"), "threads[0].follows_bot_model")
        try expect(try need(first.status, "threads[0].status") == "working", "threads[0].status")
        _ = try need(first.updatedAt, "threads[0].updated_at")
        let meta = try need(first.thread, "threads[0].thread")
        try expect(try need(meta.main, "threads[0].thread.main"), "threads[0].thread.main")
        try expect(try need(meta.unread, "threads[0].thread.unread"), "threads[0].thread.unread")
        try expect(try need(meta.branchRevision, "threads[0].thread.branch_revision") == 4, "threads[0].thread.branch_revision")
        try expect(try need(meta.queueRevision, "threads[0].thread.queue_revision") == 3, "threads[0].thread.queue_revision")
        _ = try need(meta.activeLeafId, "threads[0].thread.active_leaf_id")
        _ = try need(meta.lastReadMessageId, "threads[0].thread.last_read_message_id")
        let second = try need(rows[1].thread, "threads[1].thread")
        try expect(try need(second.openedBy, "threads[1].thread.opened_by") == "routine", "threads[1].thread.opened_by")
        try expect(try need(second.snoozedUntil, "threads[1].thread.snoozed_until") == 0, "threads[1].thread.snoozed_until")
        try expect(try need(second.folderId, "threads[1].thread.folder_id") == "f01a2b3c4d", "threads[1].thread.folder_id")
        return "\(rows.count) conversations"
    }

    static func checkState() throws -> String {
        let state = try KJSON.decode(BotChatStateDTO.self, from: chatState)
        try expect(try need(state.sessionId, "state.session_id") == "5e55100a0002", "state.session_id")
        try expect(try need(state.botId, "state.bot_id") == "a1b2c3d4e5", "state.bot_id")
        _ = try need(state.activeLeafId, "state.active_leaf_id")
        try expect(try need(state.branchRevision, "state.branch_revision") == 4, "state.branch_revision")
        let turn = try need(state.turn, "state.turn")
        _ = try need(turn.startedAt, "state.turn.started_at")
        try expect(try need(turn.permission, "state.turn.permission") == false, "state.turn.permission")
        try expect(try need(state.runningTurnId, "state running turn") == "7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a", "state running turn")
        try expect(try need(state.context?.percent, "state.context.percent") == 42.5, "state.context.percent")
        let queue = try need(state.queue, "state.queue")
        try expect(try need(queue.revision, "state.queue.revision") == 3, "state.queue.revision")
        try expect(try need(queue.consumedQueueIds, "state.queue.consumed_queue_ids").count == 1, "state.queue.consumed_queue_ids")
        let waiting = try need(queue.items?.first, "state.queue.items[0]")
        _ = try need(waiting.sendId, "state.queue.items[0].send_id")
        try expect(try need(waiting.resumesMessage, "state.queue.items[0].resumes_message") == false, "state.queue.items[0].resumes_message")
        try expect(try need(state.model?.label, "state.model.label") == "Claude sonnet", "state.model.label")
        try expect(try need(state.model?.endpointId, "state.model.endpoint_id") == "m1", "state.model.endpoint_id")
        let can = try need(state.capabilities, "state.capabilities")
        try expect(try need(can.queue, "state.capabilities.queue"), "state.capabilities.queue")
        _ = try need(can.steer, "state.capabilities.steer")
        try expect(try need(can.threadLimit, "state.capabilities.thread_limit") == 3, "state.capabilities.thread_limit")
        _ = try need(can.steerHint, "state.capabilities.steer_hint")
        _ = try need(state.lastReadMessageId, "state.last_read_message_id")
        return "turn running, \(queue.items?.count ?? 0) waiting"
    }

    static func checkMessages() throws -> String {
        let page = try KJSON.decode(BotMessagesPageDTO.self, from: messages)
        let rows = try need(page.messages, "messages.messages")
        try expect(rows.count == 4, "messages count")
        try expect(try need(page.hasBefore, "messages.has_before"), "messages.has_before")
        try expect(try need(page.hasAfter, "messages.has_after") == false, "messages.has_after")
        try expect(try need(page.firstId, "messages.first_id") == rows[0].id, "messages.first_id")
        try expect(try need(page.lastId, "messages.last_id") == rows[3].id, "messages.last_id")
        try expect(try need(page.total, "messages.total") == 54, "messages.total")
        try expect(try need(page.activeLeafId, "messages.active_leaf_id") == rows[3].id, "messages.active_leaf_id")
        try expect(try need(page.branchRevision, "messages.branch_revision") == 4, "messages.branch_revision")
        _ = try need(page.lastReadMessageId, "messages.last_read_message_id")
        let mine = rows[0]
        try expect(try need(mine.role, "messages[0].role") == "user", "messages[0].role")
        _ = try need(mine.ts, "messages[0].ts")
        _ = try need(mine.botSendId, "messages[0].bot_send_id")
        try expect(try need(mine.attachments?.first?.filename, "messages[0].attachments[0].filename") == "price-list.pdf", "messages[0].attachments[0].filename")
        let version = try need(mine.version, "messages[0].version")
        try expect(try need(version.index, "messages[0].version.index") == 1, "messages[0].version.index")
        try expect(try need(version.ids, "messages[0].version.ids").count == 2, "messages[0].version.ids")
        let reply = rows[1]
        try expect(try need(reply.parentId, "messages[1].parent_id") == mine.id, "messages[1].parent_id")
        try expect(reply.status == nil, "messages[1].status")
        _ = try need(reply.runId, "messages[1].run_id")
        try expect(try need(reply.reactions?.first?.mine, "messages[1].reactions[0].mine"), "messages[1].reactions[0].mine")
        let note = rows[2]
        try expect(try need(note.displayOnly, "messages[2].display_only"), "messages[2].display_only")
        try expect(try need(note.kind, "messages[2].kind") == "stopped", "messages[2].kind")
        _ = try need(note.turnId, "messages[2].turn_id")
        let failed = rows[3]
        try expect(try need(failed.status, "messages[3].status") == "failed", "messages[3].status")
        try expect(try need(failed.failureKind, "messages[3].failure_kind") == "rate_limited", "messages[3].failure_kind")
        try expect(try need(failed.failureHadTools, "messages[3].failure_had_tools") == false, "messages[3].failure_had_tools")
        let desk = try KJSON.decode(BotMessagesPageDTO.self, from: messagesFrontDesk)
        let deskRows = try need(desk.messages, "front desk messages")
        try expect(try need(deskRows[0].fdKind, "front desk messages[0].fd_kind") == "reminder", "front desk messages[0].fd_kind")
        try expect(try need(deskRows[0].fdStatus, "front desk messages[0].fd_status") == "open", "front desk messages[0].fd_status")
        _ = try need(deskRows[0].fdData, "front desk messages[0].fd_data")
        try expect(try need(deskRows[1].handoffStatus, "front desk messages[1].handoff_status") == "working", "front desk messages[1].handoff_status")
        try expect(try need(deskRows[1].agentId, "front desk messages[1].agent_id") == "a1b2c3d4e5", "front desk messages[1].agent_id")
        _ = try need(deskRows[1].partner, "front desk messages[1].partner")
        try expect(desk.lastReadMessageId == nil, "front desk last_read_message_id")
        return "\(rows.count) messages, \(page.total ?? 0) in all"
    }

    static func checkSend() throws -> String {
        let started = try KJSON.decode(BotSendResultDTO.self, from: sendStarted)
        try expect(try need(started.accepted, "send.accepted"), "send.accepted")
        try expect(try need(started.queued, "send.queued") == false, "send.queued")
        _ = try need(started.turnId, "send.turn_id")
        try expect(try need(started.messageIndex, "send.message_index") == 4, "send.message_index")
        try expect(try need(started.branchRevision, "send.branch_revision") == 5, "send.branch_revision")
        try expect(try need(started.queueRevision, "send.queue_revision") == 4, "send.queue_revision")
        let saved = try need(started.message, "send.message")
        try expect(try need(saved.botMessageId, "send.message.bot_message_id") == started.messageId, "send.message.bot_message_id")
        try expect(try need(started.activeLeafId, "send.active_leaf_id") == started.messageId, "send.active_leaf_id")
        let waiting = try KJSON.decode(BotSendResultDTO.self, from: sendQueued)
        try expect(try need(waiting.queued, "queued send.queued"), "queued send.queued")
        try expect(try need(waiting.reason, "queued send.reason") == "busy", "queued send.reason")
        _ = try need(waiting.queueId, "queued send.queue_id")
        try expect(waiting.turnId == nil && waiting.message == nil, "queued send turn and message")
        return "one started, one queued (\(waiting.reason ?? "?"))"
    }

    static func checkQueue() throws -> String {
        let list = try KJSON.decode(BotQueueDTO.self, from: queue)
        let items = try need(list.items, "queue.items")
        try expect(items.count == 2, "queue count")
        try expect(try need(list.paused, "queue.paused"), "queue.paused")
        try expect(try need(items[1].state, "queue.items[1].state") == "interrupted", "queue.items[1].state")
        try expect(try need(items[1].attachmentIds, "queue.items[1].attachment_ids").count == 1, "queue.items[1].attachment_ids")
        try expect(try need(items[1].resumesMessage, "queue.items[1].resumes_message"), "queue.items[1].resumes_message")
        let edited = try KJSON.decode(BotQueueChangeDTO.self, from: queueEdit)
        let draft = try need(edited.draft, "queue edit.draft")
        try expect(try need(draft.text, "queue edit.draft.text") == "Also check the delivery times.", "queue edit.draft.text")
        try expect(try need(edited.revision, "queue edit.revision") == 6, "queue edit.revision")
        try expect(try need(edited.consumedQueueIds, "queue edit.consumed_queue_ids").count == 2, "queue edit.consumed_queue_ids")
        let removed = try KJSON.decode(BotQueueChangeDTO.self, from: queueRemove)
        try expect(try need(removed.cancelled, "queue remove.cancelled"), "queue remove.cancelled")
        _ = try need(removed.queueId, "queue remove.queue_id")
        return "\(items.count) waiting, paused"
    }

    static func checkSteerAndStop() throws -> String {
        let sent = try KJSON.decode(BotSteerResultDTO.self, from: steer)
        try expect(try need(sent.steered, "steer.steered"), "steer.steered")
        try expect(try need(sent.consumedIds, "steer.consumed_ids").count == 1, "steer.consumed_ids")
        _ = try need(sent.turnId, "steer.turn_id")
        try expect(try need(sent.threadId, "steer.thread_id") == "5e55100a0002", "steer.thread_id")
        let refused = try KJSON.decode(BotSteerResultDTO.self, from: steerBlocked)
        try expect(try need(refused.steered, "blocked steer.steered") == false, "blocked steer.steered")
        try expect(try need(refused.blocked, "blocked steer.blocked") == "turn-changed", "blocked steer.blocked")
        let stop = try KJSON.decode(BotInterruptResultDTO.self, from: interrupt)
        try expect(try need(stop.outcome, "interrupt.outcome") == "stopping", "interrupt.outcome")
        _ = try need(stop.turnId, "interrupt.turn_id")
        let read = try KJSON.decode(BotReadResultDTO.self, from: markRead)
        _ = try need(read.lastReadMessageId, "read.last_read_message_id")
        try expect(try need(read.unread, "read.unread") == false, "read.unread")
        let reacted = try KJSON.decode(BotReactionResultDTO.self, from: reaction)
        _ = try need(reacted.messageId, "reaction.message_id")
        try expect(try need(reacted.reactions?.first?.emoji, "reaction.reactions[0].emoji") == "heart", "reaction.reactions[0].emoji")
        return "steer, stop, read and reaction"
    }

    static func checkCards() throws -> String {
        let list = try KJSON.decode(BotCardListDTO.self, from: cards)
        let rows = try need(list.cards, "cards.cards")
        try expect(rows.count == 2, "cards count")
        try expect(try need(list.pending, "cards.pending") == 1, "cards.pending")
        let question = rows[0]
        try expect(try need(question.kind, "cards[0].kind") == "question", "cards[0].kind")
        try expect(try need(question.threadId, "cards[0].thread_id") == "5e55100a0002", "cards[0].thread_id")
        try expect(try need(question.generation, "cards[0].generation") == 3, "cards[0].generation")
        let asked = try need(question.questions?.first, "cards[0].questions[0]")
        try expect(try need(asked.id, "cards[0].questions[0].id") == "q1", "cards[0].questions[0].id")
        try expect(try need(asked.multiSelect, "cards[0].questions[0].multi_select") == false, "cards[0].questions[0].multi_select")
        try expect(try need(asked.allowCustom, "cards[0].questions[0].allow_custom"), "cards[0].questions[0].allow_custom")
        try expect(try need(asked.options, "cards[0].questions[0].options").count == 2, "cards[0].questions[0].options")
        _ = try need(asked.options?.first?.description, "cards[0].questions[0].options[0].description")
        _ = try need(question.outcome?.answers, "cards[0].outcome.answers")
        _ = try need(question.settledAt, "cards[0].settled_at")
        let approval = rows[1]
        try expect(try need(approval.waiting, "cards[1].waiting"), "cards[1].waiting")
        try expect(try need(approval.status, "cards[1].status") == "pending", "cards[1].status")
        try expect(try need(approval.revision, "cards[1].revision") == 1, "cards[1].revision")
        try expect(try need(approval.choices, "cards[1].choices").count == 4, "cards[1].choices")
        try expect(try need(approval.choices?.last?.behavior, "cards[1].choices[3].behavior") == "deny", "cards[1].choices[3].behavior")
        try expect(try need(approval.details?.lines, "cards[1].details.lines").count == 2, "cards[1].details.lines")
        try expect(try need(approval.details?.tool, "cards[1].details.tool") == "send_email", "cards[1].details.tool")
        _ = try need(approval.expiresAt, "cards[1].expires_at")
        try expect(approval.outcome == nil && approval.settledAt == nil, "cards[1] outcome")
        let answered = try KJSON.decode(BotCardRespondResultDTO.self, from: cardRespond)
        try expect(try need(answered.ok, "card respond.ok"), "card respond.ok")
        try expect(try need(answered.card?.status, "card respond.card.status") == "allowed", "card respond.card.status")
        try expect(try need(answered.card?.outcome?.choiceId, "card respond.card.outcome.choice_id") == "once", "card respond.card.outcome.choice_id")
        let gone = try KJSON.decode(BotCardRespondResultDTO.self, from: cardRespondGone)
        try expect(try need(gone.ok, "gone card respond.ok") == false, "gone card respond.ok")
        _ = try need(gone.message, "gone card respond.message")
        try expect(try need(gone.card?.status, "gone card respond.card.status") == "unavailable", "gone card respond.card.status")
        return "\(rows.count) cards, \(list.pending ?? 0) waiting"
    }

    static func checkInbox() throws -> String {
        let box = try KJSON.decode(BotInboxDTO.self, from: inbox)
        let rows = try need(box.rows, "inbox.rows")
        try expect(rows.count == 3, "inbox count")
        try expect(try need(box.count, "inbox.count") == 2, "inbox.count")
        let counts = try need(box.counts, "inbox.counts")
        try expect(try need(counts["needs-you"], "inbox.counts.needs-you") == 2, "inbox.counts.needs-you")
        try expect(try need(counts["done"], "inbox.counts.done") == 1, "inbox.counts.done")
        let approval = rows[0]
        try expect(try need(approval.kind, "inbox[0].kind") == "approval", "inbox[0].kind")
        try expect(try need(approval.sender?.name, "inbox[0].sender.name") == "Scout", "inbox[0].sender.name")
        try expect(try need(approval.actions, "inbox[0].actions") == ["allow", "deny"], "inbox[0].actions")
        _ = try need(approval.revision, "inbox[0].revision")
        _ = try need(approval.sourceId, "inbox[0].source_id")
        try expect(try need(approval.bucket, "inbox[0].bucket") == "needs-you", "inbox[0].bucket")
        try expect(try need(approval.read, "inbox[0].read") == false, "inbox[0].read")
        try expect(try need(approval.target?.sessionId, "inbox[0].target.sessionId") == "5e55100a0002", "inbox[0].target.sessionId")
        try expect(try need(rows[1].target?.messageId, "inbox[1].target.messageId") == "2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b", "inbox[1].target.messageId")
        try expect(try need(rows[2].target?.roomId, "inbox[2].target.roomId") == "r00m00000001", "inbox[2].target.roomId")
        try expect(try need(rows[2].done, "inbox[2].done"), "inbox[2].done")
        let waiting = try KJSON.decode(BotInboxDTO.self, from: needsYou)
        let live = try need(waiting.rows?.first, "needs-you.rows[0]")
        let asked = try need(live.questions?.first, "needs-you.rows[0].questions[0]")
        try expect(try need(asked.question, "needs-you question") == "Which tone for the report?", "needs-you question")
        try expect(try need(asked.multiSelect, "needs-you multiSelect") == false, "needs-you multiSelect")
        try expect(try need(asked.options, "needs-you options").count == 2, "needs-you options")
        try expect(waiting.counts == nil, "needs-you counts")
        let done = try KJSON.decode(BotInboxRespondResultDTO.self, from: inboxRespond)
        try expect(try need(done.ok, "inbox respond.ok"), "inbox respond.ok")
        _ = try need(done.result, "inbox respond.result")
        return "\(rows.count) rows, \(box.count ?? 0) need you"
    }

    static func checkNotifications() throws -> String {
        let feed = try KJSON.decode(BotNotificationsDTO.self, from: notifications)
        let rows = try need(feed.rows, "notifications.rows")
        try expect(rows.count == 3, "notifications count")
        try expect(try need(feed.unread, "notifications.unread") == 2, "notifications.unread")
        let missed = rows[0]
        try expect(try need(missed.kind, "notifications[0].kind") == "missed-call", "notifications[0].kind")
        try expect(try need(missed.pinned, "notifications[0].pinned"), "notifications[0].pinned")
        try expect(try need(missed.callBack?.ringId, "notifications[0].call_back.ring_id") == "0123456789abcdef0123456789abcdef", "notifications[0].call_back.ring_id")
        try expect(try need(missed.agentId, "notifications[0].agent_id") == "a1b2c3d4e5", "notifications[0].agent_id")
        _ = try need(missed.sourceId, "notifications[0].source_id")
        _ = try need(missed.at, "notifications[0].at")
        try expect(try need(rows[1].target?.messageId, "notifications[1].target.messageId") == "9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c", "notifications[1].target.messageId")
        try expect(try need(rows[1].backlog, "notifications[1].backlog") == false, "notifications[1].backlog")
        try expect(try need(rows[2].inboxId, "notifications[2].inbox_id") == "item:9a8b7c6d5e4f", "notifications[2].inbox_id")
        try expect(try need(rows[2].read, "notifications[2].read"), "notifications[2].read")
        return "\(rows.count) notifications, \(feed.unread ?? 0) unread"
    }

    static func checkApprovals() throws -> String {
        let answer = try KJSON.decode(BotPermissionResultDTO.self, from: permissionAnswer)
        try expect(try need(answer.status, "permission answer.status") == "answered", "permission answer.status")
        let policy = try KJSON.decode(BotApprovalPolicyDTO.self, from: approvalPolicy)
        try expect(try need(policy.mode, "policy.mode") == "ask", "policy.mode")
        try expect(try need(policy.botId, "policy.bot_id") == "a1b2c3d4e5", "policy.bot_id")
        try expect(try need(policy.revision, "policy.revision") == 2, "policy.revision")
        try expect(try need(policy.inherited, "policy.inherited") == false, "policy.inherited")
        try expect(try need(policy.botMode, "policy.bot_mode") == "ask", "policy.bot_mode")
        try expect(try need(policy.storedBot, "policy.stored_bot") == "ask", "policy.stored_bot")
        try expect(try need(policy.stateCorrupt, "policy.state_corrupt") == false, "policy.state_corrupt")
        let levels = try need(policy.levels, "policy.levels")
        try expect(levels.count == 3, "policy.levels count")
        try expect(try need(levels[2].available, "policy.levels[2].available") == false, "policy.levels[2].available")
        _ = try need(levels[2].reason, "policy.levels[2].reason")
        return "level \(policy.mode ?? "?"), \(levels.count) levels"
    }

    static func checkRings() throws -> String {
        let pending = try KJSON.decode(RingPendingDTO.self, from: ringsPending)
        let ring = try need(pending.rings?.first, "rings.rings[0]")
        try expect(try need(ring.botName, "rings[0].bot_name") == "Scout", "rings[0].bot_name")
        try expect(try need(ring.agentId, "rings[0].agent_id") == "a1b2c3d4e5", "rings[0].agent_id")
        try expect(try need(ring.status, "rings[0].status") == "ringing", "rings[0].status")
        try expect(try need(ring.secondsLeft, "rings[0].seconds_left") == 41, "rings[0].seconds_left")
        _ = try need(ring.expiresAt, "rings[0].expires_at")
        _ = try need(ring.reason, "rings[0].reason")
        try expect(try need(pending.outbound, "rings.outbound") == 0, "rings.outbound")
        let answered = try KJSON.decode(RingAnswerDTO.self, from: ringAnswer)
        try expect(try need(answered.ringId, "ring answer.ring_id") == ring.id, "ring answer.ring_id")
        try expect(try need(answered.callback, "ring answer.callback") == false, "ring answer.callback")
        try expect(try need(answered.target?.agentId, "ring answer.target.agentId") == "a1b2c3d4e5", "ring answer.target.agentId")
        try expect(try need(answered.target?.sessionId, "ring answer.target.sessionId") == "5e55100a0002", "ring answer.target.sessionId")
        return "1 ringing, \(ring.secondsLeft ?? 0) seconds left"
    }

    static func checkPackets() throws -> String {
        let queued = try KJSON.decode(BotLivePacketDTO.self, from: packetQueue)
        try expect(try need(queued.type, "bot_queue.type") == "bot_queue", "bot_queue.type")
        try expect(try need(queued.sessionId, "bot_queue.sessionId") == "5e55100a0002", "bot_queue.sessionId")
        try expect(try need(queued.why, "bot_queue.why") == "queued", "bot_queue.why")
        _ = try need(queued.queueId, "bot_queue.queueId")
        try expect(try need(queued.revision, "bot_queue.revision") == 5, "bot_queue.revision")
        try expect(try need(queued.paused, "bot_queue.paused") == false, "bot_queue.paused")
        _ = try need(queued.items?.first?.sendId, "bot_queue.items[0].send_id")
        try expect(try need(queued.consumedQueueIds, "bot_queue.consumedQueueIds").count == 1, "bot_queue.consumedQueueIds")

        let branch = try KJSON.decode(BotLivePacketDTO.self, from: packetBranch)
        try expect(try need(branch.type, "bot_branch.type") == "bot_branch", "bot_branch.type")
        _ = try need(branch.activeLeafId, "bot_branch.activeLeafId")
        try expect(try need(branch.branchRevision, "bot_branch.branchRevision") == 6, "bot_branch.branchRevision")

        let goal = try KJSON.decode(BotLivePacketDTO.self, from: packetGoal)
        let run = try need(goal.goal, "bot_goal.goal")
        _ = try need(run.rootId, "bot_goal.goal.root_id")
        try expect(try need(run.status, "bot_goal.goal.status") == "working", "bot_goal.goal.status")
        try expect(try need(run.turn, "bot_goal.goal.turn") == 2, "bot_goal.goal.turn")
        try expect(try need(run.maxTurns, "bot_goal.goal.max_turns") == 13, "bot_goal.goal.max_turns")
        _ = try need(run.turnId, "bot_goal.goal.turn_id")
        _ = try need(run.updatedAt, "bot_goal.goal.updated_at")

        let rich = try KJSON.decode(BotLivePacketDTO.self, from: packetRich)
        _ = try need(rich.messageId, "bot_rich.messageId")
        try expect(try need(rich.kind, "bot_rich.kind") == "widget", "bot_rich.kind")

        let desk = try KJSON.decode(BotLivePacketDTO.self, from: packetFrontDeskCard)
        try expect(try need(desk.type, "bot.fd_card.type") == "bot.fd_card", "bot.fd_card.type")
        try expect(try need(desk.event, "bot.fd_card.event") == "posted", "bot.fd_card.event")
        let posted = try need(desk.message, "bot.fd_card.message")
        _ = try need(posted.botMessageId, "bot.fd_card.message.bot_message_id")
        try expect(try need(posted.fdKind, "bot.fd_card.message.fd_kind") == "reminder", "bot.fd_card.message.fd_kind")
        try expect(try need(posted.fdKey, "bot.fd_card.message.fd_key") == "fd:report-friday", "bot.fd_card.message.fd_key")
        _ = try need(posted.fdData, "bot.fd_card.message.fd_data")
        try expect(try need(posted.displayOnly, "bot.fd_card.message.display_only"), "bot.fd_card.message.display_only")

        let card = try KJSON.decode(BotLivePacketDTO.self, from: packetCard)
        try expect(try need(card.event, "bot_card.event") == "opened", "bot_card.event")
        try expect(try need(card.sessionId, "bot_card.sessionId") == "5e55100a0002", "bot_card.sessionId")
        try expect(try need(card.card?.waiting, "bot_card.card.waiting"), "bot_card.card.waiting")
        try expect(try need(card.card?.choices, "bot_card.card.choices").count == 2, "bot_card.card.choices")

        let change = try KJSON.decode(BotLivePacketDTO.self, from: packetAutomationChange)
        try expect(try need(change.type, "bot_automation_change.type") == "bot_automation_change", "bot_automation_change.type")
        try expect(try need(change.event, "bot_automation_change.event") == "applied", "bot_automation_change.event")
        _ = try need(change.receipt, "bot_automation_change.receipt")
        return "7 packets"
    }

    static let checks: [DecodeCheck] = [
        DecodeCheck("bots.roster") { try BotSamples.checkRoster() },
        DecodeCheck("bots.detail") { try BotSamples.checkAgentDetail() },
        DecodeCheck("bots.conversations") { try BotSamples.checkConversations() },
        DecodeCheck("bots.pulse") { try BotSamples.checkPulse() },
        DecodeCheck("bots.teams") { try BotSamples.checkTeams() },
        DecodeCheck("bots.threads") { try BotSamples.checkThreads() },
        DecodeCheck("bots.state") { try BotSamples.checkState() },
        DecodeCheck("bots.messages") { try BotSamples.checkMessages() },
        DecodeCheck("bots.send") { try BotSamples.checkSend() },
        DecodeCheck("bots.queue") { try BotSamples.checkQueue() },
        DecodeCheck("bots.steer") { try BotSamples.checkSteerAndStop() },
        DecodeCheck("bots.cards") { try BotSamples.checkCards() },
        DecodeCheck("bots.inbox") { try BotSamples.checkInbox() },
        DecodeCheck("bots.notifications") { try BotSamples.checkNotifications() },
        DecodeCheck("bots.approvals") { try BotSamples.checkApprovals() },
        DecodeCheck("bots.rings") { try BotSamples.checkRings() },
        DecodeCheck("bots.packets") { try BotSamples.checkPackets() },
    ]
}
