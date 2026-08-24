#!/usr/bin/env node
// Regenerates references/ts7-options.json.
//
// Two sources, both authoritative, neither trusted alone:
//   1. The compiler's own option declarations (typescript-go declscompiler.go at a pinned
//      release tag) for the full option list and declared defaults.
//   2. Live probes of an installed tsc, because the declared defaults drift from real
//      behaviour. `rootDir` declares "Computed from the list of input files" but actually
//      defaults to "."; the 7.0 release notes claim `stableTypeOrdering` cannot be turned
//      off but the compiler accepts `false`. Probes win where the two disagree.
//
// Usage: node refresh-options.mjs [--tag typescript/v7.0.2] [--tsc <path>]

import { execFileSync } from 'node:child_process'
import { mkdtempSync, rmSync, writeFileSync, readFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const OUT = resolve(HERE, '..', 'references', 'ts7-options.json')

// Options TS 5.0 deprecated and 5.5 neutered. TS7 reports them as TS5023 "Unknown compiler
// option", which is indistinguishable from a typo -- this list is what tells them apart.
const LEGACY_REMOVED = [
  'charset', 'importsNotUsedAsValues', 'preserveValueImports', 'noImplicitUseStrict',
  'noStrictGenericChecks', 'keyofStringsOnly', 'suppressExcessPropertyErrors',
  'suppressImplicitAnyIndexErrors', 'out', 'prepend',
]

// Candidates probed for removal. Values are probed as `option: value` pairs.
const REMOVAL_PROBES = [
  ['target', 'es5'], ['target', 'es3'],
  ['downlevelIteration', true], ['downlevelIteration', false],
  ['moduleResolution', 'node'], ['moduleResolution', 'node10'], ['moduleResolution', 'classic'],
  ['module', 'amd'], ['module', 'umd'], ['module', 'system'],
  ['baseUrl', './'], ['outFile', './out.js'],
  ['esModuleInterop', false], ['allowSyntheticDefaultImports', false], ['alwaysStrict', false],
  ['esModuleInterop', true], ['allowSyntheticDefaultImports', true], ['alwaysStrict', true],
  ['stableTypeOrdering', true], ['stableTypeOrdering', false],
]

// Options whose implications are worth materialising. Probed via --showConfig.
const IMPLICATION_PROBES = [
  { composite: true },
  { verbatimModuleSyntax: true },
  { module: 'node16' }, { module: 'node18' }, { module: 'node20' }, { module: 'nodenext' },
  { module: 'preserve' }, { module: 'commonjs' }, { module: 'esnext' },
  { declaration: true }, { isolatedDeclarations: true },
]

const ENUM_PROBES = ['module', 'moduleResolution', 'target', 'jsx', 'moduleDetection', 'newLine']

function arg(name, fallback) {
  const i = process.argv.indexOf(name)
  return i !== -1 && process.argv[i + 1] ? process.argv[i + 1] : fallback
}

function findTsc() {
  const explicit = arg('--tsc', null)
  if (explicit) return explicit
  for (const c of ['./node_modules/.bin/tsc', 'tsc']) {
    try {
      execFileSync(c, ['--version'], { stdio: 'pipe' })
      return c
    } catch {}
  }
  throw new Error('No tsc found. Install typescript@7 or pass --tsc <path>.')
}

// --- source of truth 1: compiler option declarations ------------------------------------

function parseGoDecls(src) {
  const opts = []
  for (const block of src.split(/\n\t\{\n/).slice(1)) {
    const body = block.split(/\n\t\},/)[0]
    const name = body.match(/Name:\s*"([^"]+)"/)?.[1]
    if (!name) continue
    // Anchor on end-of-line, not "\n": the last field in a block has its newline consumed
    // by the block split, so a "\n"-terminated pattern silently misses ~90% of defaults.
    const rawDefault = body.match(/DefaultValueDescription:\s*(.*?),?\s*$/m)?.[1]?.trim()
    opts.push({
      name,
      kind: body.match(/Kind:\s*CommandLineOptionType(\w+)/)?.[1]?.toLowerCase() ?? null,
      commandLineOnly: /IsCommandLineOnly:\s*true/.test(body),
      tsconfigOnly: /IsTSConfigOnly:\s*true/.test(body),
      declaredDefault: normaliseDefault(rawDefault),
    })
  }
  return opts
}

// Go declarations mix real literals with diagnostic-message references. Only literals are
// usable as "this equals the default"; everything else is conditional and must not drive a
// drop recommendation.
function normaliseDefault(raw) {
  if (raw == null) return { kind: 'unset' }
  if (raw === 'true') return { kind: 'literal', value: true }
  if (raw === 'false') return { kind: 'literal', value: false }
  if (/^-?\d+$/.test(raw)) return { kind: 'literal', value: Number(raw) }
  if (/^"(.*)"$/.test(raw)) return { kind: 'literal', value: raw.slice(1, -1) }
  if (raw.includes('TSUnknown')) return { kind: 'unset' }
  return { kind: 'conditional', note: raw.replace(/^diagnostics\.|^core\./, '') }
}

async function fetchDecls(tag) {
  const url = `https://raw.githubusercontent.com/microsoft/typescript-go/${tag}/internal/tsoptions/declscompiler.go`
  const res = await fetch(url)
  if (!res.ok) throw new Error(`Fetch failed (${res.status}): ${url}`)
  return { url, text: await res.text() }
}

// --- source of truth 2: live compiler probes ---------------------------------------------

class Probe {
  constructor(tsc) {
    this.tsc = tsc
    this.dir = mkdtempSync(join(tmpdir(), 'tsconfig-audit-'))
    writeFileSync(join(this.dir, 'index.ts'), 'export const probe = 1;\n')
  }

  run(compilerOptions, flag) {
    const cfg = { compilerOptions, files: ['index.ts'] }
    writeFileSync(join(this.dir, 'tsconfig.json'), JSON.stringify(cfg))
    try {
      const out = execFileSync(this.tsc, ['-p', 'tsconfig.json', flag], {
        cwd: this.dir, stdio: 'pipe', encoding: 'utf8', env: { ...process.env, TS_LOCALE: 'en' },
      })
      return { ok: true, out }
    } catch (e) {
      return { ok: false, out: `${e.stdout ?? ''}${e.stderr ?? ''}` }
    }
  }

  diagnose(compilerOptions) {
    return this.run(compilerOptions, '--noEmit').out
  }

  showConfig(compilerOptions) {
    const r = this.run(compilerOptions, '--showConfig')
    try {
      return JSON.parse(r.out).compilerOptions ?? {}
    } catch {
      return null
    }
  }

  cleanup() {
    rmSync(this.dir, { recursive: true, force: true })
  }
}

function probeRemovals(probe) {
  const removed = {}
  const removedValues = {}
  const accepted = new Set()
  for (const [option, value] of REMOVAL_PROBES) {
    // Pair module values with a compatible moduleResolution, otherwise the real removal
    // diagnostic is masked by TS5095 (bundler requires module preserve/commonjs/es2015+).
    const extra = option === 'module' ? { moduleResolution: 'node16' } : {}
    const text = probe.diagnose({ [option]: value, ...extra })
    const optionRemoved = new RegExp(`TS5102: Option '${option}' has been removed`).test(text)
    const valueRemoved = /TS5108: Option '[^']+' has been removed/.test(text)
    const suggestion = text.match(/^\s+Use '(.+)' instead\.$/m)?.[1] ?? null

    if (optionRemoved) removed[option] = { removedIn: '7.0', suggestion }
    else if (valueRemoved) (removedValues[option] ??= []).push({ value, suggestion })
    else if (!/error TS/.test(text)) accepted.add(`${option}:${JSON.stringify(value)}`)
  }

  // "Locked" means the compiler leaves exactly one legal value, so writing it is a no-op.
  // That is only true when the opposite boolean is a hard error -- an option that accepts
  // both values (stableTypeOrdering does) is not locked, however the release notes read.
  const lockedValues = {}
  for (const [option, entries] of Object.entries(removedValues)) {
    const bools = entries.map((e) => e.value).filter((v) => typeof v === 'boolean')
    if (bools.length !== 1) continue
    const only = !bools[0]
    if (accepted.has(`${option}:${JSON.stringify(only)}`)) lockedValues[option] = only
  }
  return { removed, removedValues, lockedValues }
}

function probeEnums(probe) {
  const enums = {}
  for (const option of ENUM_PROBES) {
    const text = probe.diagnose({ [option]: '__bogus__' })
    const list = text.match(/must be: (.+?)\.\s*$/m)?.[1]
    if (list) enums[option] = list.split(',').map((s) => s.trim().replace(/^'|'$/g, ''))
  }
  return enums
}

function probeImplications(probe) {
  const implications = {}
  for (const seed of IMPLICATION_PROBES) {
    const [option, value] = Object.entries(seed)[0]
    const effective = probe.showConfig(seed)
    if (!effective) continue
    const implied = {}
    for (const [k, v] of Object.entries(effective)) {
      if (k !== option) implied[k] = v
    }
    if (Object.keys(implied).length === 0) continue
    if (typeof value === 'boolean') implications[option] = { whenTrue: implied }
    else (implications[option] ??= { byValue: {} }).byValue[value] = implied
  }
  return implications
}

// --- assembly -----------------------------------------------------------------------------

const tsc = findTsc()
const tsVersion = execFileSync(tsc, ['--version'], { encoding: 'utf8' }).trim().replace(/^Version\s+/, '')
const major = Number(tsVersion.split('.')[0])
if (!Number.isFinite(major) || major < 7) {
  console.error(`Refusing to generate from TypeScript ${tsVersion}. Install typescript@7 first.`)
  process.exit(1)
}

const tag = arg('--tag', `typescript/v${tsVersion}`)
console.error(`compiler: ${tsc} (${tsVersion})`)
console.error(`declarations: ${tag}`)

const decls = await fetchDecls(tag)
const options = parseGoDecls(decls.text)
if (options.length < 50) throw new Error(`Parsed only ${options.length} options; declscompiler.go format changed.`)

const probe = new Probe(tsc)
let payload
try {
  const { removed, removedValues, lockedValues } = probeRemovals(probe)
  const enums = probeEnums(probe)
  const implications = probeImplications(probe)

  // `moduleResolution`'s default depends on `module`. --showConfig exposes the node16/node18/
  // node20/nodenext cases (they land in `implications`) but not the "otherwise bundler"
  // fallback, so that one is transcribed from the compiler's own default description and
  // asserted against it -- a wording change fails loudly instead of going quietly stale.
  const MR_NOTE = 'X_nodenext_if_module_is_nodenext_node16_if_module_is_node16_or_node18_otherwise_bundler'

  const defaults = {}
  const conditionalDefaults = {}
  for (const o of options) {
    if (o.commandLineOnly) continue
    if (o.declaredDefault.kind === 'literal') defaults[o.name] = o.declaredDefault.value
    else if (o.declaredDefault.kind === 'conditional') conditionalDefaults[o.name] = o.declaredDefault.note
  }

  // Probe-verified overrides. The declared default is a help string and is wrong for these.
  const verified = probeVerifiedDefaults(probe)
  Object.assign(defaults, verified)
  // A probed default supersedes the declared one, so drop the losing entry rather than
  // shipping both. `rootDir` otherwise lands in `defaults` as `.` and in
  // `conditionalDefaults` as "Computed from the list of input files" -- two contradictory
  // answers in one file, with nothing marking which one won.
  for (const name of Object.keys(verified)) delete conditionalDefaults[name]

  const derivedDefaults = {}
  if (conditionalDefaults.moduleResolution === MR_NOTE) {
    derivedDefaults.moduleResolution = {
      fallback: 'bundler',
      explicitByModule: Object.keys(implications.module?.byValue ?? {}),
    }
  } else {
    console.error(
      'WARNING: moduleResolution default description changed upstream; derived default skipped.\n' +
        `  expected: ${MR_NOTE}\n  got:      ${conditionalDefaults.moduleResolution}`,
    )
  }

  payload = {
    $generated: 'scripts/refresh-options.mjs -- do not edit by hand',
    tsVersion,
    generatedFrom: { declarations: decls.url, probedCompiler: tsc },
    knownOptions: options.filter((o) => !o.commandLineOnly).map((o) => o.name).sort(),
    commandLineOnly: options.filter((o) => o.commandLineOnly).map((o) => o.name).sort(),
    removed,
    removedValues,
    legacyRemoved: LEGACY_REMOVED,
    lockedValues,
    defaults,
    // Declared defaults that are wrong in the option table and were corrected by probing
    // the real compiler. Recorded so a future reader knows these are not from the source.
    probeVerifiedDefaults: Object.keys(verified),
    derivedDefaults,
    conditionalDefaults,
    implications,
    enums,
    // Read by bundlers, test runners, ts-node and IDEs independently of tsc. A clean
    // typecheck after dropping these does not prove runtime resolution still works.
    externalConsumers: ['baseUrl', 'paths', 'rootDirs', 'moduleSuffixes', 'customConditions'],
    // Never reported as redundant even when the value matches the TS7 default.
    keepList: {
      strict: 'Explicit `true` documents intent, and stricter checks are planned for future releases.',
      target:
        'The TS7 default floats to the newest stable ECMAScript version, so it changes under you on a compiler upgrade. An explicit target pins emit semantics.',
      module:
        'Emit format is a deployment contract, not a detail worth inferring. Keep it explicit even when it matches the current default.',
      lib: 'Explicit `lib` pins the ambient surface. It often matches what `target` implies, but dropping it is only safe when `target` is pinned too, and it is the wrong thing to drop when the list was deliberately narrowed or widened (e.g. adding DOM).',
    },
  }
} finally {
  probe.cleanup()
}

function probeVerifiedDefaults(p) {
  const out = {}
  // rootDir declares "Computed from the list of input files" but 7.0 fixes it at ".".
  const dir = p.dir
  writeFileSync(join(dir, 'tsconfig.json'), JSON.stringify({ compilerOptions: {}, files: ['index.ts'] }))
  const empty = p.showConfig({})
  if (empty && !('rootDir' in empty)) out.rootDir = '.'
  out.types = []
  return out
}

writeFileSync(OUT, `${JSON.stringify(payload, null, 2)}\n`)
console.error(
  `wrote ${OUT}\n` +
    `  options=${payload.knownOptions.length} removed=${Object.keys(payload.removed).length} ` +
    `removedValues=${Object.keys(payload.removedValues).length} ` +
    `implications=${Object.keys(payload.implications).length} defaults=${Object.keys(payload.defaults).length}`,
)
