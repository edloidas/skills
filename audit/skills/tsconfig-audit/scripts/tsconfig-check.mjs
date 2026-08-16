#!/usr/bin/env node
// Audits a tsconfig.json against TypeScript 7.
//
// The compiler is the authority wherever it can answer:
//   * `tsc --noEmit` reports removals (TS5102/TS5108), unknown options (TS5023), bad enum
//     values (TS6046) and illegal combinations (TS5095).
//   * `tsc --showConfig` materialises options *implied* by another setting, so implications
//     never have to be hardcoded.
// references/ts7-options.json supplies only what the compiler cannot express: defaults,
// which unknown options are legacy removals rather than typos, and migration guidance.
//
// Note `--showConfig` silently swallows config errors (it prints a config containing a
// removed option and exits 0), so it is never used as a diagnostics source.
//
// Usage: node tsconfig-check.mjs [tsconfig path] [--json] [--tsc <path>]

import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs'
import { dirname, isAbsolute, join, relative, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const DATA = JSON.parse(readFileSync(resolve(HERE, '..', 'references', 'ts7-options.json'), 'utf8'))

// --- config reading -----------------------------------------------------------------------

// tsconfig is JSONC: comments and trailing commas are legal and common. Strip them in a
// string-aware pass so a `//` inside a path value is not mistaken for a comment.
export function stripJsonc(text) {
  let out = ''
  let inString = false
  let escaped = false
  for (let i = 0; i < text.length; i++) {
    const c = text[i]
    if (inString) {
      out += c
      if (escaped) escaped = false
      else if (c === '\\') escaped = true
      else if (c === '"') inString = false
      continue
    }
    if (c === '"') {
      inString = true
      out += c
    } else if (c === '/' && text[i + 1] === '/') {
      while (i < text.length && text[i] !== '\n') i++
      out += '\n'
    } else if (c === '/' && text[i + 1] === '*') {
      i += 2
      while (i < text.length && !(text[i] === '*' && text[i + 1] === '/')) i++
      i++
    } else {
      out += c
    }
  }
  return out.replace(/,(\s*[}\]])/g, '$1')
}

function readConfig(file) {
  const raw = readFileSync(file, 'utf8')
  return { raw, json: JSON.parse(stripJsonc(raw)) }
}

// Resolve an `extends` specifier the way tsc does: relative paths against the referring
// file, bare specifiers through node_modules walking upward.
function resolveExtends(spec, fromFile) {
  const fromDir = dirname(fromFile)
  const candidates = []
  if (spec.startsWith('.') || isAbsolute(spec)) {
    const base = resolve(fromDir, spec)
    candidates.push(base, `${base}.json`, join(base, 'tsconfig.json'))
  } else {
    let dir = fromDir
    for (;;) {
      const base = join(dir, 'node_modules', spec)
      candidates.push(base, `${base}.json`, join(base, 'tsconfig.json'))
      const parent = dirname(dir)
      if (parent === dir) break
      dir = parent
    }
  }
  return candidates.find((c) => existsSync(c) && statSync(c).isFile()) ?? null
}

// Walk the extends chain and record which file last set each option. The compiler cannot
// answer this: a removal diagnostic anchors to the leaf config even when the option was
// inherited from a base inside node_modules.
function buildChain(entry) {
  const chain = []
  const seen = new Set()

  const visit = (file) => {
    const real = resolve(file)
    if (seen.has(real)) return
    seen.add(real)
    let config
    try {
      config = readConfig(real)
    } catch (err) {
      chain.push({ file: real, error: err.message, options: {} })
      return
    }
    const ext = config.json.extends
    for (const spec of Array.isArray(ext) ? ext : ext ? [ext] : []) {
      const resolved = resolveExtends(spec, real)
      if (resolved) visit(resolved)
      else chain.push({ file: real, unresolvedExtends: spec, options: {} })
    }
    chain.push({ file: real, raw: config.raw, options: config.json.compilerOptions ?? {}, json: config.json })
  }

  visit(entry)
  return chain
}

// Later entries in the chain override earlier ones, so the last writer owns the option.
function mergeChain(chain) {
  const merged = {}
  const origin = {}
  for (const link of chain) {
    for (const [k, v] of Object.entries(link.options)) {
      merged[k] = v
      origin[k] = link.file
    }
  }
  return { merged, origin }
}

// --- compiler ----------------------------------------------------------------------------

function findCompiler(startDir, explicit) {
  if (explicit) return { bin: explicit, source: '--tsc' }
  let dir = startDir
  for (;;) {
    const local = join(dir, 'node_modules', '.bin', 'tsc')
    if (existsSync(local)) return { bin: local, source: 'project' }
    const parent = dirname(dir)
    if (parent === dir) break
    dir = parent
  }
  for (const bin of ['tsgo', 'tsc']) {
    try {
      execFileSync(bin, ['--version'], { stdio: 'pipe' })
      return { bin, source: 'PATH' }
    } catch {}
  }
  return null
}

function runTsc(bin, args, cwd) {
  try {
    return execFileSync(bin, args, { cwd, stdio: 'pipe', encoding: 'utf8' })
  } catch (err) {
    return `${err.stdout ?? ''}${err.stderr ?? ''}`
  }
}

// Diagnostics are matched on their numeric code; only the option name is read out of the
// message text, and `--locale en` keeps that text stable.
function parseDiagnostics(text) {
  const found = []
  const lines = text.split('\n')
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    const suggestion = lines[i + 1]?.match(/Use '(.+)' instead\./)?.[1] ?? null
    let m
    if ((m = line.match(/error TS5102: Option '([^']+)' has been removed/))) {
      found.push({ code: 'TS5102', option: m[1], suggestion })
    } else if ((m = line.match(/error TS5108: Option '([^']+)=([^']*)' has been removed/))) {
      found.push({ code: 'TS5108', option: m[1], value: m[2], suggestion })
    } else if ((m = line.match(/error TS5023: Unknown compiler option '([^']+)'/))) {
      found.push({ code: 'TS5023', option: m[1], suggestion })
    } else if ((m = line.match(/error TS6046: Argument for '--([^']+)' option must be: (.+)/))) {
      found.push({ code: 'TS6046', option: m[1], detail: m[2], suggestion })
    } else if ((m = line.match(/error (TS5095|TS5052|TS5053|TS5069): (.+)/))) {
      found.push({ code: m[1], option: null, detail: m[2], suggestion })
    }
  }
  return found
}

// --- classification -----------------------------------------------------------------------

// tsc matches enum values case-insensitively -- "ESNext", "esnext" and "EsNext" are the same
// option. Comparing raw strings would miss every finding in a config that uses TitleCase.
const norm = (v) => (typeof v === 'string' ? v.toLowerCase() : v)
const eq = (a, b) => JSON.stringify(norm(a)) === JSON.stringify(norm(b))

function impliedBy(option, merged) {
  for (const [source, rule] of Object.entries(DATA.implications)) {
    if (source === option) continue
    const byValue = rule.byValue && Object.entries(rule.byValue).find(([k]) => eq(k, merged[source]))?.[1]
    const set = rule.whenTrue && merged[source] === true ? rule.whenTrue : byValue
    if (set && option in set && eq(set[option], merged[option])) return source
  }
  return null
}

// `moduleResolution` defaults to bundler for every `module` value that does not pin it to a
// node* resolver, so writing "bundler" alongside module: esnext/preserve/commonjs is a no-op.
function isDefaultModuleResolution(merged) {
  const rule = DATA.derivedDefaults?.moduleResolution
  if (!rule || !eq(merged.moduleResolution, rule.fallback)) return false
  return !rule.explicitByModule.some((m) => eq(m, merged.module))
}

function classify({ merged, origin, chain, diagnostics, projectRoot, entryFile }) {
  const findings = []
  const byOption = new Map()
  for (const d of diagnostics) if (d.option) byOption.set(d.option, d)

  const add = (f) => {
    const source = f.sourceFile ?? entryFile
    findings.push({
      ...f,
      sourceFile: relative(projectRoot, source) || '.',
      // A base inside node_modules is shared with every other consumer of that package;
      // it must be overridden locally, never edited in place.
      editable: !source.includes(`${'node_modules'}/`),
    })
  }

  for (const [option, value] of Object.entries(merged)) {
    const diag = byOption.get(option)
    const sourceFile = origin[option]

    if (diag?.code === 'TS5102') {
      add({
        option, value, action: 'remove', reason: 'removed-in-ts7', severity: 'error', confidence: 'high',
        sourceFile, detail: `\`${option}\` was removed in TypeScript 7.`,
        suggestion: diag.suggestion ?? DATA.removed[option]?.suggestion ?? null,
      })
      continue
    }
    if (diag?.code === 'TS5108') {
      add({
        option, value, action: 'replace', reason: 'removed-value', severity: 'error', confidence: 'high',
        sourceFile, detail: `\`${option}: ${JSON.stringify(value)}\` was removed in TypeScript 7.`,
        suggestion: diag.suggestion ?? null,
      })
      continue
    }
    if (diag?.code === 'TS6046') {
      add({
        option, value, action: 'replace', reason: 'invalid-value', severity: 'error', confidence: 'high',
        sourceFile, detail: `Not a valid TypeScript 7 value. Must be: ${diag.detail}`, suggestion: null,
      })
      continue
    }
    if (diag?.code === 'TS5023') {
      const legacy = DATA.legacyRemoved.includes(option)
      add({
        option, value, action: 'remove',
        reason: legacy ? 'legacy-removed' : 'unknown-option',
        severity: legacy ? 'error' : 'warning',
        confidence: legacy ? 'high' : 'low',
        sourceFile,
        detail: legacy
          ? `Deprecated in TypeScript 5.0, inert since 5.5, and unknown to 7.`
          : `TypeScript 7 does not recognise this option. It is a typo, a third-party extension, or newer than this skill's data file (generated from ${DATA.tsVersion}).`,
        suggestion: null,
        needsResearch: !legacy,
      })
      continue
    }

    // An option that sets a different value than a config it inherits from is never
    // redundant, however well it matches a default: deleting it silently restores the base
    // value. This has to gate every redundancy rule below, not just the defaults check.
    const overridesBase = chain.some(
      (l) => resolve(l.file) !== resolve(sourceFile) && option in l.options && !eq(l.options[option], value),
    )
    if (overridesBase) {
      const base = chain.find((l) => resolve(l.file) !== resolve(sourceFile) && option in l.options)
      add({
        option, value, action: 'keep', reason: 'overrides-base', severity: 'info', confidence: 'high',
        sourceFile,
        detail: `Overrides \`${JSON.stringify(base.options[option])}\` inherited from ${relative(projectRoot, base.file)}. Removing it would restore that value.`,
        suggestion: null,
      })
      continue
    }

    if (option in DATA.lockedValues && eq(value, DATA.lockedValues[option])) {
      add({
        option, value, action: 'remove', reason: 'locked-value', severity: 'info', confidence: 'high',
        sourceFile, detail: `TypeScript 7 accepts only \`${JSON.stringify(DATA.lockedValues[option])}\`; setting it does nothing.`,
        suggestion: null,
      })
      continue
    }

    const implier = impliedBy(option, merged)
    if (implier) {
      add({
        option, value, action: 'remove', reason: 'implied-by', severity: 'info', confidence: 'high',
        sourceFile, detail: `Already implied by \`${implier}: ${JSON.stringify(merged[implier])}\`.`,
        suggestion: null,
      })
      continue
    }

    // The strict family defaults to `true unless strict is false`, so writing `true` while
    // strict is on is redundant. Writing `false` while strict is on is a real override.
    const conditional = DATA.conditionalDefaults[option]
    if (conditional && /true_unless_strict_is_false/.test(conditional) && value === true && merged.strict !== false) {
      add({
        option, value, action: 'remove', reason: 'implied-by', severity: 'info', confidence: 'high',
        sourceFile, detail: `Already implied by \`strict: ${merged.strict ?? 'true (default)'}\`.`, suggestion: null,
      })
      continue
    }

    // "false unless <other> is set" defaults: redundant when written as false while the
    // option that would flip it is absent.
    const gated = conditional?.match(/^X_false_unless_(\w+?)_is_set$/)?.[1]
    if (gated && value === false && merged[gated] !== true) {
      add({
        option, value, action: 'remove', reason: 'matches-default', severity: 'info', confidence: 'high',
        sourceFile, detail: `Defaults to \`false\` unless \`${gated}\` is set, and \`${gated}\` is not set here.`,
        suggestion: null,
      })
      continue
    }

    if (option === 'moduleResolution' && isDefaultModuleResolution(merged)) {
      add({
        option, value, action: 'remove', reason: 'matches-default', severity: 'info', confidence: 'high',
        sourceFile,
        detail: `\`${DATA.derivedDefaults.moduleResolution.fallback}\` is already the default for \`module: ${JSON.stringify(merged.module)}\`.`,
        suggestion: null,
      })
      continue
    }

    if (option in DATA.keepList) {
      // The keep-list rationale is written for the default value. A config that sets
      // something else is deliberately overriding, which needs the opposite message.
      const isDefault = !(option in DATA.defaults) || eq(value, DATA.defaults[option])
      add({
        option, value, action: 'keep', reason: 'keep-list', severity: 'info', confidence: 'high',
        sourceFile,
        detail: isDefault
          ? DATA.keepList[option]
          : `Overrides the TypeScript 7 default (\`${JSON.stringify(DATA.defaults[option])}\`). Deliberate — keep it.`,
        suggestion: null,
      })
      continue
    }

    if (option in DATA.defaults && eq(value, DATA.defaults[option])) {
      add({
        option, value, action: 'remove', reason: 'matches-default', severity: 'info', confidence: 'high',
        sourceFile, detail: `Matches the TypeScript 7 default (\`${JSON.stringify(DATA.defaults[option])}\`).`,
        suggestion: null,
      })
      continue
    }

    if (DATA.externalConsumers.includes(option)) {
      add({
        option, value, action: 'keep', reason: 'external-consumer', severity: 'warning', confidence: 'medium',
        sourceFile,
        detail: `Bundlers, test runners and IDEs read \`${option}\` independently of tsc. A clean typecheck does not prove runtime resolution survives dropping it.`,
        suggestion: null,
      })
      continue
    }
  }

  // Dropping `baseUrl` is not a delete. Every relative `paths` entry was resolved against
  // it, so the prefix has to be folded into each entry or module resolution silently breaks
  // -- and the compiler's own suggestion only rewrites the catch-all.
  if (byOption.get('baseUrl')?.code === 'TS5102' && merged.paths) {
    const base = merged.baseUrl
    const rewritten = Object.fromEntries(
      Object.entries(merged.paths).map(([k, v]) => [
        k,
        (Array.isArray(v) ? v : [v]).map((p) => (p.startsWith('.') ? p : `${String(base).replace(/\/$/, '')}/${p}`)),
      ]),
    )
    add({
      option: 'paths', value: merged.paths, action: 'replace', reason: 'removed-in-ts7',
      severity: 'error', confidence: 'high', sourceFile: origin.paths,
      detail:
        `\`paths\` entries were resolved against \`baseUrl: ${JSON.stringify(base)}\`. With baseUrl removed they ` +
        `resolve against the config directory instead, so each entry needs the old prefix folded in.`,
      suggestion: `"paths": ${JSON.stringify(rewritten)}`,
    })
  }

  // Combination errors carry no single owning option.
  for (const d of diagnostics) {
    if (!d.option && d.detail) {
      add({
        option: null, value: null, action: 'replace', reason: 'invalid-combination',
        severity: 'error', confidence: 'high', sourceFile: entryFile, detail: d.detail, suggestion: d.suggestion,
      })
    }
  }

  // An option with a blocking finding must not also appear under "keep" or "safe to drop" --
  // the migration fix supersedes the advisory note.
  const blocking = new Set(findings.filter((f) => f.severity === 'error' && f.option).map((f) => f.option))
  return findings.filter((f) => f.severity === 'error' || !blocking.has(f.option))
}

// The two TS7 default changes that make a drop-only audit unsafe. Both are conditional --
// neither is universally required -- so each is only raised when its trigger is present.
function conditionalAdds({ merged, projectRoot, entryFile, effective }) {
  const out = []
  const entryDir = dirname(entryFile)

  if (!('rootDir' in merged) && !merged.noEmit && (merged.outDir || merged.declarationDir)) {
    const files = effective?.files ?? []
    const below = files.filter((f) => f.startsWith('./') && f.slice(2).includes('/'))
    if (below.length > 0) {
      const topDirs = [...new Set(below.map((f) => f.slice(2).split('/')[0]))]
      out.push({
        option: 'rootDir', value: null, action: 'add', reason: 'conditional-add',
        severity: 'error', confidence: 'high', sourceFile: relative(projectRoot, entryFile) || '.', editable: true,
        detail:
          `\`rootDir\` now defaults to \`.\` instead of being inferred from the input files. ` +
          `Sources live under ${topDirs.map((d) => `\`${d}/\``).join(', ')}, so emit moves from ` +
          `\`${merged.outDir ?? 'outDir'}/\` to \`${merged.outDir ?? 'outDir'}/${topDirs[0]}/\`.`,
        suggestion: topDirs.length === 1 ? `"rootDir": "./${topDirs[0]}"` : null,
      })
    }
  }

  if (!('types' in merged)) {
    const typesDir = join(findNodeModules(entryDir) ?? entryDir, '@types')
    const installed = safeReaddir(typesDir)
    out.push({
      option: 'types', value: null, action: 'add', reason: 'conditional-add',
      severity: installed.length > 0 ? 'warning' : 'info', confidence: 'medium',
      sourceFile: relative(projectRoot, entryFile) || '.', editable: true,
      detail:
        `\`types\` now defaults to \`[]\`; @types packages are no longer added to the global scope automatically. ` +
        (installed.length > 0
          ? `Installed @types: ${installed.map((t) => `\`${t}\``).join(', ')}. List the ones whose globals the code actually uses.`
          : `No @types packages are installed, so this is likely already fine.`),
      suggestion: installed.length > 0 ? `"types": [${installed.map((t) => `"${t}"`).join(', ')}]` : null,
    })
  }

  return out
}

function safeReaddir(dir) {
  try {
    return readdirSync(dir).filter((d) => !d.startsWith('.'))
  } catch {
    return []
  }
}

function findNodeModules(startDir) {
  let dir = startDir
  for (;;) {
    const nm = join(dir, 'node_modules')
    if (existsSync(nm)) return nm
    const parent = dirname(dir)
    if (parent === dir) return null
    dir = parent
  }
}

// --- reporting -----------------------------------------------------------------------------

const GROUPS = [
  ['removed-in-ts7', 'Removed in TypeScript 7 — build fails until fixed'],
  ['removed-value', 'Value removed in TypeScript 7 — build fails until fixed'],
  ['invalid-value', 'Invalid value for TypeScript 7'],
  ['invalid-combination', 'Illegal option combination'],
  ['legacy-removed', 'Dead since TypeScript 5.5, unknown to 7'],
  ['conditional-add', 'Must be added — default changed under you'],
  ['unknown-option', 'Not recognised — needs research'],
  ['locked-value', 'No-op — only one legal value in TypeScript 7'],
  ['implied-by', 'Redundant — already implied by another option'],
  ['matches-default', 'Redundant — matches the TypeScript 7 default'],
  ['external-consumer', 'Keep — read by tools other than tsc'],
  ['overrides-base', 'Keep — overrides an inherited value'],
  ['keep-list', 'Keep — deliberately explicit'],
]

function render(report) {
  const lines = []
  const { findings, compiler, entry } = report
  lines.push(`tsconfig audit — ${entry}`)
  lines.push(`compiler: ${compiler.bin} (${compiler.version}, via ${compiler.source})`)
  lines.push(`data file: TypeScript ${DATA.tsVersion}`)
  lines.push('')

  let shown = 0
  for (const [reason, title] of GROUPS) {
    const group = findings.filter((f) => f.reason === reason)
    if (group.length === 0) continue
    lines.push(`## ${title}`)
    for (const f of group) {
      const name = f.option ?? '(config)'
      const val = f.value === null || f.value === undefined ? '' : ` = ${JSON.stringify(f.value)}`
      lines.push(`  ${f.action.toUpperCase().padEnd(7)} ${name}${val}   [${f.sourceFile}]`)
      lines.push(`          ${f.detail}`)
      if (f.suggestion) lines.push(`          suggested: ${f.suggestion}`)
      if (!f.editable) lines.push(`          note: declared outside the project — override locally, do not edit in place`)
      shown++
    }
    lines.push('')
  }

  if (shown === 0) lines.push('No findings. Config is clean for TypeScript 7.')
  const errors = findings.filter((f) => f.severity === 'error').length
  const drops = findings.filter((f) => f.action === 'remove' && f.severity === 'info').length
  lines.push(`summary: ${errors} blocking, ${drops} safe to drop, ${findings.length} findings total`)
  return lines.join('\n')
}

// --- main -------------------------------------------------------------------------------------

function main() {
  const argv = process.argv.slice(2)
  const asJson = argv.includes('--json')
  const tscArg = argv[argv.indexOf('--tsc') + 1]
  const explicitTsc = argv.includes('--tsc') ? tscArg : null
  const positional = argv.filter((a, i) => !a.startsWith('--') && argv[i - 1] !== '--tsc')

  let entry = positional[0] ? resolve(positional[0]) : resolve('tsconfig.json')
  if (existsSync(entry) && statSync(entry).isDirectory()) entry = join(entry, 'tsconfig.json')
  if (!existsSync(entry)) {
    console.error(`No tsconfig found at ${entry}`)
    process.exit(2)
  }

  const projectRoot = dirname(entry)
  const compiler = findCompiler(projectRoot, explicitTsc)
  if (!compiler) {
    console.error(
      'No TypeScript compiler found. Install typescript@7 in the project, or pass --tsc <path>.\n' +
        'This audit reads diagnostics from the real compiler and will not guess without one.',
    )
    process.exit(2)
  }
  compiler.version = runTsc(compiler.bin, ['--version'], projectRoot).trim().replace(/^Version\s+/, '')
  const major = Number(compiler.version.split('.')[0])

  const chain = buildChain(entry)
  const { merged, origin } = mergeChain(chain)

  const diagText = runTsc(compiler.bin, ['-p', entry, '--noEmit', '--locale', 'en'], projectRoot)
  const diagnostics = parseDiagnostics(diagText)

  let effective = null
  try {
    effective = JSON.parse(runTsc(compiler.bin, ['-p', entry, '--showConfig'], projectRoot))
  } catch {}

  const findings = [
    ...classify({ merged, origin, chain, diagnostics, projectRoot, entryFile: entry }),
    ...conditionalAdds({ merged, projectRoot, entryFile: entry, effective }),
  ]

  const warnings = []
  if (!Number.isFinite(major) || major < 7) {
    warnings.push(
      `Compiler is TypeScript ${compiler.version}, not 7.x. Removal and unknown-option findings ` +
        `come from this compiler and will understate what TypeScript 7 rejects. ` +
        `Findings derived from the data file are still TS7-accurate.`,
    )
  }
  if (compiler.version && DATA.tsVersion && compiler.version !== DATA.tsVersion) {
    warnings.push(`Data file was generated from ${DATA.tsVersion}; compiler is ${compiler.version}. Re-run refresh-options.mjs if they diverge further.`)
  }
  for (const link of chain) {
    if (link.unresolvedExtends) warnings.push(`Could not resolve extends "${link.unresolvedExtends}" from ${relative(projectRoot, link.file)}`)
    if (link.error) warnings.push(`Could not parse ${relative(projectRoot, link.file)}: ${link.error}`)
  }
  if (effective?.references?.length) {
    warnings.push(`${effective.references.length} project reference(s) found. Audit each referenced tsconfig separately — they are not covered here.`)
  }

  const report = {
    entry: relative(process.cwd(), entry) || entry,
    compiler,
    dataFileVersion: DATA.tsVersion,
    chain: chain.map((l) => relative(projectRoot, l.file) || '.'),
    warnings,
    findings,
  }

  if (asJson) {
    console.log(JSON.stringify(report, null, 2))
  } else {
    console.log(render(report))
    for (const w of warnings) console.log(`\nwarning: ${w}`)
  }
  process.exit(findings.some((f) => f.severity === 'error') ? 1 : 0)
}

// Guarded so the helpers above can be imported by tests without running the audit.
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main()
