#!/usr/bin/env bash
# Shared builders for the skill-eval script tests: an aggregate-result.json in the shape
# `claude plugin eval --json` writes, and stream-json traces in the shape a run records.

# trace_init <file> <model>
trace_init() {
  mkdir -p "$(dirname "$1")"
  printf '{"type":"system","subtype":"init","model":"%s","claude_code_version":"2.1.314"}\n' "$2" > "$1"
}

# trace_text <file> <text>  — assistant prose, JSON-escaped by jq
trace_text() {
  jq -cn --arg t "$2" '{type:"assistant",message:{content:[{type:"text",text:$t}]}}' >> "$1"
}

# trace_tool <file> <tool> <input-json>
trace_tool() {
  jq -cn --arg n "$2" --argjson i "$3" '{type:"assistant",message:{content:[{type:"tool_use",name:$n,input:$i}]}}' >> "$1"
}

# case_yaml <root> <dir> <expected>
case_yaml() {
  mkdir -p "$1/$2"
  printf 'schema_version: "1.1"\nname: x\nexpected_outcome: "%s"\n' "$3" > "$1/$2/case.yaml"
}

# aggregate <out-dir> <root> <cases-json>
# cases-json: [{name, dir, prompt, runs:[{passed, error, trace, graders:[{name,passed,explanation}]}]}]
aggregate() {
  mkdir -p "$1"
  jq -n --arg root "$2" --argjson cases "$3" '{
    schemaVersion: 1, claudeVersion: "2.1.314", startedAt: "2026-10-31T00:00:00.000Z",
    durationSeconds: 42, costUsd: 1.234, partial: false,
    suite: {root: $root, ablation: "none"},
    cases: [$cases[] | {
      name, dir, promptMarkdown: .prompt, runsPerCase: 3,
      arms: {with: [.runs[] | {passed, score: (if .passed then 1 else 0 end), error: (.error // null),
        tracePath: (.trace // ""), graders: (.graders // [])}]},
      aggregates: {}
    }],
    aggregates: {casesTotal: ($cases | length),
      casesPassed: ([$cases[] | select(all(.runs[]; .passed))] | length)}
  }' > "$1/aggregate-result.json"
}
