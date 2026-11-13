import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { NOTICE_KINDS, noticeLine } from "../src/apns.js";

// The phone's wording is the source of truth. Read each kind's headline straight from the app's
// source and check the relay sends the same line, so a change on either side fails here.
const swiftPath = fileURLToPath(new URL("../../KairosAgents/Native/Notifications.swift", import.meta.url));

function phoneHeadlines() {
  const source = readFileSync(swiftPath, "utf8");
  const start = source.indexOf("var headline: String {");
  assert.ok(start >= 0, "headline not found in Notifications.swift");
  const end = source.indexOf("\n    }\n", start);
  const block = source.slice(start, end);
  const lines = {};
  for (const match of block.matchAll(/case \.(\w+): return "((?:[^"\\]|\\.|\\\([^)]*\))*)"/g)) {
    lines[match[1]] = match[2];
  }
  return lines;
}

test("every relay notice line matches the phone's headline word for word", () => {
  const phone = phoneHeadlines();
  for (const kind of NOTICE_KINDS) {
    assert.ok(kind in phone, `the phone has no fixed headline for ${kind}`);
    const expected = phone[kind].replaceAll("\\(botName)", "Ada");
    assert.ok(!expected.includes("\\("), `the phone's ${kind} line uses a value the relay does not have`);
    assert.equal(noticeLine(kind, "Ada"), expected, `${kind} drifted from the phone`);
  }
});
