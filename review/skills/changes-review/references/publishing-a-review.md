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
- **A runnable reproduction or a measurement.** `the 280px submenu spans 295 to 575 on a
  320px-wide viewport` is a reproduction. "The submenu is clipped" is not. A rendered frame can
  now travel with it — see **Attaching a frame** — but it rides alongside the measurement and
  never replaces it: a number is checkable by the author, an image is only viewable.
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

### `APPROVE` has its own shape

An approval is not a `REQUEST_CHANGES` with the findings deleted. It publishes **one body and no
inline comments** — the `comments` array is empty, and nothing carries a line anchor, a `file:line`
quote, a reproduction snippet, or a measured table. Everything above about anchoring, grouping
minors, and the body being a map rather than a summary applies to reviews that ask for something;
an approval asks for nothing, so there is nowhere for a reader to be sent.

Write it as a conclusion, and keep it to roughly:

- one sentence that it was verified against the issue and approved
- two or three sentences on what holds up, in behavioural terms — what a user can now do
- at most one technical observation, where the change turned on something worth the author's time
- a plain close

**What was run stays out of it.** The engines, the story matrix, the probe names, the clean tooling
result — the author sees CI, and the method is what earned *your* confidence, not something they
need to audit. It belongs in the report to the operator. A verification narrative inside an
approval reads as the reviewer asking for credit.

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

**A review cannot carry an attachment.** `--attach` exists on `gh pr comment` and not on `gh api`,
so nothing submitted through this endpoint uploads a file. **Attaching a frame** above applies to
the issue-comment shape only. In review shape a visual finding publishes as its measurement, and
the frame stays in the operator report — do not post a separate comment to host the image and link
it from the review, which splits one review across two objects and notifies twice.

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

A review that found nothing still publishes, in one short paragraph: what held up, in the terms the
issue used. Never a section list of everything checked — on the calibration run a "checked and
clear" section drew no response at all beyond the closing sentence, and in review shape this is the
`APPROVE` body, which per the section above carries no method narrative and no inline comments.

## When publication cannot finish

Every row ends the same way — print what was composed, post nothing. Publication is the one
outward-facing thing here, so the safe failure is always silence plus a full local copy.

| Situation | Action |
| --------- | ------ |
| Every finding fails the gate | Publish the clean-run paragraph, and tell the caller which findings were withheld and why |
| No pull request resolves for the branch | Print the composed text, and say no PR was found |
| The user declines, or does not answer | Print everything. A declined publication is a normal outcome, not a failed run |
| `--review` on a pull request the user authored | GitHub refuses it. Fall back to the issue-comment shape and say why |
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
