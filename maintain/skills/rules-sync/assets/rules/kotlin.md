---
paths:
  - '**/*.kt'
---

# Kotlin Coding Standards

These rules optimize for Enonic XP / OSGi code that is called from Java and XP server-side TypeScript. Prioritize predictable bytecode, stable cross-language boundaries, and small runtime surface area over clever Kotlin features.

## Migration First

### Preserve the Java-visible contract during Java -> Kotlin migrations

Keep public method names, arity, return types, nullability, and caller-visible behavior stable unless the task explicitly changes the contract.

```kotlin
// ✅ Safe migration: same bean API, same return semantics
@Component(immediate = true)
class DumpManager {
    fun list(): String = TODO()
    fun delete(name: String): Boolean = TODO()
}

// ❌ Hidden contract change during migration
@Component(immediate = true)
class DumpManager {
    fun list(): List<DumpEntry> = TODO()
    fun delete(name: String?): Boolean? = TODO()
}
```

Keep existing "best effort" vs "hard failure" behavior intact. If the Java version returned `false` for invalid input or wrapped `IOException` with a contextual `RuntimeException`, the Kotlin version should do the same unless the task says otherwise.

## OSGi & Enonic XP

### Component classes stay regular final classes

SCR instantiates components directly. Use plain `class` declarations. Do not make components `open`, `abstract`, or Kotlin `object`s.

```kotlin
// ✅ Final concrete component
@Component(immediate = true)
class ExportManager

// ❌ No framework benefit, adds confusion
@Component(immediate = true)
open class ExportManager

// ❌ SCR should create the instance, not Kotlin
@Component(immediate = true)
object ExportManager
```

### Public bean APIs stay Java/JS-friendly

These classes are called through Java reflection and XP's bean bridge. Public methods must compile to boring, predictable JVM signatures.

- Use simple boundary types: `String`, `Boolean`, `Int`, `Long`, `Path`, JDK collections, or explicit JSON strings when the caller already expects JSON.
- Do not expose `Result`, `Pair`, `Triple`, `Sequence`, `Flow`, `suspend`, unsigned types, value classes, or function types at public boundaries.
- Do not rely on default arguments or named arguments for public methods. Java and the XP bean bridge do not see Kotlin call-site sugar.
- If multiple arities are required, add explicit overloads or separate methods on purpose.

```kotlin
// ✅ Stable interop
fun generateToken(subject: String, keyId: String, privateKeyPath: String, expirationSeconds: Int): String

// ❌ Kotlin-only surface area
fun generateToken(privateKeyPath: String, expirationSeconds: Int = 30): Result<String>
```

### Use Kotlin syntax that still maps cleanly to Java APIs

```kotlin
// ✅ Kotlin array literal syntax for OSGi annotations
@Component(property = ["key=value", "service.ranking:Integer=100"])

// ✅ Java Class when OSGi / reflection APIs expect it
val clazz: Class<ExportManager> = ExportManager::class.java
```

### Keep the runtime surface small

Do not add libraries that complicate OSGi packaging or add reflection-heavy runtime behavior unless the task explicitly requires them.

- No `kotlinx.serialization`, Jackson, or Gson for these small utility beans.
- No `kotlin-reflect` unless a feature truly depends on it.
- No coroutines / `Flow` in simple XP component code unless the module already uses them as a deliberate architectural choice.

## Java Interop & Nullability

### Normalize platform types at the boundary

Most XP Java APIs expose platform types (`T!`). Resolve nullability once, close to the call, then continue with proper Kotlin types.

```kotlin
// ✅ Known-safe Java API
private fun dumpDir(): Path =
    HomeDir.get().toFile().toPath().resolve("data").resolve("dump")

// ✅ Convert uncertain Java result once
val xpVersion: String = props.getProperty("xp.version") ?: ""
val entry = findDumpJson(zip) ?: return fallbackJson

// ❌ Platform type leaks deeper into the function
val entry = findDumpJson(zip)
return parseZipEntry(entry)

// ❌ `!!` is not a nullability strategy
val node = repo.getNode(nodeId)!!
```

Check the Java source when possible. When unsure, prefer `?:`, `orEmpty()`, or an early return over `!!`.

## State, Concurrency, and Lifecycle

### OSGi components are shared singletons

Treat component instances as multi-call, potentially concurrent objects.

- Prefer stateless methods and `val` properties.
- If you cache mutable state, make the concurrency model explicit with `@Volatile`, `synchronized`, or concurrent data structures.
- Do not keep request-scoped data in fields.

```kotlin
// ✅ Explicitly synchronized cache mutation
@Volatile
private var cachedKeyPath: String? = null

@Synchronized
private fun loadPrivateKey(path: String): RSAPrivateKey = TODO()

// ❌ Unsynchronized mutable cache in a shared component
private var cachedKeyPath: String? = null
private var cachedKey: RSAPrivateKey? = null
```

### Distinguish core failures from best-effort work

Follow the same discipline as the current Java code:

- Primary operations (`list`, `delete`, token generation, file reads that define the result) should fail loudly with contextual messages.
- Sidecar metadata, cleanup, telemetry, and other non-critical work may be best-effort, but only swallow exceptions deliberately and document why.

```kotlin
// ✅ Primary path: preserve context
throw RuntimeException("Failed to list exports: ${e.message}", e)

// ✅ Best-effort path: explicitly non-critical
catch (_: IOException) {
    // ? Metadata is non-critical; export itself already succeeded
}
```

## Filesystem & Boundary Formats

### Derive child paths safely before delete/write operations

Never trust names that become file paths. `resolve(name).normalize()` + `startsWith(base)` is **not sufficient**: a path starts with itself, so names like `"."` or `"foo/.."` normalize to the base directory and pass the check — turning a single-entry delete into a wipe of the whole directory. Multi-segment names (`"a/b"`) also pass.

Require the resolved path to be a direct child whose file name is exactly the input:

```kotlin
// ✅ Single shared helper, used by every name-taking file operation
internal fun Path.resolveChildEntry(name: String): Path? =
    try {
        val base = normalize()
        val target = base.resolve(name).normalize()
        if (target.parent == base && target.fileName.toString() == name) target else null
    } catch (_: InvalidPathException) {
        null
    }

val target = exportDir.resolveChildEntry(name) ?: return false

// ❌ Accepts ".", "foo/..", and "a/b"
val target = exportDir.resolve(name).normalize()
if (!target.startsWith(exportDir)) return false
```

Derived sibling paths (`"$name.zip"`, `"$name.tmp"`) are safe to build with plain `resolve` only **after** `name` has passed the direct-child check. Do not concatenate paths as strings.

### Prefer Kotlin path helpers and `.use {}`

```kotlin
val content = metadata.readText()

Files.newDirectoryStream(dir).use { stream ->
    for (entry in stream) {
        // ...
    }
}
```

Use `kotlin.io.path` helpers for `readText`, `readBytes`, `writeText`, and `deleteIfExists` unless the Java API call is genuinely clearer.

### Manual parsing is only for tiny, owned formats

Regex-based extraction is acceptable for tiny, stable inputs such as:

- app-owned sidecar metadata files
- XP-generated key files with a few known fields

Do not grow ad-hoc regex parsing into a general JSON parser. If the input becomes nested, optional-heavy, or externally controlled, stop and reassess the approach instead of stacking more regexes.

### Compile regexes once, not per call

```kotlin
private val NODE_COUNT_REGEX = """"nodeCount"\s*:\s*(\d+)""".toRegex()

fun readNodeCount(content: String): Long =
    NODE_COUNT_REGEX.find(content)?.groupValues?.get(1)?.toLongOrNull() ?: -1

// ❌ Recompiled every call
fun readNodeCount(content: String): Long {
    val regex = """"nodeCount"\s*:\s*(\d+)""".toRegex()
    return regex.find(content)?.groupValues?.get(1)?.toLongOrNull() ?: -1
}
```

### Manual JSON requires a dedicated escaping helper

If a bean returns JSON as `String`, every dynamic string value must pass through one escaping function. Never interpolate raw values into JSON.

```kotlin
private fun String.escapeJson(): String = buildString(length + 8) {
    for (ch in this@escapeJson) {
        when (ch) {
            '\\' -> append("\\\\")
            '"' -> append("\\\"")
            '\n' -> append("\\n")
            '\r' -> append("\\r")
            '\t' -> append("\\t")
            else -> if (ch < ' ') append("\\u%04x".format(ch.code)) else append(ch)
        }
    }
}

fun jsonString(value: String): String = "\"${value.escapeJson()}\""
```

Prefer `buildString` and `joinToString` for manual JSON assembly. Do not drop to `StringBuilder` unless profiling proves it matters.

### Use `java.time` types at the boundary

Use `Instant` and `Duration` for timestamps and expirations. Serialize timestamps as ISO-8601 unless the caller explicitly expects another format.

## Reusable Kotlin Idioms

### Default to immutable values and file-local helpers

- Prefer `val` over `var`; introduce mutation only when it reflects real state changes.
- Prefer `private` top-level constants, regexes, and helper functions over `object Utils` or `companion object` when no instance state is needed.
- Keep helpers close to the file that owns the behavior; do not build extension/helper sprawl.

```kotlin
private const val METADATA_FILE = ".datakit-export.json"
private val NODE_COUNT_REGEX = """"nodeCount"\s*:\s*(\d+)""".toRegex()

private fun Path.readNodeCount(): Long = TODO()
```

### Use `require` and `check` only when throwing is the intended contract

They are good Kotlin tools, but only for programmer errors and violated invariants.

```kotlin
// ✅ Invalid API usage should fail fast
fun parsePem(pem: String): RSAPrivateKey {
    require(pem.isNotBlank()) { "PEM must not be blank" }
    return TODO()
}

// ✅ Internal impossible state
check(cachedKey != null) { "Private key cache was not initialized" }

// ❌ Do not replace business-level fallback behavior with exceptions
fun delete(name: String): Boolean {
    if (name.isEmpty()) return false
    return TODO()
}
```

### Expression bodies are good for tiny helpers, not as a style mandate

Use them when the whole function is genuinely one idea. Switch back to block bodies as soon as branching, local state, or exception handling appears.

```kotlin
private fun dumpDir(): Path =
    HomeDir.get().toFile().toPath().resolve("data").resolve("dump")
```

### Prefer private extension functions when they encode domain language

Extensions are useful for repeated local transformations. Keep them `private` unless they are broadly reusable and do not hide important side effects.

```kotlin
private fun String.escapeJson(): String = TODO()
private fun Path.lastModifiedInstantOrNull(): Instant? = TODO()
```

Do not use extensions to disguise heavyweight operations or mutate surprising state.

### Use `when` and sealed hierarchies for closed decision spaces

- Prefer `when` when branching on the same subject, enum, or sealed type.
- Prefer sealed interfaces/classes for internal states where exhaustiveness matters.
- Do not force sealed hierarchies or enum wrappers into Java/JS-facing bean APIs just to be more “Kotlin”.

### Avoid clever standard-library control flow

Kotlin offers many concise helpers, but brevity is not the goal.

- Use `takeIf`, `takeUnless`, `runCatching`, `associate*`, and nested scope functions only when they make the code more obvious than a plain `if`, local variable, or `try/catch`.
- Do not turn boundary code, file IO, crypto, or deletion logic into dense pipelines.

## Readability Over Cleverness

### Keep control flow flat

- Single-line guard clauses are preferred for invalid input and path-safety checks.
- Use at most one scope function in a chain. If the code needs `let { }.also { }.run { }`, extract locals.
- Prefer obvious local names over dense functional pipelines in filesystem, crypto, and boundary code.
