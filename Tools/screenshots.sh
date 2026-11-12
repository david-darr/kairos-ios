#!/bin/bash
# Launch the simulator build on each screen and save a picture of it.
# The app reads "-kScreen <name>" in Debug builds only (see DebugScreens.swift).
set -euo pipefail

APP="build/Build/Products/Debug-iphonesimulator/KairosAgents.app"
BUNDLE="app.kairos-agents.mobile"
OUT="shots"
mkdir -p "$OUT"

UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
best = None
for runtime in sorted(devices, reverse=True):
    if "iOS" not in runtime:
        continue
    for device in devices[runtime]:
        name = device["name"]
        if not name.startswith("iPhone"):
            continue
        score = ("Pro" in name and "Max" not in name) * 2 + ("17" in name)
        if best is None or score > best[0]:
            best = (score, device["udid"], name, runtime)
    if best:
        break
print(best[1])
print("Simulator:", best[2], best[3], file=sys.stderr)
')

xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
xcrun simctl install "$UDID" "$APP"
# Warm up: the first launch after a boot is slow.
xcrun simctl launch "$UDID" "$BUNDLE" -onboarded YES >/dev/null 2>&1 || true
sleep 12

shot() {
  local name="$1"; shift
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE" "$@" >/dev/null
  sleep "${WAIT:-5}"
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null 2>&1
  echo "saved $name"
}

# AREA=<name> shoots only Tools/screens/<name>.txt (quick, for one area's work).
# Without it: the base set below, then every area's list.
if [ -z "${AREA:-}" ]; then
  WAIT=14 shot 01-onboarding -onboarded NO
  shot 02-onboarding-bots -onboarded NO -kScreen onboarding2
  shot 03-connect -onboarded NO -kScreen connect
  shot 04-home -onboarded YES -kScreen home
  shot 05-home-bar-small -onboarded YES -kScreen collapsed
  shot 06-jump -onboarded YES -kScreen jump
  shot 07-bot -onboarded YES -kScreen bot
  shot 08-bot-inbox -onboarded YES -kScreen botpanel
  shot 09-bot-settings -onboarded YES -kScreen botsettings
  shot 10-call -onboarded YES -kScreen call
  shot 11-chat -onboarded YES -kScreen chat
  shot 12-chat-live -onboarded YES -kScreen chatlive
  shot 13-model-sheet -onboarded YES -kScreen modelsheet
  shot 14-tools -onboarded YES -kScreen tools
  shot 15-doc-viewer -onboarded YES -kScreen docviewer
  shot 16-make -onboarded YES -kScreen make
  shot 17-library -onboarded YES -kScreen library
  shot 18-desktop -onboarded YES -kScreen desktop
  shot 19-you -onboarded YES -kScreen you
  shot 20-search -onboarded YES -kScreen search
  shot 27-bots -onboarded YES -kScreen bots
  shot 21-home-light -onboarded YES -kScreen home -kAppearance light
  shot 22-bot-light -onboarded YES -kScreen bot -kAppearance light
  shot 23-chat-live-light -onboarded YES -kScreen chatlive -kAppearance light
  shot 24-jump-light -onboarded YES -kScreen jump -kAppearance light
  shot 25-you-light -onboarded YES -kScreen you -kAppearance light
  shot 26-onboarding-light -onboarded NO -kAppearance light
fi

for list in Tools/screens/*.txt; do
  [ -f "$list" ] || continue
  area=$(basename "$list" .txt)
  if [ -n "${AREA:-}" ] && [ "$AREA" != "$area" ]; then continue; fi
  while read -r name args; do
    case "$name" in ""|\#*) continue ;; esac
    # shellcheck disable=SC2086
    shot "$area-$name" -onboarded YES $args
  done < "$list"
done

xcrun simctl shutdown "$UDID" || true
ls -la "$OUT"
