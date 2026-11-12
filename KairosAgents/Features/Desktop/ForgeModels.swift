import SwiftUI

// MARK: - Plain data

nonisolated struct PCStatus: Hashable, Sendable {
    var name: String
    var online: Bool
    var version: String
    var lastSeen: String
    var asleep: Bool
}

nonisolated struct RunningApp: Identifiable, Hashable, Sendable {
    let id: String
    var port: Int
    var sessionID: String
    var title: String
    var command: String
}

nonisolated struct ForgeProject: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var path: String
    var branch: String
    var lastOpened: String
}

nonisolated enum ForgeMode: String, CaseIterable, Hashable, Sendable {
    case build = "Build", plan = "Plan"

    var explain: String {
        switch self {
        case .build: "Build: the agent can edit files and run commands."
        case .plan: "Plan: the agent reads and proposes a plan. It changes nothing."
        }
    }
}

nonisolated enum ForgeAccess: String, CaseIterable, Hashable, Sendable {
    case supervised = "Supervised", full = "Full access"

    var explain: String {
        switch self {
        case .supervised: "Asks you before edits and commands."
        case .full: "Edits and runs commands without asking."
        }
    }
}

nonisolated enum ForgeLocation: String, CaseIterable, Hashable, Sendable {
    case worktree = "New worktree", branch = "Existing branch", inPlace = "In place"

    var explain: String {
        switch self {
        case .worktree: "A separate copy on a new branch. Your folder stays untouched until you merge."
        case .branch: "Work on a branch you already have, in its own copy."
        case .inPlace: "In place: changes affect your project folder directly."
        }
    }
}

nonisolated enum ForgeState: Hashable, Sendable {
    case working, needsYou, done, idle

    var label: String {
        switch self {
        case .working: "Working"
        case .needsYou: "Waiting for you"
        case .done: "Done"
        case .idle: "Idle"
        }
    }
}

nonisolated enum DiffKind: Hashable, Sendable { case context, add, remove }

nonisolated struct DiffLine: Identifiable, Hashable, Sendable {
    let id = UUID()
    var kind: DiffKind
    var old: Int?
    var new: Int?
    var text: String
}

nonisolated struct DiffHunk: Identifiable, Hashable, Sendable {
    let id = UUID()
    var header: String
    var lines: [DiffLine]
    var added: Int { lines.filter { $0.kind == .add }.count }
    var removed: Int { lines.filter { $0.kind == .remove }.count }
}

nonisolated enum ChangeMark: String, Hashable, Sendable {
    case modified = "M", added = "A", deleted = "D", untracked = "U"

    var word: String {
        switch self {
        case .modified: "Modified"
        case .added: "Added"
        case .deleted: "Deleted"
        case .untracked: "New, not tracked"
        }
    }
}

nonisolated struct FileChange: Identifiable, Hashable, Sendable {
    var id: String { path }
    var path: String
    var mark: ChangeMark
    var hunks: [DiffHunk]
    var binary = false
    var added: Int { hunks.reduce(0) { $0 + $1.added } }
    var removed: Int { hunks.reduce(0) { $0 + $1.removed } }
    var name: String { path.split(separator: "/").last.map(String.init) ?? path }
}

nonisolated enum StepKind: Hashable, Sendable {
    case read, edit, command, search

    var symbol: String {
        switch self {
        case .read: "doc.text"
        case .edit: "pencil"
        case .command: "terminal"
        case .search: "magnifyingglass"
        }
    }
}

nonisolated struct ForgeStep: Identifiable, Hashable, Sendable {
    let id = UUID()
    var kind: StepKind
    var summary: String
    var output: String? = nil
    var failed = false
    var file: String? = nil
}

nonisolated struct PermissionAsk: Hashable, Sendable {
    var title: String
    var tool: String
    var target: String
}

nonisolated enum TurnReview: Hashable, Sendable { case open, kept, undone }

nonisolated struct ForgeTurn: Identifiable, Hashable, Sendable {
    let id: String
    var prompt: String
    var reply: String
    var steps: [ForgeStep]
    var duration: String
    var files: [String] = []
    var added = 0
    var removed = 0
    var review: TurnReview = .open
    var ask: PermissionAsk? = nil
    var running = false
    var afterBackground = false
}

nonisolated struct GitInfo: Hashable, Sendable {
    var branch: String
    var upstream: String?
    var ahead: Int
    var behind: Int
    var staged: [String]
    var unstaged: [String]
    var branches: [String]
}

nonisolated struct ForgeSessionInfo: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var projectID: String
    var branch: String?
    var mode: ForgeMode
    var access: ForgeAccess
    var agent: String
    var model: String
    var effort: String
    var state: ForgeState
    var updated: String
    var today: Bool
    var turns: [ForgeTurn]
    var changes: [FileChange]
    var git: GitInfo
    var ended = false
    var queued: [String] = []
    var background: String? = nil

    var added: Int { changes.reduce(0) { $0 + $1.added } }
    var removed: Int { changes.reduce(0) { $0 + $1.removed } }
    var placeLabel: String { branch ?? "In place" }
}

nonisolated struct FileNode: Identifiable, Hashable, Sendable {
    var id: String { path }
    var name: String
    var path: String
    var children: [FileNode]? = nil
    var mark: ChangeMark? = nil
    var size: String = ""
}

nonisolated struct RankedRow: Identifiable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var commits: Int
    var added: Int
    var removed: Int
}

nonisolated struct LanguageShare: Identifiable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var percent: Double
    var colorHex: UInt32
}

nonisolated struct RepoStats: Hashable, Sendable {
    var commits: Int
    var commitsDelta: Int
    var contributors: Int
    var contributorsDelta: Int
    var added: Int
    var addedDelta: Int
    var removed: Int
    var removedDelta: Int
    var ageDays: Int
    var first: String
    var latest: String
    var history: [Int]
    var historyLabel: String
    var languages: [LanguageShare]
    /// Seven weekdays, 24 hours each.
    var rhythm: [[Int]]
    var files: [RankedRow]
    var people: [RankedRow]
}

nonisolated enum ForgeEndChoice: Hashable, Sendable { case merge, keepBranch, discard, keepAndLeave }

nonisolated enum ForgeWidget: String, CaseIterable, Hashable, Sendable {
    case working = "Working now"
    case services = "Running services"
    case git = "Git activity"
    case recent = "Recent projects"
    case lifespan = "Repo lifespan"
}

// MARK: - Sample data

nonisolated enum ForgeSample {
    static let pc = PCStatus(name: "Studio PC", online: true, version: "Kairos 2.3.0", lastSeen: "now", asleep: false)

    static let projects = [
        ForgeProject(id: "p-shop", name: "shop-site", path: "C:/Projects/shop-site", branch: "main", lastOpened: "Today"),
        ForgeProject(id: "p-api", name: "inventory-api", path: "C:/Projects/inventory-api", branch: "main", lastOpened: "Yesterday"),
        ForgeProject(id: "p-notes", name: "recipe-notes", path: "C:/Projects/recipe-notes", branch: "main", lastOpened: "Mon"),
    ]

    static let apps = [
        RunningApp(id: "a-1", port: 5173, sessionID: "s-layout", title: "Mobile layout prototype", command: "npm run dev -- --port {port}"),
        RunningApp(id: "a-2", port: 8080, sessionID: "s-alerts", title: "Add stock alerts", command: "python -m app --port {port}"),
    ]

    /// Commits per day for the last 14 days.
    static let activity = [2, 0, 3, 5, 1, 0, 0, 4, 6, 2, 3, 0, 1, 5]
    static let activityAdded = [120, 0, 210, 380, 40, 0, 0, 260, 512, 90, 140, 0, 30, 412]
    static let activityRemoved = [30, 0, 44, 120, 12, 0, 0, 80, 160, 22, 36, 0, 8, 36]

    static let layoutDiff: [FileChange] = [
        FileChange(path: "src/styles/layout.css", mark: .modified, hunks: [
            DiffHunk(header: "@@ -12,9 +12,16 @@ .page", lines: [
                DiffLine(kind: .context, old: 12, new: 12, text: ".page {"),
                DiffLine(kind: .remove, old: 13, new: nil, text: "  display: grid;"),
                DiffLine(kind: .remove, old: 14, new: nil, text: "  grid-template-columns: 240px 1fr;"),
                DiffLine(kind: .add, old: nil, new: 13, text: "  display: flex;"),
                DiffLine(kind: .add, old: nil, new: 14, text: "  flex-direction: column;"),
                DiffLine(kind: .add, old: nil, new: 15, text: "  gap: 16px;"),
                DiffLine(kind: .context, old: 15, new: 16, text: "  padding: 24px;"),
                DiffLine(kind: .context, old: 16, new: 17, text: "}"),
                DiffLine(kind: .context, old: 17, new: 18, text: ""),
                DiffLine(kind: .add, old: nil, new: 19, text: "@media (min-width: 900px) {"),
                DiffLine(kind: .add, old: nil, new: 20, text: "  .page { display: grid; grid-template-columns: 240px 1fr; }"),
                DiffLine(kind: .add, old: nil, new: 21, text: "}"),
            ]),
            DiffHunk(header: "@@ -40,6 +48,8 @@ .product-card", lines: [
                DiffLine(kind: .context, old: 40, new: 48, text: ".product-card {"),
                DiffLine(kind: .remove, old: 41, new: nil, text: "  width: 320px;"),
                DiffLine(kind: .add, old: nil, new: 49, text: "  width: 100%;"),
                DiffLine(kind: .add, old: nil, new: 50, text: "  max-width: 320px;"),
                DiffLine(kind: .add, old: nil, new: 51, text: "  border-radius: 14px;"),
                DiffLine(kind: .context, old: 42, new: 52, text: "}"),
            ]),
        ]),
        FileChange(path: "src/components/NavBar.tsx", mark: .modified, hunks: [
            DiffHunk(header: "@@ -1,8 +1,14 @@", lines: [
                DiffLine(kind: .context, old: 1, new: 1, text: "import { useState } from 'react'"),
                DiffLine(kind: .add, old: nil, new: 2, text: "import { MenuButton } from './MenuButton'"),
                DiffLine(kind: .context, old: 2, new: 3, text: ""),
                DiffLine(kind: .context, old: 3, new: 4, text: "export function NavBar() {"),
                DiffLine(kind: .add, old: nil, new: 5, text: "  const [open, setOpen] = useState(false)"),
                DiffLine(kind: .remove, old: 4, new: nil, text: "  return <nav className=\"nav\">{links}</nav>"),
                DiffLine(kind: .add, old: nil, new: 6, text: "  return ("),
                DiffLine(kind: .add, old: nil, new: 7, text: "    <nav className={open ? 'nav open' : 'nav'}>"),
                DiffLine(kind: .add, old: nil, new: 8, text: "      <MenuButton onPress={() => setOpen(!open)} />"),
                DiffLine(kind: .add, old: nil, new: 9, text: "      {links}"),
                DiffLine(kind: .add, old: nil, new: 10, text: "    </nav>"),
                DiffLine(kind: .add, old: nil, new: 11, text: "  )"),
                DiffLine(kind: .context, old: 5, new: 12, text: "}"),
            ]),
        ]),
        FileChange(path: "src/components/MenuButton.tsx", mark: .added, hunks: [
            DiffHunk(header: "@@ -0,0 +1,9 @@", lines: [
                DiffLine(kind: .add, old: nil, new: 1, text: "type Props = { onPress: () => void }"),
                DiffLine(kind: .add, old: nil, new: 2, text: ""),
                DiffLine(kind: .add, old: nil, new: 3, text: "export function MenuButton({ onPress }: Props) {"),
                DiffLine(kind: .add, old: nil, new: 4, text: "  return ("),
                DiffLine(kind: .add, old: nil, new: 5, text: "    <button aria-label=\"Menu\" onClick={onPress}>"),
                DiffLine(kind: .add, old: nil, new: 6, text: "      <span className=\"bars\" />"),
                DiffLine(kind: .add, old: nil, new: 7, text: "    </button>"),
                DiffLine(kind: .add, old: nil, new: 8, text: "  )"),
                DiffLine(kind: .add, old: nil, new: 9, text: "}"),
            ]),
        ]),
        FileChange(path: "public/hero-old.png", mark: .deleted, hunks: [], binary: true),
    ]

    static let imageDiff: [FileChange] = [
        FileChange(path: "src/lib/images.ts", mark: .modified, hunks: [
            DiffHunk(header: "@@ -3,7 +3,9 @@ export function load", lines: [
                DiffLine(kind: .context, old: 3, new: 3, text: "export function load(src: string) {"),
                DiffLine(kind: .remove, old: 4, new: nil, text: "  return fetch(src).then(r => r.blob())"),
                DiffLine(kind: .add, old: nil, new: 4, text: "  const cached = cache.get(src)"),
                DiffLine(kind: .add, old: nil, new: 5, text: "  if (cached) return Promise.resolve(cached)"),
                DiffLine(kind: .add, old: nil, new: 6, text: "  return fetch(src).then(r => r.blob()).then(b => cache.set(src, b))"),
                DiffLine(kind: .context, old: 5, new: 7, text: "}"),
            ]),
        ]),
    ]

    static let alertsDiff: [FileChange] = [
        FileChange(path: "app/alerts.py", mark: .added, hunks: [
            DiffHunk(header: "@@ -0,0 +1,7 @@", lines: [
                DiffLine(kind: .add, old: nil, new: 1, text: "def low_stock(items, limit=5):"),
                DiffLine(kind: .add, old: nil, new: 2, text: "    \"\"\"Items at or under the limit.\"\"\""),
                DiffLine(kind: .add, old: nil, new: 3, text: "    return [i for i in items if i.count <= limit]"),
                DiffLine(kind: .add, old: nil, new: 4, text: ""),
                DiffLine(kind: .add, old: nil, new: 5, text: "def message(item):"),
                DiffLine(kind: .add, old: nil, new: 6, text: "    return f\"{item.name} is low: {item.count} left\""),
                DiffLine(kind: .add, old: nil, new: 7, text: ""),
            ]),
        ]),
    ]

    static let sessions: [ForgeSessionInfo] = [
        ForgeSessionInfo(
            id: "s-layout", title: "Mobile layout prototype", projectID: "p-shop", branch: "kairos/mobile-layout",
            mode: .build, access: .supervised, agent: "Claude Code", model: "Claude Opus", effort: "High",
            state: .needsYou, updated: "2m", today: true,
            turns: [
                ForgeTurn(
                    id: "t1",
                    prompt: "Make the shop pages work on phones. The product grid should stack and the nav needs a menu button.",
                    reply: "The page grid now stacks under 900 pixels and the product cards fill the width. I added a MenuButton and wired it into the NavBar.",
                    steps: [
                        ForgeStep(kind: .read, summary: "Read src/styles/layout.css"),
                        ForgeStep(kind: .read, summary: "Read src/components/NavBar.tsx"),
                        ForgeStep(kind: .edit, summary: "Edited src/styles/layout.css", file: "src/styles/layout.css"),
                        ForgeStep(kind: .edit, summary: "Created src/components/MenuButton.tsx", file: "src/components/MenuButton.tsx"),
                        ForgeStep(kind: .edit, summary: "Edited src/components/NavBar.tsx", file: "src/components/NavBar.tsx"),
                        ForgeStep(kind: .command, summary: "npm run lint", output: "0 problems found"),
                    ],
                    duration: "Worked 3m 12s", files: ["src/styles/layout.css", "src/components/MenuButton.tsx", "src/components/NavBar.tsx"], added: 27, removed: 4
                ),
                ForgeTurn(
                    id: "t2",
                    prompt: "Remove the old hero image and run the build.",
                    reply: "",
                    steps: [
                        ForgeStep(kind: .search, summary: "Searched for hero-old.png", output: "1 match in public/"),
                        ForgeStep(kind: .command, summary: "git rm public/hero-old.png"),
                    ],
                    duration: "Working 41s",
                    ask: PermissionAsk(title: "Run a command?", tool: "Shell", target: "git rm public/hero-old.png"),
                    running: true
                ),
            ],
            changes: layoutDiff,
            git: GitInfo(branch: "kairos/mobile-layout", upstream: nil, ahead: 2, behind: 0, staged: [], unstaged: layoutDiff.map(\.path), branches: ["main", "kairos/mobile-layout", "kairos/image-cache"])
        ),
        ForgeSessionInfo(
            id: "s-images", title: "Faster image loading", projectID: "p-shop", branch: "kairos/image-cache",
            mode: .build, access: .supervised, agent: "Claude Code", model: "Claude Sonnet", effort: "Medium",
            state: .done, updated: "1h", today: true,
            turns: [
                ForgeTurn(
                    id: "t1", prompt: "Product images load slowly. Cache them in memory.",
                    reply: "Images now come from a small in-memory cache after the first load. The second visit to a page skips the network.",
                    steps: [
                        ForgeStep(kind: .read, summary: "Read src/lib/images.ts"),
                        ForgeStep(kind: .edit, summary: "Edited src/lib/images.ts", file: "src/lib/images.ts"),
                        ForgeStep(kind: .command, summary: "npm test", output: "12 passed"),
                    ],
                    duration: "Worked 1m 50s", files: ["src/lib/images.ts"], added: 3, removed: 1, review: .kept
                ),
            ],
            changes: imageDiff,
            git: GitInfo(branch: "kairos/image-cache", upstream: "origin/kairos/image-cache", ahead: 0, behind: 1, staged: ["src/lib/images.ts"], unstaged: [], branches: ["main", "kairos/image-cache"])
        ),
        ForgeSessionInfo(
            id: "s-alerts", title: "Add stock alerts", projectID: "p-api", branch: "kairos/stock-alerts",
            mode: .build, access: .full, agent: "Codex", model: "GPT-6.1 Sol", effort: "Medium",
            state: .working, updated: "now", today: true,
            turns: [
                ForgeTurn(
                    id: "t1", prompt: "Add a low stock alert that lists items with five or fewer left.",
                    reply: "",
                    steps: [
                        ForgeStep(kind: .read, summary: "Read app/models.py"),
                        ForgeStep(kind: .edit, summary: "Created app/alerts.py", file: "app/alerts.py"),
                        ForgeStep(kind: .command, summary: "pytest -q", output: "....F\n1 failed, 4 passed", failed: true),
                    ],
                    duration: "Working 2m 05s", running: true
                ),
            ],
            changes: alertsDiff,
            git: GitInfo(branch: "kairos/stock-alerts", upstream: nil, ahead: 0, behind: 0, staged: [], unstaged: ["app/alerts.py"], branches: ["main", "kairos/stock-alerts"]),
            background: "Running the test suite"
        ),
        ForgeSessionInfo(
            id: "s-checkout", title: "Fix the checkout total", projectID: "p-shop", branch: nil,
            mode: .plan, access: .supervised, agent: "Claude Code", model: "Claude Sonnet", effort: "Low",
            state: .idle, updated: "3d", today: false,
            turns: [
                ForgeTurn(
                    id: "t1", prompt: "The checkout total is off by the delivery fee sometimes. Find out why.",
                    reply: "The fee is added twice when a coupon is applied after choosing delivery. Plan: compute the fee once in cartTotal, and add a test for coupon then delivery.",
                    steps: [ForgeStep(kind: .read, summary: "Read src/cart/total.ts"), ForgeStep(kind: .search, summary: "Searched for deliveryFee", output: "4 matches")],
                    duration: "Worked 58s", review: .kept
                ),
            ],
            changes: [],
            git: GitInfo(branch: "main", upstream: "origin/main", ahead: 0, behind: 0, staged: [], unstaged: [], branches: ["main"])
        ),
    ]

    static let tree: [FileNode] = [
        FileNode(name: "public", path: "public", children: [
            FileNode(name: "favicon.svg", path: "public/favicon.svg", size: "1 KB"),
            FileNode(name: "hero-old.png", path: "public/hero-old.png", mark: .deleted, size: "240 KB"),
        ]),
        FileNode(name: "src", path: "src", children: [
            FileNode(name: "components", path: "src/components", children: [
                FileNode(name: "MenuButton.tsx", path: "src/components/MenuButton.tsx", mark: .added, size: "1 KB"),
                FileNode(name: "NavBar.tsx", path: "src/components/NavBar.tsx", mark: .modified, size: "2 KB"),
                FileNode(name: "ProductCard.tsx", path: "src/components/ProductCard.tsx", size: "3 KB"),
            ]),
            FileNode(name: "lib", path: "src/lib", children: [
                FileNode(name: "images.ts", path: "src/lib/images.ts", size: "1 KB"),
            ]),
            FileNode(name: "styles", path: "src/styles", children: [
                FileNode(name: "layout.css", path: "src/styles/layout.css", mark: .modified, size: "4 KB"),
            ]),
            FileNode(name: "main.tsx", path: "src/main.tsx", size: "1 KB"),
        ]),
        FileNode(name: "package.json", path: "package.json", size: "1 KB"),
        FileNode(name: "README.md", path: "README.md", size: "2 KB"),
    ]

    static func fileText(_ path: String) -> String {
        switch path {
        case "src/components/NavBar.tsx":
            return """
            import { useState } from 'react'
            import { MenuButton } from './MenuButton'

            export function NavBar() {
              const [open, setOpen] = useState(false)
              return (
                <nav className={open ? 'nav open' : 'nav'}>
                  <MenuButton onPress={() => setOpen(!open)} />
                  {links}
                </nav>
              )
            }
            """
        case "src/components/MenuButton.tsx":
            return """
            type Props = { onPress: () => void }

            export function MenuButton({ onPress }: Props) {
              return (
                <button aria-label="Menu" onClick={onPress}>
                  <span className="bars" />
                </button>
              )
            }
            """
        case "README.md":
            return """
            # shop-site

            The website for a small bike shop.

            Run it with `npm run dev`, then open the address it prints.
            """
        case "package.json":
            return """
            {
              "name": "shop-site",
              "private": true,
              "scripts": {
                "dev": "vite",
                "build": "vite build",
                "test": "vitest run"
              }
            }
            """
        default:
            return """
            .page {
              display: flex;
              flex-direction: column;
              gap: 16px;
              padding: 24px;
            }

            @media (min-width: 900px) {
              .page { display: grid; grid-template-columns: 240px 1fr; }
            }

            .product-card {
              width: 100%;
              max-width: 320px;
              border-radius: 14px;
            }
            """
        }
    }

    static let repo = RepoStats(
        commits: 214, commitsDelta: 18, contributors: 3, contributorsDelta: 1,
        added: 18_420, addedDelta: 1_240, removed: 6_310, removedDelta: -220,
        ageDays: 162, first: "Jun 3", latest: "Today",
        history: [4, 9, 12, 7, 15, 22, 18, 11, 25, 30, 19, 26, 33, 21, 28, 17],
        historyLabel: "Every 10 days",
        languages: [
            LanguageShare(name: "TypeScript", percent: 48.2, colorHex: Palette.botPowder),
            LanguageShare(name: "CSS", percent: 21.6, colorHex: Palette.botRose),
            LanguageShare(name: "HTML", percent: 12.4, colorHex: Palette.botSand),
            LanguageShare(name: "JSON", percent: 9.3, colorHex: Palette.botSage),
            LanguageShare(name: "Markdown", percent: 8.5, colorHex: Palette.botLilac),
        ],
        rhythm: (0..<7).map { day in
            (0..<24).map { hour in
                let work = (9...18).contains(hour) && day < 5
                let evening = (20...23).contains(hour)
                return work ? (hour * 7 + day * 3) % 6 + 1 : (evening ? (hour + day) % 3 : 0)
            }
        },
        files: [
            RankedRow(name: "src/styles/layout.css", commits: 31, added: 820, removed: 410),
            RankedRow(name: "src/components/NavBar.tsx", commits: 22, added: 340, removed: 190),
            RankedRow(name: "src/cart/total.ts", commits: 17, added: 260, removed: 120),
            RankedRow(name: "package.json", commits: 14, added: 48, removed: 30),
        ],
        people: [
            RankedRow(name: "You", commits: 120, added: 9_800, removed: 3_200),
            RankedRow(name: "Kairos agents", commits: 86, added: 8_100, removed: 2_900),
            RankedRow(name: "Shop helper", commits: 8, added: 520, removed: 210),
        ]
    )

    static let terminalStart = """
    PS C:/Projects/shop-site> npm run dev
    > shop-site@0.4.0 dev
    > vite --port 5173

      VITE ready in 412 ms
      Local:   http://localhost:5173/
    """

    static let appLogs = [
        "[09:41:02] vite v6 dev server running",
        "[09:41:02] Local: http://localhost:5173/",
        "[09:41:15] page reload src/styles/layout.css",
        "[09:41:16] hmr update /src/components/NavBar.tsx",
        "[09:42:03] GET /products 200 in 18 ms",
        "[09:42:04] GET /images/bike-red.jpg 200 in 6 ms",
    ]
}
