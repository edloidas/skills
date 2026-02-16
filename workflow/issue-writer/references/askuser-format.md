## AskUserQuestion Standards

When using the `AskUserQuestion` tool in this skill, follow these standards:

### Format Requirements

1. **First option MUST be recommended** - Always add "(Recommended)" suffix to the first option
2. **Every option MUST have a description** - Explain what the choice means or what will happen
3. **Order by relevance** - Recommended first, then logical alternatives, then "skip/none" option last
4. **Maximum 4 options** - Claude Code tool limit; "Other" is automatically added by the system
5. **Clear, concise labels** - 1-5 words, actionable

### Questions Used in This Skill

| Step | Question | Header |
|------|----------|--------|
| 1.5 | "What level of detail should this issue have?" | Format |
| 3.5 | "Which label best describes this issue?" | Label |
| 6.5 | "Who should this issue be assigned to?" | Assignee |

### Template

```
question: "{{CLEAR_QUESTION_ENDING_WITH_?}}"
header: "{{SHORT_HEADER_MAX_12_CHARS}}"
options:
  - label: "{{CHOICE}} (Recommended)"
    description: "{{WHY_THIS_IS_RECOMMENDED}}"
  - label: "{{ALTERNATIVE_1}}"
    description: "{{WHAT_THIS_MEANS}}"
  - label: "{{ALTERNATIVE_2}}"
    description: "{{WHAT_THIS_MEANS}}"
  - label: "{{SKIP_OPTION}}"
    description: "{{CONSEQUENCE_OF_SKIPPING}}"
```
