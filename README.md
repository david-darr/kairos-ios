# Kairos Agents for iPhone

The native iPhone app for [Kairos](https://www.kairos-agents.com/). It is a remote for your own Kairos desktop: the desktop stays the brain, and the phone talks to it.

**Status:** early. The app shell, the design system and the main screens run on sample data. Connecting to a desktop is not built yet.

## What is here

- `KairosAgents/` the SwiftUI app (iOS 26 and later, iPhone only)
- `project.yml` the project description; [XcodeGen](https://github.com/yonaskolb/XcodeGen) turns it into an Xcode project
- `Fonts/source/` Jost and Cormorant Garamond Italic (SIL Open Font License, texts beside them)
- `Tools/build_fonts.py` cuts the font weights the app uses
- `Tools/screenshots.sh` takes a picture of every screen in the simulator
- `.github/workflows/build.yml` builds for the simulator and saves the screenshots

## Build it

On a Mac with Xcode 26:

```bash
python3 -m venv .fontenv && .fontenv/bin/pip install fonttools==4.57.0 brotli==1.1.0 && .fontenv/bin/python Tools/build_fonts.py
```

```bash
brew install xcodegen && xcodegen generate && open KairosAgents.xcodeproj
```

No Mac is needed to work on it: every push to `main` builds in GitHub Actions and uploads the screenshots.

## Rules for this repository

It is public. No secret, key, token or personal data goes into the code or the history. Signing keys live only in GitHub Actions secrets.

## Licence

MIT, the same as Kairos itself. See [LICENSE](LICENSE). The fonts in `Fonts/source/` are under the SIL Open Font License; their licence texts sit beside them.
