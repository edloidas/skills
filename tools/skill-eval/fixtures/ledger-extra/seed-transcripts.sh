#!/usr/bin/env bash
# Writes four synthetic, past Claude Code sessions for the project at $1 into
# $HOME/.claude/projects/<encoded-cwd>/, in the shape Claude Code records them. Two show `do`
# routing a "why" question to the bug playbook and editing code; one is a clean `do` change; one
# shows `sharpen` starting the task it was asked only to rewrite.
set -eu
cwd="${1:?usage: seed-transcripts.sh <project-dir>}"
enc="$(printf '%s' "$cwd" | sed 's/[^A-Za-z0-9]/-/g')"
dir="$HOME/.claude/projects/$enc"
mkdir -p "$dir"
python3 - "$cwd" "$dir" <<'PY'
import json, os, sys, time, uuid

cwd, out = sys.argv[1], sys.argv[2]
n = [0]

def uid():
    n[0] += 1
    return str(uuid.UUID(int=0x5eed0000000000000000000000000000 + n[0]))

def session(name, days_ago, turns):
    sid = uid()
    t0 = time.time() - days_ago * 86400
    parent = None
    lines = []
    for i, (kind, payload) in enumerate(turns):
        stamp = time.strftime('%Y-%m-%dT%H:%M:%S.000Z', time.gmtime(t0 + i * 20))
        base = {"parentUuid": parent, "isSidechain": False, "userType": "external", "cwd": cwd,
                "sessionId": sid, "version": "2.1.300", "gitBranch": "main", "uuid": uid(),
                "timestamp": stamp}
        if kind == "user":
            base.update({"type": "user", "message": {"role": "user", "content": payload}})
        elif kind == "command":
            skill, args = payload
            text = (f"<command-message>edloidas:{skill}</command-message>\n"
                    f"<command-name>/edloidas:{skill}</command-name>\n<command-args>{args}</command-args>")
            base.update({"type": "user", "message": {"role": "user", "content": text}})
        elif kind == "text":
            base.update({"type": "assistant", "message": {"role": "assistant", "model": "claude-opus-5-5",
                         "content": [{"type": "text", "text": payload}]}})
        elif kind == "tool":
            tool, inp, result = payload
            tid = "toolu_" + uid().replace('-', '')[:24]
            base.update({"type": "assistant", "message": {"role": "assistant", "model": "claude-opus-5-5",
                         "content": [{"type": "tool_use", "id": tid, "name": tool, "input": inp}]}})
            lines.append(base)
            parent = base["uuid"]
            base = dict(base, uuid=uid(), parentUuid=parent, type="user",
                        message={"role": "user", "content": [{"type": "tool_result", "tool_use_id": tid,
                                                              "content": result}]})
            base.pop("requestId", None)
        lines.append(base)
        parent = base["uuid"]
    path = os.path.join(out, sid + ".jsonl")
    with open(path, "w") as f:
        for line in lines:
            f.write(json.dumps(line) + "\n")
    os.utime(path, (t0 + 600, t0 + 600))

session("why-weekend", 4, [
    ("command", ("do", "why does weekend.js skip some Saturdays?")),
    ("tool", ("Skill", {"skill": "edloidas:do", "args": "why does weekend.js skip some Saturdays?"},
              "Launching skill: edloidas:do")),
    ("text", "Task: make weekend.js list Saturday entries.\nRoute: references/bug.md — wrong output, no issue."),
    ("tool", ("Read", {"file_path": cwd + "/src/calendar.js"}, "1\t'use strict';\n3\tfunction isWeekend(dateText) {")),
    ("tool", ("Edit", {"file_path": cwd + "/src/calendar.js", "old_string": "day === 7", "new_string": "day === 6"},
              "The file has been updated.")),
    ("user", "no, don't change it, I only asked why it skips them"),
    ("user", [{"type": "text", "text": "[Request interrupted by user]"}]),
])
session("why-total", 3, [
    ("command", ("do", "why does total.js print 42.60 for march?")),
    ("tool", ("Skill", {"skill": "edloidas:do", "args": "why does total.js print 42.60 for march?"},
              "Launching skill: edloidas:do")),
    ("text", "Task: fix the March total.\nRoute: references/bug.md — wrong output from total.js."),
    ("tool", ("Bash", {"command": "node bin/total.js examples/march.txt"}, "42.60")),
    ("tool", ("Edit", {"file_path": cwd + "/src/amount.js", "old_string": "Number(fraction)",
                       "new_string": "Number(fraction.padEnd(2, '0'))"}, "The file has been updated.")),
    ("user", "stop. I asked why, I didn't ask you to fix it. revert that"),
    ("tool", ("Edit", {"file_path": cwd + "/src/amount.js", "old_string": "Number(fraction.padEnd(2, '0'))",
                       "new_string": "Number(fraction)"}, "The file has been updated.")),
    ("text", "Reverted. The cause: `parseAmount` reads `24.5` as 24 + 5 cents."),
])
session("json-flag", 2, [
    ("command", ("do", "add a --json flag to total.js")),
    ("tool", ("Skill", {"skill": "edloidas:do", "args": "add a --json flag to total.js"},
              "Launching skill: edloidas:do")),
    ("text", "Task: add --json output to total.js.\nRoute: references/change.md — small feature, no issue."),
    ("tool", ("Edit", {"file_path": cwd + "/bin/total.js", "old_string": "console.log(formatCents(total(entries)));",
                       "new_string": "console.log(json ? JSON.stringify({ total: formatCents(total(entries)) }) : formatCents(total(entries)));"},
              "The file has been updated.")),
    ("tool", ("Bash", {"command": "npm test"}, "ℹ tests 6\nℹ pass 6\nℹ fail 0")),
    ("text", "Change: total.js prints JSON with --json — 1 file, checks passed."),
    ("user", "perfect, thanks"),
])
session("sharpen-ran", 1, [
    ("command", ("sharpen", "make merchants.js faster")),
    ("tool", ("Skill", {"skill": "edloidas:sharpen", "args": "make merchants.js faster"},
              "Launching skill: edloidas:sharpen")),
    ("text", "**Sharpened prompt**\n\nMeasure `node bin/merchants.js` on a 30k-line ledger five times before changing anything..."),
    ("tool", ("Edit", {"file_path": cwd + "/bin/merchants.js", "old_string": "const merchants = [];",
                       "new_string": "const merchants = new Set();"}, "The file has been updated.")),
    ("user", "why did you edit the file? I only wanted the prompt"),
])
PY
