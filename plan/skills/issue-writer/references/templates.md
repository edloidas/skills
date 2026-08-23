# Issue Description Templates

One template per format. Pick the one matching the format chosen in Step 1.5, then
follow the writing rules in Step 5 of `SKILL.md`. `{{PLACEHOLDER}}` markers are
instructions to you, not literal text — replace them, and drop any section whose
guard note says to include it only under a condition that does not hold.

## Full Issue Template

Use this comprehensive template for Full format issues (includes all sections as needed):

```markdown
{{BRIEF_DESCRIPTION}}

---

### Rationale

{{Include only if the "why" isn't obvious}}

- {{RATIONALE_POINT}}

---

### References

{{Include if there are relevant links}}

- {{REFERENCE: description}}

---

### Things to Consider

{{Include if there are important edge cases or decisions}}

- {{CONSIDERATION}}

---

### Implementation

> [!IMPORTANT]
> This is not a step-by-step guide — it's a functional checklist ordered logically.

{{Include for medium/large scope issues}}

1. {{IMPLEMENTATION_STEP}}

**UI Behavior:**

{{Include if there are specific interaction requirements}}

- {{UI_BEHAVIOR}}

---

### Acceptance Criteria

{{Always include — defines "done"}}

- [ ] {{CRITERION}}

---

### Testing Steps

{{Include if testing isn't obvious}}

1. {{TESTING_STEP}}

---

### Examples

{{Include if visual examples help clarify}}

**{{EXAMPLE_CASE}}**

![{{ALT_TEXT}}]({{IMAGE_URL}})

---

### Out of Scope _(Optional)_

{{Include only if scope boundaries need explicit definition}}

- {{OUT_OF_SCOPE_ITEM}}

---

### Technical Constraints _(Optional)_

{{Include only if there are specific technical requirements}}

- {{CONSTRAINT}}
```

## Short Issue Template

Use this minimal template for Short format issues. No section headers, no horizontal rules:

```markdown
{{DESCRIPTION — 4-6 sentences. Explain the issue naturally: what happens, what's affected, why it matters. Keep the user's original phrasing.}}

**Rationale:** {{WHY_NEEDED — 1-2 sentences}}
```

## Default Issue Template

Use this template for Default format issues. Use h4 headers, no horizontal rules:

```markdown
{{DESCRIPTION — 4-8 sentences: what the issue is, what it affects, how to reproduce (when applicable), what's impacted. Keep the user's original phrasing.}}

#### Rationale

{{WHY_NEEDED — explain why this needs to be fixed or implemented}}

#### References

{{Include only if there are relevant links or related issues}}

#### Implementation Notes

{{Include only if the approach is already known — brief notes on what needs to be done}}
```
