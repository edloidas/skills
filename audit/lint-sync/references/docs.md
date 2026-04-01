# Documentation Links

Quick-reference for fetching up-to-date docs without spending tokens on web search.

## Context7 Library IDs

Use these with `mcp__context7__query-docs` for token-efficient documentation lookups.

| Tool | Library ID | Snippets | Notes |
|------|-----------|----------|-------|
| Biome (source) | `/biomejs/biome` | 837 | Source repo docs |
| Biome (website) | `/biomejs/website` | 5357 | Full website, most complete |
| Biome (guides) | `/websites/biomejs_dev_guides` | 114 | Guides only |
| Oxc (source) | `/oxc-project/oxc` | 573 | Source repo docs |
| Oxc (website) | `/websites/oxc_rs` | 3287 | Full website docs |
| Oxc (website alt) | `/oxc-project/website` | 5057 | Website source, most complete |
| Vite+ (website) | `/websites/viteplus_dev` | 210 | Config, lint, fmt, migration |
| Vite+ (guide) | `/websites/viteplus_dev_guide` | 147 | Guides, troubleshooting |

**Recommended**: Use `/biomejs/website` for Biome, `/oxc-project/website` for Oxc, `/websites/viteplus_dev` for Vite+.

## Direct Documentation URLs

### Biome

| Resource | URL |
|----------|-----|
| Rule sources (ESLint mapping) | https://biomejs.dev/linter/rules-sources/ |
| All linter rules | https://biomejs.dev/linter/rules/ |
| JS/TS rule sources | https://biomejs.dev/linter/javascript/sources/ |
| CSS rule sources | https://biomejs.dev/linter/css/sources/ |
| Formatter options | https://biomejs.dev/formatter/ |
| JS formatter options | https://biomejs.dev/reference/configuration/#javascriptformatter |
| Migration from ESLint | https://biomejs.dev/guides/migrate-eslint-prettier/ |
| Blog (changelogs) | https://biomejs.dev/blog/ |
| v2.4 changelog | https://biomejs.dev/blog/biome-v2-4/ |
| v2.3 changelog | https://biomejs.dev/blog/biome-v2-3/ |
| v2.1 changelog | https://biomejs.dev/blog/biome-v2-1/ |
| v2.0 changelog | https://biomejs.dev/blog/biome-v2/ |

### Oxc (Oxlint + Oxfmt)

| Resource | URL |
|----------|-----|
| Linter config | https://oxc.rs/docs/guide/usage/linter/config |
| Linter rules list | https://oxc.rs/docs/guide/usage/linter/rules |
| Formatter config | https://oxc.rs/docs/guide/usage/formatter/config.html |
| Migration from ESLint | https://oxc.rs/docs/guide/usage/linter/migration.html |
| eslint-plugin-oxlint | https://oxc.rs/docs/guide/usage/linter/eslint-compatibility.html |
| Type-aware linting | https://oxc.rs/docs/guide/usage/linter/type-aware.html |
| Blog (changelogs) | https://oxc.rs/blog/ |
| Rule coverage tracker | https://github.com/oxc-project/oxc/issues/481 |

### Vite+ (unified Oxc toolchain)

| Resource | URL |
|----------|-----|
| Configuration overview | https://viteplus.dev/config |
| Lint config (`lint` block) | https://viteplus.dev/config/lint |
| Fmt config (`fmt` block) | https://viteplus.dev/config/fmt |
| Lint guide | https://viteplus.dev/guide/lint |
| Fmt guide | https://viteplus.dev/guide/fmt |
| Migration guide | https://viteplus.dev/guide/migrate |
| IDE integration | https://viteplus.dev/guide/ide-integration |
| Troubleshooting | https://viteplus.dev/guide/troubleshooting |
| GitHub | https://github.com/voidzero-dev/vite-plus |

**Key points:**
- `lint` block = Oxlint config (same schema as `.oxlintrc.json`)
- `fmt` block = Oxfmt config (same schema as `.oxfmtrc.json`)
- Do NOT use standalone `.oxlintrc.json`/`.oxfmtrc.json` alongside Vite+
- `lint.options.typeAware: true` + `lint.options.typeCheck: true` recommended
- IDE: set `oxc.fmt.configPath` to `./vite.config.ts` in VS Code settings

### TypeScript-ESLint

| Resource | URL |
|----------|-----|
| Type-aware config source | https://github.com/typescript-eslint/typescript-eslint/blob/main/packages/eslint-plugin/src/configs/flat/disable-type-checked.ts |
| All rules | https://typescript-eslint.io/rules/ |

## Context7 Query Examples

```
# Check what Biome rules were added recently
query-docs libraryId="/biomejs/website" query="new rules added in latest version changelog"

# Look up Oxlint config schema
query-docs libraryId="/oxc-project/website" query="oxlintrc.json configuration schema all options"

# Check Biome formatter options
query-docs libraryId="/biomejs/website" query="biome formatter configuration options javascript"

# Oxfmt migration from Prettier
query-docs libraryId="/oxc-project/website" query="oxfmt migrate from prettier configuration"

# Vite+ lint and fmt blocks
query-docs libraryId="/websites/viteplus_dev" query="lint fmt block configuration vite.config.ts oxlint oxfmt"

# Vite+ migration from ESLint/Prettier
query-docs libraryId="/websites/viteplus_dev" query="migrate from eslint prettier to vite plus"
```
