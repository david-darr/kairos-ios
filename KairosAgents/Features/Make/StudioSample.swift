import Foundation

/// Made-up Content Studio data: three niches, five channels, a dozen posts. No real channels.
nonisolated struct SampleStudio: StudioProviding {
    func niches() -> [StudioNiche] {
        [
            StudioNiche(id: "n-bikes", name: "Bike care", slots: 2, score: 71.4),
            StudioNiche(id: "n-bakes", name: "Easy baking", slots: 1, score: 58.2),
            StudioNiche(id: "n-plants", name: "Small gardens", retired: true, slots: 1),
        ]
    }

    func channels() -> [StudioChannel] {
        [
            StudioChannel(id: "ch-trail", handle: "@trailtips", platform: .youtube, nicheID: "n-bikes", initials: "TT", hue: 0.08, pack: "Flat 2D explainer", narrator: "Iris", longPerWeek: 1, connection: "Connected", connectedAs: "Shop account", posts: 24, views: 48_200, follows: 610, averageView: 31),
            StudioChannel(id: "ch-spoke", handle: "@spokeshorts", platform: .tiktok, nicheID: "n-bikes", initials: "SP", hue: 0.55, pack: "Motion type (default)", connection: "Not connected", posts: 31, views: 92_400, follows: 1_250, averageView: 14),
            StudioChannel(id: "ch-crumb", handle: "@crumbclub", platform: .instagram, nicheID: "n-bakes", initials: "CC", hue: 0.92, pack: "Glossy 3D mascot", connection: "Connected", connectedAs: "Bakery page", posts: 12, views: 15_900, follows: 220, averageView: 11),
            StudioChannel(id: "ch-dough", handle: "@doughdaily", platform: .youtube, nicheID: "n-bakes", state: .paused, initials: "DD", hue: 0.33, warning: "YouTube warned @doughdaily: a reused audio claim on one video.", pack: "", connection: "Needs sign-in", posts: 6, views: 2_100, follows: 40, averageView: 22),
            StudioChannel(id: "ch-leaf", handle: "@leafcorner", platform: .youtube, nicheID: "n-plants", state: .archived, initials: "LC", hue: 0.7, pack: "Motion type (default)", connection: "Not connected", posts: 9, views: 3_300, follows: 55, averageView: 19),
        ]
    }

    func posts() -> [StudioPost] {
        [
            StudioPost(id: "p-chain", title: "Clean your chain in 60 seconds", channelID: "ch-trail", stage: .awaiting, publish: .awaiting, owner: "Producer", ageHours: 5, why: "Chain care questions doubled this month.", format: "Format: One fix, one minute (ported). Style pack: Flat 2D explainer.", caption: "A clean chain shifts better and lasts longer. Here is the one minute way.", script: "Most chains are dirty. Here is how to fix that in a minute. One: rag on the lower run...", tags: "bike care, chain, quick fix", nextStep: "You: approve or send back", checklist: []),
            StudioPost(id: "p-gears", title: "Why your gears skip", channelID: "ch-spoke", stage: .awaiting, publish: .awaiting, owner: "Producer", ageHours: 30, rejectedTimes: 2, why: "Skipping gears is the top search in the niche.", format: "Format: Myth or fact. Style pack: Motion type.", caption: "Skipping gears? It is usually one of three things.", script: "Your gears skip. Before you buy a new chain, check these three things...", tags: "gears, bike, tips", nextStep: "You: approve or send back"),
            StudioPost(id: "p-loaf", title: "No knead loaf, three ingredients", channelID: "ch-crumb", stage: .awaiting, publish: .awaiting, owner: "Producer", ageHours: 2, why: "Simple bread did well last week.", format: "Style pack: Glossy 3D mascot.", caption: "Three ingredients. No kneading. Warm bread by dinner.", script: "Flour, water, salt and a little yeast. That is it...", tags: "bread, baking, easy", nextStep: "You: approve or send back"),
            StudioPost(id: "p-lights", title: "Lights for winter rides", channelID: "ch-trail", stage: .approved, publish: .prepared, owner: "Publisher", ageHours: 8, why: "Days are getting shorter.", caption: "Be seen. Three lights that make winter rides safer.", script: "Winter is dark. Here is what to fit...", tags: "lights, winter, safety", scheduledDay: 3, scheduledTime: "18:00", nextStep: "You: open the upload page and press Publish", fillNote: "Kairos filled: Video, Title, Description, Tags, AI label. Not found on the page, do these yourself: Thumbnail.", checklist: SampleStudio.checklist(for: .youtube)),
            StudioPost(id: "p-tyre", title: "Tyre pressure, simply", channelID: "ch-spoke", stage: .approved, publish: .waitingForYou, owner: "You", ageHours: 20, caption: "Too soft, too hard, just right.", tags: "tyres, pressure", scheduledDay: 2, scheduledTime: "12:30", nextStep: "You: press Post on TikTok", fillNote: "Kairos filled: Video, Caption, AI label.", checklist: SampleStudio.checklist(for: .tiktok)),
            StudioPost(id: "p-scone", title: "Scones that rise", channelID: "ch-crumb", stage: .approved, publish: .approved, owner: "Publisher", ageHours: 4, caption: "Cold butter is the whole secret.", tags: "scones, baking", nextStep: "You: prepare it"),
            StudioPost(id: "p-brake", title: "Brake pads: when to swap", channelID: "ch-trail", stage: .posted, publish: .posted, owner: "You", ageHours: 70, caption: "Look for the groove.", tags: "brakes", posted: "Mon 09:30", link: "https://example.com/watch/brake", numbers: PostNumbers(views: 12_400, averageView: 34, likes: 820, comments: 41, shares: 66, follows: 120), numberSets: 3),
            StudioPost(id: "p-saddle", title: "Saddle height in one step", channelID: "ch-spoke", stage: .posted, publish: .posted, owner: "You", ageHours: 96, caption: "Heel on the pedal. That is it.", tags: "fit, saddle", posted: "Sun 17:00", link: "https://example.com/watch/saddle", numbers: PostNumbers(views: 34_100, averageView: 15, likes: 2_900, comments: 180, shares: 410, follows: 380, source: "tiktok page read"), numberSets: 2),
            StudioPost(id: "p-muffin", title: "Muffins in one bowl", channelID: "ch-crumb", stage: .posted, publish: .posted, owner: "You", ageHours: 120, caption: "One bowl, less washing up.", posted: "Sat 11:00", link: "https://example.com/watch/muffin", numbers: nil),
            StudioPost(id: "p-pump", title: "Pick the right pump", channelID: "ch-trail", stage: .rendering, publish: .drafted, owner: "Editor", ageHours: 14, expectedHours: 6, renderFailed: true, nextStep: "Team: render again"),
            StudioPost(id: "p-rust", title: "Stop rust before it starts", channelID: "ch-trail", stage: .scripting, publish: .drafted, owner: "Script Writer", ageHours: 3, nextStep: "Team: writing the script"),
            StudioPost(id: "p-icing", title: "Icing without a bag", channelID: "ch-crumb", stage: .topic, publish: .drafted, owner: "Researcher", ageHours: 1, why: "A topic the Researcher found. The Evaluator picks which ones get made."),
            StudioPost(id: "p-flat", title: "Flat on the road, what now", channelID: "ch-spoke", stage: .topic, publish: .drafted, owner: "Researcher", ageHours: 6),
            StudioPost(id: "p-crust", title: "Crispy crust every time", channelID: "ch-crumb", stage: .approved, publish: .failed, owner: "Publisher", ageHours: 10, caption: "Steam is the trick.", nextStep: "You: prepare again", fillNote: "Stopped: the upload page asked you to sign in."),
        ]
    }

    static func checklist(for platform: StudioPlatform) -> [ChecklistLine] {
        [
            ChecklistLine(text: "Video file", who: .filled),
            ChecklistLine(text: platform == .youtube ? "Title" : "Caption", who: .filled),
            ChecklistLine(text: "Description and tags", who: platform == .tiktok ? .kairos : .filled),
            ChecklistLine(text: "AI content label", who: .filled),
            ChecklistLine(text: "Thumbnail", who: .missing),
            ChecklistLine(text: "Press \(platform.postButton)", who: .you),
        ]
    }

    static let packs: [StudioPack] = [
        StudioPack(id: "pk-flat", name: "Flat 2D explainer", origin: "Starter pack", summary: "Clean flat shapes, round characters, calm cuts.", brief: "Flat colours from the warm palette. Round characters talk to camera. One idea per shot, cut on the beat, captions in sentence case.", facts: ["Look": "Flat 2D", "Characters": "Round family", "Pacing": "One idea per shot", "Captions": "On, sentence case", "Music and voice": "Warm bed, Iris narrates"], versions: [PackVersion(number: 1, status: .approved, note: "First version."), PackVersion(number: 2, status: .waiting, note: "Softer colours, slower cuts.", sampleNotes: ["Captions sit inside the safe area.", "One shot runs 0.4 s long."])]),
        StudioPack(id: "pk-glossy", name: "Glossy 3D mascot", origin: "Made from a written brief", summary: "A shiny mascot on a pastel stage.", brief: "A small glossy mascot on a pedestal, pastel sets, slow push-ins.", facts: ["Look": "Glossy 3D", "3D renderer": "three.js, built into Kairos", "Studio sets": "Peach, mint, sky", "Camera and cuts": "Slow push-ins"], versions: [PackVersion(number: 1, status: .approved, note: "Made from the brief.")]),
        StudioPack(id: "pk-block", name: "Blocky voxel 3D", origin: "Duplicated", summary: "Toy blocks and bright worlds.", brief: "Pastel toy blocks, wide shots, a bouncy pace.", facts: ["Look": "Voxel 3D", "Audience": "This look draws children. Check Made for kids.", "Worlds": "Meadow, village"], versions: [PackVersion(number: 1, status: .draft, note: "Copy of the starter.")]),
    ]

    static let characters: [StudioCharacter] = [
        StudioCharacter(id: "cr-pip", name: "Pip", family: "Round", versions: [CharacterVersion(number: 1, status: .approved, note: "First sheet.", body: 0xE8C39E, accent: 0xC9933A), CharacterVersion(number: 2, status: .waiting, note: "Adds a scarf.", body: 0xE8C39E, accent: 0xC9933A, accessory: "Scarf")]),
        StudioCharacter(id: "cr-bolt", name: "Bolt", family: "Square", versions: [CharacterVersion(number: 1, status: .draft, note: "New character.", body: 0xB9D2E3, accent: 0x4F84A8, accessory: "Antenna")]),
    ]

    static let plans: [StudioPlan] = [
        StudioPlan(id: "pl-tour", title: "A full tune-up, start to finish", channelID: "ch-trail", chapters: ["00:00 What you need", "01:05 Clean and check", "03:40 Brakes", "06:10 Gears", "08:30 Test ride"], shots: ["Wide: the bike on a stand", "Close: degreaser on the chain", "Medium: wheel off, pads out", "Close: the barrel adjuster", "Wide: riding away"]),
    ]

    static let formats: [StudioFormat] = [
        StudioFormat(id: "f-onefix", name: "One fix, one minute", beats: ["Hook: the problem", "The fix in three steps", "Before and after", "One line to remember"], length: "45 seconds to 2 minutes", audience: "18 to 34, people who fix their own things, on YouTube. Why they watch: a quick win.", seenIn: "Three repair channels", evidence: ["210K views, 12 days old when seen. Checked Mon 3 Nov.", "88K views, 30 days old when seen. Checked Mon 3 Nov."], ports: [
            StudioPort(id: "pt-1", from: "Home repair", to: "Bike care", status: "Accepted", reason: "Same quick-win promise, a fresh subject.", changes: ["New premise: one bike fix a day", "Subject: bike parts", "Style pack: Flat 2D explainer", "Example title: Clean your chain in 60 seconds"], checks: [StudioCheck(name: "Audience match", result: "Passed"), StudioCheck(name: "Distance from the source", result: "Passed"), StudioCheck(name: "Cost to make", result: "Passed"), StudioCheck(name: "Series rule", result: "Warning")], cost: "About 4 planning units, the cheapest way to make it.", verdict: "Accepted: a clear fit with room to grow."),
            StudioPort(id: "pt-2", from: "Home repair", to: "Easy baking", status: "With the Evaluator", reason: "Kitchen fixes may fit the baking crowd.", changes: ["New premise: one baking fix", "Mascot: Pip"], checks: [], cost: "About 6 planning units, 1.5 times the cheapest pack that could make it.", verdict: "Not checked yet."),
        ]),
        StudioFormat(id: "f-myth", name: "Myth or fact", beats: ["The myth", "The test", "The answer"], length: "about 1 minute", audience: "Curious viewers on TikTok. Why they watch: to be right.", seenIn: "Two science channels", evidence: ["1.2M views, 8 days old when seen. Checked Tue 4 Nov."], ports: []),
    ]

    static let decisions: [StudioDecision] = [
        StudioDecision(id: "d-retire", title: "Retire channel @leafcorner", numbers: "score 22.0 · team median 58.2 · 9 posts scored · 60 days of data · 1 slot freed", status: .needsYou),
        StudioDecision(id: "d-add", title: "Add niche Commuter tips", numbers: "3 slots after · 2 of 3 niches live", evidence: "Source: search trends. Signal: steady rise for 8 weeks.", status: .producer),
        StudioDecision(id: "d-promote", title: "Promote format One fix, one minute", numbers: "score 74.1 · 12 posts scored", status: .confirmed),
    ]

    static let templates: [StudioTemplate] = [
        StudioTemplate(id: "t-content", name: "Content Studio team", detail: "Seven bots and the Producer. Researches, writes, renders and prepares short videos.", bots: ["Producer", "Researcher", "Evaluator", "Script Writer", "Editor", "Publisher", "Executor"], added: true),
        StudioTemplate(id: "t-long", name: "Long video crew", detail: "Plans and renders one longer video a week, with chapters.", bots: ["Producer", "Script Writer", "Editor"]),
        StudioTemplate(id: "t-shop", name: "Shop promo pair", detail: "Two bots that turn new stock into short posts.", bots: ["Script Writer", "Publisher"]),
    ]

    static let scores: [StudioScore] = [
        StudioScore(name: "Bike care", score: 71.4, detail: "18 posts scored over 30 days"),
        StudioScore(name: "Easy baking", score: 58.2, detail: "9 posts scored over 30 days"),
        StudioScore(name: "Small gardens", score: nil, detail: "Needs more data", tag: "Retired"),
    ]

    static let formatScores: [StudioScore] = [
        StudioScore(name: "One fix, one minute", score: 74.1, detail: "12 posts scored over 30 days", tag: "Default"),
        StudioScore(name: "Myth or fact", score: 61.0, detail: "6 posts scored over 21 days"),
    ]

    static let packScores: [StudioScore] = [
        StudioScore(name: "Flat 2D explainer", score: 69.8, detail: "15 posts scored over 30 days"),
        StudioScore(name: "Glossy 3D mascot", score: 55.5, detail: "7 posts scored over 21 days"),
        StudioScore(name: "Blocky voxel 3D", score: nil, detail: "Needs more data", tag: "No card"),
    ]

    static let report = [
        "Posted 6 videos across 3 channels this week.",
        "Views are up 18 percent on last week, led by @spokeshorts.",
        "Two posts were sent back; both are redrafted.",
        "@doughdaily is paused by a platform warning.",
        "Spend this month: 14 of 40 dollars.",
        "Next week: one long video plan waits for your OK.",
    ]
}
