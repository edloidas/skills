# Publishing a review

The report this skill produces and the comment you post to the author are **different artifacts with
an inverted rule**, not two formats of the same thing. The report is for whoever called the skill:
severity, confidence and reviewer counts are their decision inputs. The moment the audience is the
person who wrote the code, those same labels are noise, and unjudged output costs that person their
time.

So the report says *never soften, you are the messenger not the judge*. This phase says the opposite:
drop, narrow and re-attribute before you speak. Both are correct for their own audience. Read
`calibration.md` run 3 for the run that produced this file — 7 findings, 4 published, and the one
rated highest was the most wrong.

## The one thing this file exists to prevent

Prose hides missing evidence. The labelled format exposes it: a finding with no demonstration still
has to fill in a `Concretely:` list and a confidence level, and a reader sees the hole. The same
claim written as three fluent sentences reads exactly like a verified one.

A model handed a style example will reproduce the cadence and invent the substance. That failure is
worse than the format it replaces. Everything below is arranged so the register comes out as a
**byproduct of having done four things**, and it is only honest when they were actually done:

1. The claim was demonstrated.
2. Its origin was attributed — this branch, or the base.
3. The reader was given a way to see it themselves.
4. The decision was left with the author.

## The gate

Mechanical on purpose. It is what stops composition from being style mimicry.

- **No demonstration, no section.** A finding that survives verification but carries no reproduction
  the reader can run gets one sentence in the closing paragraph, flagged as unverified with the
  reason. Never a section of its own.
- **No attribution, no section.** Every claim states whether this branch introduced the blamed code
  or the base already had it. `git blame` and `git diff <base>...HEAD` settle it; there is no third
  answer.
- **No section for a finding the verify phase killed**, however good the prose would be.
- **At most four sections.** More than four means clustering failed — go back and group by cause.

## Attribute, before composing

For each surviving finding, establish origin against the base:

```bash
git blame -L <line>,<line> <base> -- <path>     # was this line already here
git diff <base>...HEAD -- <path>                # is this hunk new on the branch
```

Three outcomes, and they are three different asks of the author:

| Origin | How the claim changes |
| ------ | --------------------- |
| New on this branch | Publish as written |
| Pre-existing on the base | Reclassify — say so in the claim, or drop it. Published unattributed, a pre-existing gap reads as a regression the author caused |
| Partly both | Narrow the claim to the part that is new, and say which part that is |

On the calibration run this step alone overturned or narrowed two of seven findings. Reviewers are
blind to the base by design, so they cannot do it — only this phase can.

## Length

The example below is the **serious** finding, and it is the longest thing this phase should ever
produce. Budget by what the author has to do, not by severity words:

| Kind | What it gets | Rough size |
| ---- | ------------ | ---------- |
| Needs a change before ship | Heading, code quote, mechanism, consequence in the issue's own terms, reproduction, fix offered | 250–350 words |
| A judgement call | A paragraph plus a measurement or reproduction, and the tradeoff | 100–150 words |
| Minor | Two sentences, grouped with other minors or folded into the closing paragraph | no section |
| Unverified residue | One sentence in the closing paragraph, with why it could not be shown | no section |

If the whole comment runs past roughly 900 words on a diff of a few hundred lines, the problem is
clustering, not the budget.

## What comes out, and what goes in

**Out:** finding IDs, severity words, confidence levels, reviewer counts, `demonstrated by
execution` / `reasoned` tags, the `Concretely:` scaffolding, and the `Scope:` / `Reviewers:` /
`Lenses:` / `Verification:` headers. Severity survives as **prose and placement** — the serious one
goes first and is introduced as the one needing a change before ship.

**In:**

- **A lead paragraph that earns standing.** What was run, and what works. A reviewer who has
  demonstrated they ran the thing is answerable differently from one who has read it. If a previous
  round's findings were fixed, say so here first.
- **A heading per finding, written as the claim in a sentence.** Not a noun phrase, not a label.
- **A code quote**, two or three lines, with a `// path:line` comment on the first line.
- **A runnable reproduction or a measurement.** Screenshots do not survive into a PR comment;
  numbers and console snippets do. `the 280px submenu spans 295 to 575 on a 320px-wide viewport` is
  a reproduction. "The submenu is clipped" is not.
- **The attribution clause**, inline in the claim.
- **A suggested fix, offered as an option.** The author's PR, the author's call.
- **An explicit withdrawal** of anything an earlier round of this review got wrong. A review that
  visibly corrects itself is cheaper to trust than one that never has to.
- **A closing paragraph** on what held up, including the tooling result and any unverified residue.

## Order

By what the author should act on first, never by severity. Open with one sentence saying which
findings need a change and which are judgement calls, so a reader knows the shape before reading the
sections.

Group by cause, not by symptom site. Three findings about the same block of code publish as one
section with the other two as reasons not to land it.

## Where to post, and under whose name

**Show the comment and get an answer before posting.** This is the one outward-facing thing the
skill does, published under the user's account to another person, and the text was generated rather
than written by them. `--comment` authorizes the phase; it does not authorize the words. Offer post
as written (recommended) / edit first / discard, and fall back to the same question as a short
numbered list in chat where the host has no structured prompt. Print and stop rather than posting
when nobody is there to answer.

Post as an **issue comment**, not a review: GitHub refuses a review on your own PR, and the common
case is a branch you opened.

```bash
gh pr comment <N> --body-file <file>
```

Attribution policy is repo-local and genuinely contradictory across repos — `enonic/npm-enonic-ui`
prescribes a `<sub>*Drafted with AI assistance*</sub>` footer and this repository's `CLAUDE.md`
forbids exactly that line. Neither can be hardcoded. Resolve `CLAUDE.md` / `AGENTS.md` in the
**target** repo and follow what it says. Where it says nothing, add one short sentence noting the
review was automated and may contain errors.

Voice is not free of the author. Both calibration rounds read as first-person prose from the account
that posted them. The rules above are all about **substance** — demonstration, attribution,
withdrawal, open decision — and those transfer to anyone. Cadence does not, so do not prescribe it
beyond *write plainly and lead with the point*, which `write:markdown-writing` already says.

## Publishing as a review (someone else's pull request)

On a branch you did not author, publication is a GitHub review rather than one comment: the findings
sit next to the code and the whole thing carries a verdict. Everything above still applies — the
gate, the attribution, the length budget. Only the container changes.

**One inline comment per finding**, anchored to the line it concerns. Minors do not each get one:
group them into a single comment anchored at the first of them, and open it by saying so — `Three
small ones, grouped.` A reader counts comments, and eight reads as a review where fifteen reads as a
wall.

**Anchoring is constrained by the diff.** A comment can only sit on a line the pull request touches.
Use `side: RIGHT` for added or changed lines, `side: LEFT` for a claim about a line the branch
removed. When a finding's line falls outside the diff — a consequence in a file the branch never
touched — it belongs in the body. Never anchor it to the nearest line the API happens to accept:
that sends the reader to code that is not the problem.

**The body is not a summary of the inline comments** and never repeats a finding's text. It carries
only what the whole review can say:

- what was run, and what held up — the standing paragraph, same rule as above
- how the findings group, in a sentence or two
- what was deliberately excluded, and why
- which ones you would not merge without
- the closing paragraph, with unverified residue and the tooling result

**The verdict follows from what survived**, never from how many findings there are:

| What survived | Event |
| ------------- | ----- |
| At least one finding you would not merge without | `REQUEST_CHANGES` |
| Findings, but every one a judgement call | `COMMENT` |
| Nothing | `APPROVE` |

`COMMENT` is the honest verdict for a review that found real things, none of them blocking. Do not
reach for `REQUEST_CHANGES` to signal effort, and do not `APPROVE` around an open question — the
middle option exists for exactly that.

Check `viewerCanUpdate` before composing something you cannot submit. Build the payload as JSON and
submit once, so the comments and the verdict land together rather than as a trickle of notifications:

```bash
gh api repos/<owner>/<repo>/pulls/<N>/reviews --input review.json
```

```json
{
  "event": "REQUEST_CHANGES",
  "body": "<the review body>",
  "comments": [
    { "path": "src/components/app-root/app-root.tsx", "line": 71, "side": "RIGHT", "body": "<finding>" }
  ]
}
```

### The body that shipped, annotated

From calibration run 4 — eight inline comments, `REQUEST_CHANGES`, abridged here:

````markdown
I pulled the branch and worked through the AppRoot story in Storybook, reading computed styles
rather than class names. The core of this holds up. The portal plumbing resolves the way the prop
doc describes, the theme class lands inside the root so `dark:` utilities actually match, and the
scroll fix is doing real work — I confirmed a scroll inside the root is invisible to
`window.addEventListener('scroll', fn, true)` and visible to the same listener on the root.

What I found falls into two groups. Three are shadow-root behaviours the code gets wrong or does
not cover, and I could reproduce each one. The rest are scope questions against the issue — things
it asks for that are not here, and things here it did not ask for.

I started on the earlier commit and re-read everything against the current head first, so this
excludes the `.light` token selector — reverting that and making `theme='light'` emit nothing is the
right call, and one consequence of it is in the grouped comment at the end.

One comment per finding, next to the code it concerns, with the small ones grouped at the end. The
two I would not merge without are the stylesheet situation on `AppRoot` and the portal layer's
containing block. Both are reproducible, and both land on the acceptance case the issue names.
````

| Part | Why it is there |
| ---- | --------------- |
| "I pulled the branch and worked through the AppRoot story… reading computed styles rather than class names" | Standing, earned in the first clause. It names the method, and the method is the reason to believe the rest |
| "The core of this holds up… the scroll fix is doing real work" | What works, before what does not. A review that concedes first is answerable; one that opens on defects is a list of accusations |
| "What I found falls into two groups" | The shape, so a reader knows what is coming before they meet it |
| "so this excludes the `.light` token selector" | What was deliberately left out and why. Without it, a re-review reads as having missed something |
| "One comment per finding, next to the code it concerns" | Tells the reader where the rest of the review is. The body is a map, not a summary |
| "The two I would not merge without are…" | The verdict, in prose, before the API's verdict says the same thing. This is where severity survives |

Nothing in that body restates a finding. Every claim, measurement and reproduction lives in the
inline comment on the line it belongs to.

## A clean run

A review that found nothing still publishes, in one short paragraph: what was run, what held up, and
the tooling result. Never a section list of everything checked — on the calibration run a
"checked and clear" section drew no response at all beyond the closing sentence.

## Boundary with `write:markdown-writing`

That skill owns render target, readability, and GitHub Markdown mechanics. This file owns what a
review comment must **contain** and what it must **refuse to publish**. Point at it for the
mechanics rather than restating them here.

## Worked example, annotated

The annotations are the point. An unannotated example gets copied for its cadence.

This is the serious finding from calibration run 3, published as written:

````markdown
### The touch check only works where `click` is a `PointerEvent`

```tsx
// src/components/combobox/combobox.tsx:755
const isTouch = 'pointerType' in event && event.pointerType === 'touch';
```

This is correct in Chromium — I confirmed the handler really does receive a `PointerEvent` with
`pointerType` of `touch` or `mouse`, so the mechanism is sound and the earlier worry that `click`
never carries `pointerType` is simply wrong.

Safari is the problem. WebKit only made `click` a `PointerEvent` with a truthful `pointerType` in
**Safari 18.2**. So on iOS 16 and 17 the `in` guard fails, `isTouch` is `false`, and the input gets
focused on chevron tap exactly as before. On those versions the PR is a no-op for its own goal, and
iOS is the platform the issue is about.

You can see it without an old device — open **Examples / Basic** and run this in the console:

```js
const t = document.querySelector('[data-component="Combobox.Toggle"]');
t.dispatchEvent(new MouseEvent('click', { bubbles: true }));
```

That is the event shape those Safari versions deliver. The popup opens and the caret lands in the
search input — on a phone that is the keyboard coming up.

The fix is the `pointerdown` route: record `event.pointerType` in an `onPointerDown` and read the
recorded value in `onClick`. `pointerdown` has been a real `PointerEvent` with a correct
`pointerType` in Safari since 13, so it sidesteps the version gap entirely.
````

Reading it against the rules above:

| Part | Why it is there |
| ---- | --------------- |
| The heading | The claim as a sentence, not a noun phrase or a label |
| The code quote | Three lines with a `file:line` comment — enough to locate, not enough to re-read the function |
| "This is correct in Chromium… is simply wrong" | **The withdrawal, first.** It kills the review's own earlier overstatement. This concession is what makes the next paragraph credible |
| "Safari is the problem… **Safari 18.2**" | The mechanism, with the version that draws the boundary |
| "On those versions the PR is a no-op for its own goal" | The consequence **in the issue's own terms**. The finding is only serious because iOS is what the PR is for |
| The console snippet | A reproduction runnable by someone with no mobile device. The one thing that made this finding land |
| "The fix is the `pointerdown` route" | Offered, not demanded. No verdict |

No severity label appears anywhere, and a reader can still tell it is the serious one — because it
was placed first and introduced as the one needing a change before ship.

**What the same run refused to publish**, and why each refusal matters more than the example:

- A finding that the value button focuses the input on tap. Untouched base code, and the issue asks
  for exactly that behavior. Publishing it would have asked the author to defend their own spec.
- A finding blaming a story description for asserting viewport clamping the positioning hook does
  not implement. True, but the missing clamp is pre-existing and only the description is new.
  Published unattributed it reads as a regression.
- The same Safari finding, in its original form, rated **critical** on the false premise that
  `click` never carries `pointerType` in any browser. Measurement refuted it. Same line of code,
  different claim, different severity — and it was the highest-rated finding in the run.

Three of seven would have damaged the review's credibility, and the one rated highest was the most
wrong. That is the reason for the gate.
