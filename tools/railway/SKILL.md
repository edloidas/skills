---
name: railway
description: >
  Interact with Railway deployments — check status, stream logs, manage
  environment variables, debug errors, and link projects. Use when the user
  mentions Railway, deployed apps, production logs, or environment variables
  for hosted services.
license: MIT
compatibility: Claude Code, Codex
allowed-tools: Bash(railway:*) Read
metadata:
  author: edloidas
---

# Railway CLI

Interact with Railway-deployed applications — check status, read logs, manage variables, deploy, and debug.

## Prerequisites

- **Railway CLI** installed (`brew install railway` or `npm i -g @railway/cli`)
- **Authenticated** — run `railway login` before using this skill

## When to Use

Use when the user:

- Asks about a deployed app's status, errors, or logs
- Wants to check or update environment variables on a hosted service
- Mentions Railway by name
- Needs to deploy, restart, or redeploy a service
- Wants to debug production issues (crashes, build failures, startup errors)
- Asks about a service's environment configuration

## Step 1: Establish Project Context

**Always start here.** Do not skip this step.

Run `railway status --json` to check what project is currently linked.

### If auth fails

Tell the user to run `railway login` in their terminal. Stop — do not proceed.

### If no project is linked

1. Run `railway list` to show available projects
2. Ask the user which project to link
3. Run `railway link -p <project> -e <env> -s <service>` with their selection
4. Confirm with `railway status`

### If linked to the wrong project

If the user asks about a project or service that doesn't match what `railway status` reports, offer to re-link. Do not silently operate on the wrong target.

### Multi-service projects

If the project has multiple services (e.g., app + database), check which service is active. Use the `-s <service>` flag to target a specific service when needed, or re-link to a different service.

### Config detection

Use `Read` to check for `railway.toml` or `railway.json` in the project root. If present, mention the config as context — it affects builds, deploys, and healthchecks.

## Step 2: Handle the Request

Route based on the user's intent. See `references/commands.md` for full flag details. Use `--json` where available for structured, parseable output.

### Logs & Debugging

```bash
# Last 100 lines of runtime logs
railway logs -n 100

# Build logs (for deploy failures)
railway logs --build -n 200

# Logs for a specific service
railway logs -n 100 -s <service-name>
```

**NEVER run bare `railway logs` without `-n`** — it streams indefinitely and blocks the session.

After reading logs, analyze errors and suggest fixes in the codebase. Look for:
- Stack traces and error messages
- Missing environment variables
- Port binding issues (`PORT` env var)
- Build failures in `--build` logs
- Health check failures

### Variable Management

```bash
# List variable names
railway variable list

# Set or update a variable
railway variable set KEY=value

# Delete a variable
railway variable delete KEY
```

**Safety:**
- Setting or deleting variables triggers a redeployment. Confirm with the user first.
- Never print variable values in summaries. List names only unless the user explicitly asks for values.

### Deploy & Restart

```bash
# Deploy current directory
railway up

# Deploy without streaming logs
railway up --detach

# Re-run the latest deployment
railway redeploy

# Restart without redeploying
railway restart

# Tear down the latest deployment
railway down
```

**Safety:** All of these affect production. Confirm before running any deploy/restart command.

### Status & Info

```bash
# Full project info (JSON)
railway status --json

# Open dashboard in browser
railway open
```

### SSH & Database (suggest only)

These are interactive commands that **cannot run in Claude Code**. Print the command for the user to run in their own terminal:

- `railway ssh` — shell into the running container
- `railway connect` — open a database shell (psql, redis-cli, etc.)

Suggest these when logs aren't enough to diagnose the issue.

## Safety Rules

1. **Confirm before destructive/production-affecting actions** — `railway up`, `railway down`, `railway redeploy`, `railway restart`, `railway variable delete`, `railway variable set`
2. **Never print variable values in summaries** — list names only unless explicitly asked
3. **Re-link when mismatched** — if the user asks about a different project/service, offer to re-link
4. **Never run `railway delete`** — do not delete projects, ever
5. **Never run `railway init`** — project creation belongs in the dashboard
6. **Never run `railway ssh` or `railway connect`** — print the command for the user instead

## Error Handling

| Error | Action |
|-------|--------|
| `railway: command not found` | Tell user to install: `brew install railway` or `npm i -g @railway/cli` |
| Auth expired / not logged in | Tell user to run `railway login` |
| No linked project | Run linking flow (Step 1) |
| Network failure | Suggest checking internet connection, retry once |
| Rate limit | Wait briefly, retry once, then suggest using the dashboard |
| Build failure | Check `railway logs --build -n 200`, analyze the error |
| Service crash loop | Check `railway logs -n 200`, look for startup errors |

## Troubleshooting Patterns

**App won't start:**
1. `railway logs --build -n 200` — check build errors
2. `railway logs -n 200` — check runtime errors
3. `railway variable list` — verify required env vars exist
4. Check for `PORT` — Railway injects this, the app must bind to it

**Deploy succeeds but app errors:**
1. `railway logs -n 200` — look for stack traces
2. `railway variable list` — check for missing config
3. Suggest `railway ssh` for deeper inspection (user runs it)

**Environment variable issues:**
1. `railway variable list` — check what's set
2. Compare against what the app expects (check codebase for `process.env.*` or similar)
3. `railway variable set KEY=value` — set missing vars (confirm first)

## Examples

### Check why an app is down
```
User: "My rollrobot app is returning errors"

1. railway status --json → linked to lively-miracle/production/rollrobot
2. railway logs -n 100 → find error messages
3. Analyze errors, suggest codebase fixes
```

### Update an environment variable
```
User: "Set the API_KEY for my bot"

1. railway status --json → confirm correct project/service
2. Confirm with user before setting
3. railway variable set API_KEY=<value>
4. Note: this triggers a redeployment
```

### Switch to a different project
```
User: "Check my other app now"

1. railway status --json → shows current project
2. Offer to re-link: railway link -p <other-project>
3. Continue with the new project context
```

## Keywords

railway, deploy, deployment, production, logs, environment variables, env vars, hosted, cloud, railway app, railway status, railway logs, deployed app, production errors, build failure, service crash, restart service, redeploy
