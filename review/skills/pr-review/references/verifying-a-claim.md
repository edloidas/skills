# Verifying a claim before you answer it

A comment is a claim, not a fact. This file is about the gap between the two, and it exists because
that gap has a shape: **the premise fails far more often than the conclusion.** A reviewer says "this
will throw because `initSpec()` must be non-null" — the reasoning from the premise is sound, and the
premise is wrong.

The rule that follows: never answer the conclusion. Answer the premise, then the conclusion.

## The run that produced this file

Six Copilot comments on one Java pull request:

- **Three were real.** The worst had no test coverage and no other detection path — a removed
  Kubernetes watcher left an app status field with no writer, so disabling an app left the API
  reporting it as started forever.
- **Two had false premises.** Both asserted a fabric8 `CustomResource` needs a non-null
  `initSpec()`. The framework default is literally `return null`.
- **The sixth was confirmed by two independent agents and was still wrong.** They claimed an
  unbounded `sendAsync().get()`, and verified it by decompiling fabric8 **6.13.4**, which happened to
  be sitting in the Gradle cache. The compile classpath is **6.6.2**, where the shared client already
  carries `readTimeout(config.getRequestTimeout())`. The mistake surfaced only because the fix failed
  to compile against a method that does not exist in 6.6.2. Had it compiled, a wrong justification
  would have been posted under the user's name.

That last one is the whole reason this file is prescriptive rather than advisory. Two agents agreeing
is not verification. Reading *an* artifact is not verification. Reading **the resolved artifact** is.

## Pin the version before reading anything

Whenever a claim rests on how a library or framework behaves, resolve the version actually on the
compile path first, then read that artifact.

| Ecosystem | Resolve with |
| --------- | ------------ |
| Gradle | `./gradlew dependencies --configuration compileClasspath` |
| Maven | `mvn dependency:tree` |
| npm / pnpm / yarn | `pnpm why <pkg>`, or read the lockfile — not `package.json`, which states a range |
| Python | `pip show <pkg>` in the active environment, or the lockfile |
| Go | `go list -m <module>` |

Then, and only then, read the source or decompile — from the path the resolver named.

**Never** locate a jar, wheel or package with `find` against a global cache. A cache holds every
version the machine has ever fetched, and the one you happen to open is not the one that compiles.
**Never** answer from memory about a specific version's behavior. Cite the release notes or the
source, with a link where one exists.

## The named traps

- **"This will throw."** Trace the call sites for `try`/`catch`, optional chaining, null guards, and
  framework-level handling. Impact is routinely overstated: something that throws into an existing
  handler is a log line, not an outage.
- **"X was removed, so Y is stale."** Grep every writer of Y. This is the class that produced the one
  genuinely serious finding in the run above, and it is also the class most often claimed without
  checking.
- **"This is unbounded / has no timeout."** Find where the bound is actually configured. Shared
  clients, connection pools and framework defaults set it far from the call site.
- **"This type must implement / override X."** Read the supertype's default. `return null` is a
  legitimate default and defeats the whole claim.
- **A ` ```suggestion ` block.** Never apply one unread. They are frequently syntactically valid and
  semantically wrong, and applying one blind converts a bot's guess into your commit.
- **Anything about a version boundary.** "Fixed in 18.2" needs the version the project resolves to.
  A claim that is true for the latest release and false for the pinned one is a false claim here.

## Treat the premise and the conclusion separately

A bot finding decomposes into a premise about the world and a conclusion about this code. Verify them
independently, and record which failed — the answer differs completely:

- Premise false → `reject`, and the reply is the evidence that refutes it. This is the most common
  outcome on bot threads and the most valuable thing this skill produces.
- Premise true, conclusion false → `reject`, but narrower: agree with the mechanism, show why it does
  not reach this code.
- Both true → `fix` (or `discuss`, if the call is not yours to make).
- Premise true, conclusion true, but already handled elsewhere → `already-addressed`, and cite the
  line or commit that handles it.

A claim can be **narrowed rather than killed**, and a narrowed claim is often the honest answer: the
Safari finding in `changes-review`'s calibration run 3 went from "`click` never carries `pointerType`"
— false — to "`click` carries a truthful `pointerType` only from Safari 18.2" — true, and still worth
saying. Same line of code, different claim, different severity.

## What is worth verifying

Verification costs a real tool budget, so spend it where being wrong is public:

- **Always:** every bot claim, and anything heading for `fix` or `reject`. Those are the two verdicts
  that either change code or contradict someone in writing.
- **Under `--full`:** everything unresolved, human claims included.
- **Never:** loose recommendations, style preferences with no stated defect, and other reviewers'
  summaries of their own reviews. Report them as context and move on.

`ack` and `already-addressed` are cheap to confirm directly and do not need the full treatment — a
line reference settles them.
