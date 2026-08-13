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
// right — Safe migration: same bean API, same return semantics
@Component(immediate = true)
class DumpManager {
    fun list(): String = TODO()
    fun delete(name: String): Boolean = TODO()
}

// wrong — Hidden contract change during migration
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
// right — Final concrete component
@Component(immediate = true)
class ExportManager

// wrong — No framework benefit, adds confusion
@Component(immediate = true)
open class ExportManager

// wrong — SCR should create the instance, not Kotlin
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
// right — Stable interop
fun generateToken(subject: String, keyId: String, privateKeyPath: String, expirationSeconds: Int): String

// wrong — Kotlin-only surface area
fun generateToken(privateKeyPath: String, expirationSeconds: Int = 30): Result<String>
```

### Do not reshape Java/JS-facing APIs just to be more idiomatic

Sealed hierarchies and enum wrappers are good Kotlin and wrong here. A bean API consumed from
Java or JS keeps the shape those callers can use.

### Use Kotlin syntax that still maps cleanly to Java APIs

```kotlin
// right — Kotlin array literal syntax for OSGi annotations
@Component(property = ["key=value", "service.ranking:Integer=100"])

// right — Java Class when OSGi / reflection APIs expect it
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
// right — Known-safe Java API
private fun dumpDir(): Path =
    HomeDir.get().toFile().toPath().resolve("data").resolve("dump")

// right — Convert uncertain Java result once
val xpVersion: String = props.getProperty("xp.version") ?: ""
val entry = findDumpJson(zip) ?: return fallbackJson

// wrong — Platform type leaks deeper into the function
val entry = findDumpJson(zip)
return parseZipEntry(entry)

// wrong — `!!` is not a nullability strategy
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
// right — Explicitly synchronized cache mutation
@Volatile
private var cachedKeyPath: String? = null

@Synchronized
private fun loadPrivateKey(path: String): RSAPrivateKey = TODO()

// wrong — Unsynchronized mutable cache in a shared component
private var cachedKeyPath: String? = null
private var cachedKey: RSAPrivateKey? = null
```

### Distinguish core failures from best-effort work
> **Report, never auto-apply.** This section changes behavior. Surface it as a finding
> and let a reviewer decide — a cleanup pass must not ship a semantics change.

Follow the same discipline as the current Java code:

- Primary operations (`list`, `delete`, token generation, file reads that define the result) should fail loudly with contextual messages.
- Sidecar metadata, cleanup, telemetry, and other non-critical work may be best-effort, but only swallow exceptions deliberately and document why.

```kotlin
// right — Primary path: preserve context
throw RuntimeException("Failed to list exports: ${e.message}", e)

// right — Best-effort path: explicitly non-critical
catch (_: IOException) {
    // ? Metadata is non-critical; export itself already succeeded
}
```

## Filesystem & Boundary Formats

### Derive child paths safely before delete/write operations
> **Report, never auto-apply.** This section changes behavior. Surface it as a finding
> and let a reviewer decide — a cleanup pass must not ship a semantics change.

Never trust names that become file paths. `resolve(name).normalize()` + `startsWith(base)` is **not sufficient**: a path starts with itself, so names like `"."` or `"foo/.."` normalize to the base directory and pass the check — turning a single-entry delete into a wipe of the whole directory. Multi-segment names (`"a/b"`) also pass.

Require the resolved path to be a direct child whose file name is exactly the input:

```kotlin
// right — Single shared helper, used by every name-taking file operation
internal fun Path.resolveChildEntry(name: String): Path? =
    try {
        val base = normalize()
        val target = base.resolve(name).normalize()
        if (target.parent == base && target.fileName.toString() == name) target else null
    } catch (_: InvalidPathException) {
        null
    }

val target = exportDir.resolveChildEntry(name) ?: return false

// wrong — Accepts ".", "foo/..", and "a/b"
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

// wrong — Recompiled every call
fun readNodeCount(content: String): Long {
    val regex = """"nodeCount"\s*:\s*(\d+)""".toRegex()
    return regex.find(content)?.groupValues?.get(1)?.toLongOrNull() ?: -1
}
```

### Manual JSON requires a dedicated escaping helper
> **Report, never auto-apply.** This section changes behavior. Surface it as a finding
> and let a reviewer decide — a cleanup pass must not ship a semantics change.

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
