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
- **No attribution, no section.** Establish for every claim whether this branch introduced the
  blamed code or the base already had it. `git blame` and `git diff <base>...HEAD` settle it; there
  is no third answer. It is written into the claim only where the base had it — see **What comes
  out, and what goes in**.
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

Sizes are ceilings, not targets — a range with a floor gets filled to the floor. Budget by what the
author has to do, not by severity words:

| Kind | What it gets | Ceiling |
| ---- | ------------ | ------- |
| Needs a change before ship | The always-in ingredients, plus each conditional one whose trigger fires — **What comes out, and what goes in** | 200 words, code blocks excluded |
| A judgement call | One paragraph: the tradeoff, and the measurement that shows it | 80 words |
| Minor | Two sentences, grouped with the other minors in the closing paragraph | no section |
| Unverified residue | One sentence in the closing paragraph, with why it could not be shown | no section |

The worked example at the end of this file is a serious finding at about 140 words of prose; match
that shape rather than the ceiling. A whole comment past roughly 700 words on a diff of a few hundred
lines has a clustering problem, not a budget problem.

## What comes out, and what goes in

**Out:** finding IDs, severity words, confidence levels, reviewer counts, `demonstrated by
execution` / `reasoned` tags, the `Concretely:` scaffolding, the `Scope:` / `Reviewers:` /
`Lenses:` / `Verification:` headers, and the account of what was run — engines, probes, the tooling
result. Those are the operator's decision inputs and stay in the operator report; the author sees CI.
Severity survives as **placement**: the one needing a change before ship goes first and is
introduced as such.

**In, always:**

- **A heading written as the claim in a sentence.** Not a noun phrase, not a label.
- **The consequence first, in the issue's own terms, then the mechanism that produces it.** Real
  symbols from the code, plain words for everything else — "fails closed" is "when the check throws,
  the request is blocked": longer, and nothing to look up.
- **One reproduction or one measurement.** `the 280px submenu spans 295 to 575 on a 320px-wide
  viewport` is a measurement; "the submenu is clipped" is not. One — a second is a variant of the
  first. A frame may ride alongside a measurement (**Attaching a frame**), never replace it.

**In only when its trigger fires — otherwise absent:**

| Ingredient | Trigger |
| ---------- | ------- |
| A code quote, two or three lines, `// path:line` on the first | Issue-comment shape only. In review shape the comment sits on the line, and a quote repeats what GitHub already shows above it |
| The attribution clause, inline in the claim | The base already had the blamed code, or part of it. New on this branch is what a reader assumes and needs no sentence |
| A suggested fix, offered as an option | The fix is not the plain inverse of the claim. "The guard is inverted" needs no fix paragraph; "use `pointerdown` instead" does |
| An explicit withdrawal, one clause | An earlier round of this review said something this round found wrong. A review that visibly corrects itself is cheaper to trust |
| A lead paragraph | Two or more findings. One sentence on which need a change and which are judgement calls, one on what held up in the issue's terms. Standing is a clause inside it — `I ran the AppRoot story in Storybook` — never a paragraph: each reproduction below is the proof of method |
| A closing paragraph | Grouped minors or unverified residue exist. One sentence per minor, one for the residue with why it could not be shown |

## Order

By what the author should act on first, never by severity. Group by cause, not by symptom site:
three findings about the same block of code publish as one section, with the other two as reasons
not to land it. The lead paragraph's opening sentence gives the reader the shape before the sections
— its trigger and content are in **What comes out, and what goes in**.

## Where to post, and under whose name

**Show the text and get an answer before posting.** This is the one outward-facing thing the
skill does, published under the user's account to another person, and the text was generated rather
than written by them. `--comment` authorizes the phase; it does not authorize the words.

Show it **verbatim and complete**, in a fenced block — every word that would be posted, in the
message itself.
A summary of the comment, a description of what it covers, or a count of findings and a claim about
their content are all the wrong artifact: the reader is approving words, so words are what they
have to see. Then ask, once, in prose, as the last line of the message. Not a structured-choice
prompt — a modal fires before the reader has finished the report it interrupts, which is the wrong
order for the only decision here. Print and stop rather than posting when nobody is there to answer.

Post as an **issue comment**, not a review: GitHub refuses a review on your own PR, and the common
case is a branch you opened.

```bash
gh pr comment <N> --body-file <file>
```

### Attaching a frame

A finding settled by looking at something rendered can carry the frame it was settled by. Write the
image into the body as a normal local-path reference, at the point in the finding where the
reproduction sits — under the code quote, never in a gallery at the end:

```markdown
![the submenu clipped at the right edge of a 320px viewport](.tmp/screenshots/submenu-320.png)
```

Then pass the same path, once per file, with alt text after a `#`:

```bash
gh pr comment <N> --body-file <file> --attach '.tmp/screenshots/submenu-320.png#the submenu clipped at the right edge of a 320px viewport'
```

`gh` uploads the file and rewrites that reference in place, so the image lands where you put it. A
path you attach without referencing is appended at the end instead, which is the gallery this rule
exists to avoid.

- **One image per finding.** The cap is 50 per invocation and that is not a budget to spend; a
  comment carrying six frames reads the way fifteen inline comments read.
- **Alt text always, via the `#` form.** Without it the filename becomes the alt text, and
  `submenu-320.png` describes nothing to anyone reading with a screen reader. A video is the
  exception — it renders as a player and cannot take alt text at all.
- **Needs `gh` 2.99.0 or newer, and it does not work on GitHub Enterprise Server.** Check
  `gh --version` before composing a body that references a local path. Where either is missing,
  publish the measurement alone and say in the operator report that the frame could not travel.
- **Images and GIFs cap at 10 MB**; video depends on the target repo's plan. PNG, JPEG, GIF, WebP,
  SVG, MP4, MOV and WebM are accepted, nothing else.

**No frame goes out that the confirmation gate did not show.** The gate above shows the composed
text; name each attachment and its path there too, because an image is the one part of a comment
the approver cannot read in the body.

**No AI attribution footer, ever.** Not a `<sub>` line, not a session link, not a sentence noting
the review was automated. This used to resolve from the target repository's instruction file, which
kept the mechanism alive in a reference and let it come back; there is nothing to resolve now. The
review earns trust by naming its method and quoting what it observed, and a footer declaring who
typed it adds nothing a reader wanted. Where a target repo's instruction file prescribes one, it is
overridden here — say so if it comes up rather than silently complying.

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

**The body is not a summary of the inline comments** and never repeats a finding's text. It is the
lead and closing paragraphs from **What comes out, and what goes in** and nothing else: which
comments you would not merge without, how the rest group, what was deliberately excluded and why,
and unverified residue in one sentence. The account of what was run stays in the operator report.

**The verdict follows from what survived**, never from how many findings there are:

| What survived | Event |
| ------------- | ----- |
| At least one finding you would not merge without | `REQUEST_CHANGES` |
| Findings, but every one a judgement call | `COMMENT` |
| Nothing | `APPROVE` |

`COMMENT` is the honest verdict for a review that found real things, none of them blocking. Do not
reach for `REQUEST_CHANGES` to signal effort, and do not `APPROVE` around an open question — the
middle option exists for exactly that.

### `APPROVE` has its own shape

An approval is not a `REQUEST_CHANGES` with the findings deleted. It publishes **one body and no
inline comments** — the `comments` array is empty, and nothing carries a line anchor, a `file:line`
quote, a reproduction snippet, or a measured table. Everything above about anchoring, grouping
minors, and the body being a map rather than a summary applies to reviews that ask for something;
an approval asks for nothing, so there is nowhere for a reader to be sent.

Write it as a conclusion, in **two to four sentences**: that it was verified against the issue and
approved, and what holds up in behavioural terms — what a user can now do. No headings, no lists, no
observation about the code: anything the author would want flagged is a suggestion, and the next
paragraph says where suggestions go.

**What was run stays out of it.** The engines, the probe names, the clean tooling result — the
author sees CI, and the method earned *your* confidence, not theirs. It goes in the operator report.
A verification narrative inside an approval reads as asking for credit.

The whole body, on a run of the combobox branch where nothing blocking survived:

```markdown
Verified against #142 and approving. A chevron tap now opens the popup without raising the keyboard
on iOS 16 and 17 as well as 18, and a mouse click still lands the caret in the search input as before.
```

**Non-blocking suggestions do not ride along.** Withhold them, hand them to the operator as their
own block, and offer a follow-up issue. Anchoring a suggestion to an approved pull request asks the
author to reopen code nobody needs to revisit, and it makes the verdict ambiguous — an approval
carrying two asks is a `COMMENT` wearing the wrong label. If a suggestion genuinely should gate the
merge, it was never non-blocking and the verdict is wrong.

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

### Holding it as a draft

Omit `event` and the same endpoint creates a **pending** review instead of a submitted one:

```json
{
  "body": "<the review body>",
  "comments": [
    { "path": "src/components/app-root/app-root.tsx", "line": 71, "side": "RIGHT", "body": "<finding>" }
  ]
}
```

A pending review is visible only to the account that created it and notifies nobody; it sits on the
Files changed tab behind **Finish your review** until that account submits it. Create it without the
confirmation gate — the gate puts the words in front of a reader before they reach the author, and a
pending review does exactly that.

Keep the verdict out of the payload and put it in the report, one line:
`Recommended verdict: REQUEST_CHANGES — the containing-block finding blocks the issue's own
acceptance case.` The submitting user picks the event; a pre-labelled draft has made that choice for
them.

Everything else holds: the demonstration and attribution gate, the four-section cap, the length
budget, one inline comment per finding, minors grouped.

- One pending review per account per pull request; a second returns 422. Before composing, run
  `gh api repos/<owner>/<repo>/pulls/<N>/reviews --jq '.[] | select(.state=="PENDING") | .id'`. One
  found is the failure-table row; deleting it (`gh api -X DELETE .../reviews/<id>`) happens only when
  the user asks for it.
- The body rides on the pending review into the Finish your review box. Print it in the report as
  well, so nothing has to be recomposed if that box comes up empty.
- This works on your own pull request. GitHub blocks approving your own branch at submit time, not
  holding a draft on it — say in the report that `COMMENT` is the only event it will accept.
- No attachment, same as a submitted review (below).

Report the Files changed URL, the inline-comment count and the recommended verdict, then stop. Do not
submit it in the same run, and do not ask whether to submit — that answer comes later, from a person
who has read it.

**A review cannot carry an attachment.** `--attach` exists on `gh pr comment` and not on `gh api`,
so nothing submitted through this endpoint uploads a file. **Attaching a frame** above applies to
the issue-comment shape only. In review shape a visual finding publishes as its measurement, and
the frame stays in the operator report — do not post a separate comment to host the image and link
it from the review, which splits one review across two objects and notifies twice.

### The body that shipped, annotated

From calibration run 4 — eight inline comments, `REQUEST_CHANGES`. What shipped opened with a fuller
narrative of the method; this is the same body cut to the rules above:

````markdown
I ran the AppRoot story in Storybook against the current head. The portal plumbing, the theme class
and the scroll fix all hold — a scroll inside the root is invisible to a capturing `scroll` listener
on `window` and visible to one on the root, which is what the issue asked for.

Two of the eight comments I would not merge without: the stylesheet situation on `AppRoot` and the
portal layer's containing block. Both reproduce, and both land on the acceptance case the issue
names. Three more are shadow-root behaviours the code gets wrong; the small ones are grouped in one
comment at the end. This excludes the `.light` token selector — reverting it is the right call, and
its one consequence is in the grouped comment.
````

| Part | Why it is there |
| ---- | --------------- |
| "I ran the AppRoot story in Storybook against the current head" | Standing, in one clause, and the method is not narrated further — each inline comment carries its own reproduction |
| "The portal plumbing, the theme class and the scroll fix all hold" | What works, before what does not, in the issue's terms. One sentence, not a tour |
| "Two of the eight comments I would not merge without" | The verdict in prose, and where the rest of the review is. Severity survives here and nowhere else |
| "This excludes the `.light` token selector" | What was left out and why, so a re-review does not read as a miss |

Nothing in that body restates a finding. Every claim, measurement and reproduction lives in the
inline comment on the line it belongs to.

## A clean run

A review that found nothing publishes in the `APPROVE` shape above — the same two to four sentences
whether it goes out as a review or, on your own pull request, as an issue comment. Never a section
list of everything checked: on the calibration run a "checked and clear" section drew no response at
all beyond the closing sentence.

## When publication cannot finish

Every row ends the same way — print what was composed, post nothing. Publication is the one
outward-facing thing here, so the safe failure is always silence plus a full local copy.

| Situation | Action |
| --------- | ------ |
| Every finding fails the gate | Publish the clean-run paragraph, and tell the caller which findings were withheld and why |
| No pull request resolves for the branch | Print the composed text, and say no PR was found |
| The user declines, or does not answer | Print everything. A declined publication is a normal outcome, not a failed run |
| `--review` on a pull request the user authored | GitHub refuses it. Fall back to the issue-comment shape and say why |
| A draft was asked for and a pending review already exists | Print the composed text and the existing draft's id; create nothing, and never clear it to make room |
| A finding's line is outside the diff | Move it to the review body. Never anchor it to a nearby line the API happens to accept |
| No write access to the target repository | Print everything and say it cannot post. `viewerCanUpdate` answers this before the attempt |
| The review submits but a comment is rejected | Say which finding did not land and print it. Do not resubmit the whole review |
| An attachment is rejected — too large, wrong type, `gh` too old, Enterprise Server | Post the body with the local-path reference removed, and report which frame could not travel. Never post a body whose image reference did not resolve |

## Boundary with `write:markdown-writing`

That skill owns render target, readability, and GitHub Markdown mechanics. This file owns what a
review comment must **contain** and what it must **refuse to publish**. Point at it for the
mechanics rather than restating them here.

## Worked example, annotated

The annotations are the point. An unannotated example gets copied for its cadence.

This is the serious finding from calibration run 3, in issue-comment shape, cut to the ingredients
whose triggers fired:

````markdown
### The touch check only works where `click` is a `PointerEvent`

```tsx
// src/components/combobox/combobox.tsx:755
const isTouch = 'pointerType' in event && event.pointerType === 'touch';
```

On iOS 16 and 17 this PR does nothing for its own goal. WebKit only made `click` a `PointerEvent`
with a truthful `pointerType` in Safari 18.2, so on earlier versions the `in` guard fails, `isTouch`
is `false`, and a chevron tap still focuses the input and brings the keyboard up. Chromium is fine —
the handler does receive a `PointerEvent` there, so the earlier claim that `click` never carries
`pointerType` was wrong.

To see it without an old device, open **Examples / Basic** and run this in the console:

```js
document.querySelector('[data-component="Combobox.Toggle"]')
  .dispatchEvent(new MouseEvent('click', { bubbles: true }));
```

That is the event those Safari versions deliver: the popup opens and the caret lands in the search
input.

If you want to cover them: record `event.pointerType` in `onPointerDown` and read it in `onClick`.
`pointerdown` has carried a correct `pointerType` since Safari 13.
````

Reading it against the rules above:

| Part | Why it is there |
| ---- | --------------- |
| The heading | The claim as a sentence, not a noun phrase or a label |
| The code quote | Issue-comment shape, so the quote is what locates the line. In review shape this block is absent |
| "On iOS 16 and 17 this PR does nothing for its own goal" | The consequence first, **in the issue's own terms** — iOS is what the PR is for. The mechanism follows in the same paragraph, with the version that draws the boundary |
| "so the earlier claim … was wrong" | The withdrawal, one clause. Its trigger fired: round one rated this critical on a false premise |
| The console snippet | The one reproduction, runnable by someone with no device. The thing that made the finding land |
| "If you want to cover them" | Offered, not demanded. Its trigger fired: the fix is a different event, not the inverse of the claim |

No attribution clause appears, because the line is new on this branch. No severity label appears
anywhere, and a reader can still tell it is the serious one — it was placed first and introduced as
the one needing a change before ship.

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
