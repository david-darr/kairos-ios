# Developer guide

Kairos Agents is the free iPhone app for [Kairos](https://www.kairos-agents.com/), the open-source desktop AI app. The phone is a remote: the person's own desktop is the brain and the server. The goal is a ground-up native app, App Store quality: liquid glass in the Kairos colours, real motion everywhere, and every desktop feature reachable from the phone.

Read this whole file before writing code.

## Hard rules

- **Public repository.** No secret, key, token, personal name, email, private host or real person's data, in code, comments, sample data or commit messages. Sample content is made up and generic (a bike shop, a report due Friday).
- **Nobody compiles locally.** There is no Mac. GitHub Actions is the compiler (see "The build loop"). Write Swift you are sure of; check an API you are unsure of before using it.
- **Stay in your area.** Each area owns its folders (table below). Do not edit files you do not own. If you need a change in a shared file, write the request in your final report instead.
- **No dead controls.** Every button does something real on the sample data (changes state, opens a screen, opens a sheet) or it is not drawn. A screen that cannot work until the desktop is connected says so in one plain sentence.
- **Plain copy.** Short, direct, no jargon, no em-dashes, no exclamation marks. Sentence case. Say what happened and what to do.
- **Never drop a feature.** The checklist for each area is the feature inventory (your brief names the section). Record what you covered in `docs/coverage/<area>.md`: one line per inventory feature with its screen, or the honest reason it is not there yet.
- **Kip is never redrawn.** Use `Mascot` and `BotFace`. Do not change `Design/Mascot.swift`.

## Project facts

- SwiftUI only, iOS 26 minimum, iPhone, portrait. Swift 5 language mode with main-actor default isolation: mark plain data types `nonisolated` (see `Data/Models.swift`).
- `project.yml` is turned into the Xcode project by XcodeGen on the runner. Every `.swift` file under `KairosAgents/` is compiled; no project file to edit.
- Fonts: Jost (interface) and Cormorant Garamond Italic (names, big moments), through `KFont`.
- A web view is allowed only where the content itself is web content: a custom tab's HTML, a design's HTML, the remote desktop browser.

## The design system (use it; do not restyle around it)

All in `KairosAgents/Design/`.

| Need | Use |
|---|---|
| Colours | `Palette.ground`, `.ink`, `.inkDim`, `.inkFaint`, `.gold`, `.goldText`, `.onGold`, `.surface`, `.surfaceRaised`, `.surface2`, `.line`, `.working`, `.success`, `.danger`. Never a raw colour for interface chrome. |
| Type | `KFont.ui(size, .regular/.medium/.semibold, relativeTo:)`, `KFont.display(size)` for names and big titles, `KFont.label` with `SectionLabel` for small capital labels |
| A screen | `.kScreen()` on the root (ground behind, system bar hidden). Draw your own header in `.safeAreaInset(edge: .top)` with `.background { HeaderFade() }` |
| Back / round buttons | `GlassIconButton(symbol:label:action:)` |
| Real glass (chrome only: bars, round buttons, pills, composers) | `.kGlass(Capsule())`, `.kGlass(RoundedRectangle(cornerRadius: 24, style: .continuous))` |
| Cards and rows inside content | `.kCard(radius:raised:)`, `GroupRow`, `EntryRow`, `Chip`, `SectionLabel` |
| Segmented choice | `GlassSwitch(items:selection:title:)` (hugs its items) |
| Sheets | `.kSheet()` for full height, `FittedSheet { ... }` for a sheet as tall as its content. Leave about 30 points under the grab bar |
| Buttons | `GoldButton` (the one main action), `QuietButton`, any label with `.buttonStyle(PressStyle())` |
| Motion | `Motion.snappy`, `.bouncy`, `.sheet`, `.gentle`; `.arrives(index)` so rows come in one after another; `.contentTransition(.symbolEffect(.replace))`, `.numericText()` |
| Touch | `Haptics.tap()`, `.select()`, `.success()`, `.thud()` |
| Faces | `BotFace(bot:size:showStatus:blinks:)`, `Mascot(...)` |
| Running / status | `PulsingDot`, `StatusDot`, `LevelBars` |
| A short message above the tab bar | `chrome.say("...")` (`@Environment(ChromeState.self)`) |
| Going somewhere | `@Environment(AppRouter.self)`: `router.push(.bot(id))`, `router.open(area)`, `router.sheet = .search` |

Patterns to copy: `Home/HomeView.swift` (a tab root with a header and a scrolling list that shrinks the tab bar with `.shrinksBar(chrome)`), `Chat/BotChatView.swift` (a pushed screen with its own header and a composer), `Chat/ChatSheets.swift` (sheets), `Features/Bots/BotPanelView.swift` (a full-screen cover with a switch).

Inside your area, navigate with your own route type: `NavigationLink(value: MyRoute.x)` plus `.navigationDestination(for: MyRoute.self)` on your root. You do not need to touch the shell.

Touch targets are at least 44 points. Every icon-only control has an `accessibilityLabel`. Respect Reduce Motion (`@Environment(\.accessibilityReduceMotion)`) for anything that loops. Both looks must work: Night (dark) and Light.

## Areas and ownership

| Area | Owns |
|---|---|
| Shell (lead) | `App/`, `Shell/` except `SearchView.swift`, `Design/`, `Data/`, `Features/Library/LibraryView.swift`, `project.yml`, `Tools/`, `.github/`, `docs/DEV-GUIDE.md`, `docs/PHONE-API.md` |
| Home and chats | `Home/`, `Chat/`, `Onboarding/ConnectView.swift`, `Net/` (new) |
| Bots | `Features/Bots/` |
| Library files | `Features/Library/Files/` (Files with the Vault, Notes) |
| Library planner | `Features/Library/Planner/` (Calendar, Mail, Tasks) |
| Make | `Features/Make/` |
| Desktop | `Features/Desktop/` |
| You | `Features/You/`, `Shell/SearchView.swift`, `Onboarding/OnboardingFlow.swift` |
| Native | `Native/`, `KairosWidgets/` (new), `project-widgets.yml` (new) |
| Relay | `relay/` (new) |

Each area keeps its own sample data and models in its own folder (for example `Features/Make/MakeSample.swift`). Read `Data/SampleData.swift` and `Data/Models.swift` freely; do not edit them.

Put the data behind a small protocol or store type in your area (for example `protocol NotesProviding`) with a sample implementation, so the real desktop data can replace it later without rewriting the screens.

## Seeing your screens

Debug builds can open one view on its own. In your area's `...Debug.swift`, return your views by name:

```swift
enum MakeDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        case "studio": return AnyView(StudioScreen())
        default: return nil
        }
    }
}
```

Then list the pictures you want in `Tools/screens/<area>.txt` (one line each: a name, then the launch arguments):

```
studio -kDebugView make.studio
studio-light -kDebugView make.studio -kAppearance light
```

The view is hosted in a `NavigationStack` with the router and chrome in the environment. A sheet or a state you want pictured needs its own debug name that opens in that state.

## The build loop

Work on your branch (`area/<name>`) in your own worktree. Commit small and often.

```bash
git push origin HEAD
```

Every push to an `area/` branch starts the **Compile** workflow (about four minutes). Wait for it and read the errors:

```bash
gh run watch $(gh run list --workflow Compile --branch "$(git branch --show-current)" --limit 1 --json databaseId --jq '.[0].databaseId') --exit-status
```

```bash
gh run view <id> --log | grep -E "COMPILE|error:" | sed -E 's/^[^\t]*\t[^\t]*\t[0-9T:.Z-]+ //' | sort -u | head -80
```

When it compiles, take pictures of your screens only (about eight minutes) and look at them:

```bash
gh workflow run Build --ref "$(git branch --show-current)" -f area=<area>
```

```bash
gh run download <id> -n screenshots -D <a scratch folder>
```

Look at every picture at full size before you call a screen done: spacing, clipped text, contrast in both looks, anything that reads as a placeholder. Fix and repeat. Never push to `main`; the lead merges.

Things that have bitten this project:

- An SF Symbol name that does not exist renders as nothing. Use common ones you are sure of.
- `.sheet` content does not always inherit `@Environment` objects set below it. Pass `.environment(router)` and `.environment(chrome)` to sheet content that needs them.
- A private stored property without a default breaks the memberwise init across files.
- Path booleans (`subtracting`, `union`, `intersection`) are fine; SVG-style filters are not available.
- `onChange(of:)` takes the zero or two parameter closure form.
- Do not name anything `Appearance`, `Screen`, `Tab` or `Environment`.

## Finishing

Your final report lists: what you built (screens and files), what you verified in pictures, what is unverified, what is still missing from your inventory section, and any change you need in a shared file.
