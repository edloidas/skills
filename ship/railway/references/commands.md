# Railway CLI Command Reference

Quick reference for Railway CLI commands and flags used by this skill.

## Global Flags

These work on most commands:

| Flag | Purpose |
|------|---------|
| `-s, --service <name-or-id>` | Target a specific service |
| `-e, --environment <name-or-id>` | Target a specific environment |
| `--json` | Output as JSON (machine-readable) |
| `-y, --yes` | Skip confirmation prompts |

## Authentication

| Command | Purpose |
|---------|---------|
| `railway login` | Browser-based login |
| `railway login --browserless` | Token-based login (headless/SSH sessions) |
| `railway logout` | End session |
| `railway whoami` | Show current authenticated user |

**CI/CD tokens (no interactive login needed):**
- `RAILWAY_TOKEN` — project-scoped token (from project settings)
- `RAILWAY_API_TOKEN` — account/workspace-scoped token

## Linking

| Command | Purpose |
|---------|---------|
| `railway link` | Link current directory to a project (interactive) |
| `railway link -p <project> -e <env> -s <service>` | Link non-interactively |
| `railway unlink` | Disconnect current directory |
| `railway list` | List all projects |
| `railway status` | Show linked project/environment/service |
| `railway status --json` | Detailed info with all services and environments |

Link state is stored in `.railway/` directory (should be gitignored).

**`railway link` flags:**
- `-p, --project <ID|NAME>` — specify project
- `-e, --environment <ID|NAME>` — specify environment
- `-s, --service <ID|NAME>` — specify service
- `-w, --workspace <ID|NAME>` — specify workspace

## Logs

| Command | Purpose |
|---------|---------|
| `railway logs -n <N>` | Last N lines of runtime logs |
| `railway logs --build -n <N>` | Last N lines of build logs |
| `railway logs -n <N> -s <service>` | Logs for a specific service |

**Never run bare `railway logs`** — it streams indefinitely.

## Variables

| Command | Purpose |
|---------|---------|
| `railway variable list` | List all variables for linked service |
| `railway variable set KEY=value` | Set or update a variable |
| `railway variable set K1=v1 K2=v2` | Set multiple variables at once |
| `railway variable delete KEY` | Delete a variable |

Variable changes trigger redeployment.

**Variable types in Railway:**
- **Service variables** — scoped to a single service
- **Shared variables** — shared across services (`${{ shared.KEY }}`)
- **Reference variables** — template syntax (`${{ SERVICE_NAME.VAR }}`)
- **Sealed variables** — write-only, cannot be read back via CLI

**Auto-injected variables:**
- `RAILWAY_PUBLIC_DOMAIN` — public domain
- `RAILWAY_PRIVATE_DOMAIN` — private domain
- `PORT` — port for health checks (app must bind to this)

## Deployments

| Command | Purpose |
|---------|---------|
| `railway up` | Deploy current directory |
| `railway up --detach` | Deploy without streaming logs |
| `railway redeploy` | Re-run the latest deployment |
| `railway restart` | Restart without redeploying |
| `railway down` | Tear down the latest deployment |

## Debugging (suggest to user)

These are interactive — print the command for the user to run:

| Command | Purpose |
|---------|---------|
| `railway ssh` | Shell into the running container |
| `railway connect` | Database shell (psql, redis-cli, etc.) |

## Environments

| Command | Purpose |
|---------|---------|
| `railway environment` | Switch environment (interactive) |
| `railway environment new <name>` | Create a new environment |
| `railway environment delete <name>` | Delete an environment |

## Other

| Command | Purpose |
|---------|---------|
| `railway open` | Open project dashboard in browser |
| `railway run <command>` | Run local command with Railway env vars injected |
| `railway shell` | Open shell with Railway env vars loaded |
| `railway upgrade` | Update CLI to latest version |
