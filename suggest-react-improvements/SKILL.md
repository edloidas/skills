---
name: suggest-react-improvements
description: Analyze React code and suggest improvements based on best practices, project conventions, and modern patterns. Focuses on architecture, hooks usage, state management, and code organization.
license: MIT
compatibility: Claude Code, Codex
allowed-tools: Bash, Read, Glob, Grep
---

# Suggest React Improvements

## Purpose

Provide actionable suggestions to improve React code quality. Unlike code review (which finds bugs), this skill suggests better patterns, cleaner architecture, and modern approaches. Reads project rules (react.mdc, typescript.mdc) to align with established conventions.

## When to Use

- After implementing a feature, want architectural feedback
- Refactoring existing code
- Learning better patterns for React development
- Code feels "messy" but passes all checks

Trigger phrases: "suggest improvements", "how can I improve this", "better patterns", "refactor suggestions"

## Commands

| Command | Description |
|---------|-------------|
| `/suggest-react-improvements` | Analyze staged/unstaged changes |
| `/suggest-react-improvements path/file.tsx` | Specific file |
| `/suggest-react-improvements path/` | Directory |

## Workflow

### Phase 1: Load Context

1. **Read project rules:**
   ```
   .cursor/rules/react.mdc
   .cursor/rules/typescript.mdc
   .cursor/rules/stores.mdc (if exists)
   ```

2. **Identify target files:**
   - If path argument provided: use that path
   - Otherwise: get staged/unstaged changes via `git diff --name-only`
   - Filter to `.tsx` and `.ts` files

3. **Read each file completely** before analysis

### Phase 2: Analyze Patterns

Run these analyses on each file:

#### Hooks Organization

Check ordering per react.mdc:
- Are store hooks (`useStore`) at the top?
- Are ref hooks next?
- Are state hooks (`useState`) after refs?
- Are effects (`useEffect`) last among hooks?
- Could multiple `useState` calls be consolidated into `useReducer`?

**Flag if:** Hooks are scattered or out of order

#### Data Fetching Patterns

- Is fetch logic inside `useEffect`? Count lines
- Does project have similar `use*Data` or `use*Fetch` hooks?
- Are async functions defined inside effects?

**Flag if:**
- Effect has >15 lines of fetch/async logic
- Project has hook pattern that could be followed
- Functions defined inside effect could be extracted

#### State Management

- Multiple related `useState` calls (e.g., loading, error, data, isEmpty)
- State derived from props calculated in `useEffect`
- State synced with props via `useEffect`

**Suggest:**
- Single state object or `useReducer` for related states
- `useMemo` for derived values instead of effect
- Key prop pattern: `<Component key={id} />` for reset

#### Props Handling

Check for:
- Using `omit()` utilities to exclude props when spreading
- Not using `ComponentPropsWithoutRef` for extended components
- Forwarding many individual props

**Suggest:**
```tsx
// Instead of: const rest = omit(props, ['excluded', 'another'])
const { excluded, another, ...rest } = props;
```

#### Object/Array Manipulation

Check for:
- Using `delete` on object properties
- Using utility libraries for simple operations

**Suggest:**
```tsx
// Instead of: delete obj.prop;
const { prop, ...rest } = obj;

// Instead of: omit(obj, ['a', 'b'])
const { a, b, ...rest } = obj;

// Instead of: pick(obj, ['a', 'b'])
const { a, b } = obj;
const picked = { a, b };
```

#### Memoization

- Handlers passed to memoized children without `useCallback`?
- Expensive calculations (filter, sort, map on large arrays) without `useMemo`?
- Unnecessary memoization on cheap operations?

**Per react.mdc:** Only suggest memoization when there's clear benefit

#### Error Handling

- Does project use `neverthrow`/`Result` pattern? (Check typescript.mdc)
- Are there generic `catch` blocks without specific error handling?

**Flag if:** Project uses typed errors but new code uses try-catch

#### Code Organization

- Component >200 lines? Suggest splitting
- Multiple unrelated responsibilities in one component?
- Repeated logic that could be a custom hook?

### Phase 3: Output Format

```markdown
## Suggestions for [file.tsx]

### High Impact
Changes that significantly improve maintainability/testability.

**1. Extract data fetching to custom hook** (`MyDialog.tsx:117-179`)
**Current:** 60 lines of fetch logic inside useEffect with caching, error handling, state updates
**Suggest:** Create `useMyData` hook following existing `useSimilarData` pattern
**Benefit:** Testable, reusable, cleaner component
**Example:**
```tsx
// After
const { data, isLoading, error } = useMyData(id, params);
```

### Medium Impact
Improvements to code quality and patterns.

**2. Consolidate related state variables** (`MyDialog.tsx:60-63`)
**Current:** 4 separate useState for data, isLoading, isEmpty, error
**Suggest:** Single state object or useReducer
**Benefit:** Atomic updates, clearer state machine

### Style Suggestions
Minor improvements for consistency with project conventions.

**3. Use destructuring instead of delete** (`helpers.ts:21-27`)
**Current:** `delete obj[key]` in loop
**Suggest:** `const { excluded, ...rest } = obj;`
**Benefit:** Immutable, no mutation, cleaner

---

## Priority Table

| # | Suggestion | Category | Location |
|---|------------|----------|----------|
| 1 | Extract data fetching to custom hook | High | `MyDialog.tsx:117-179` |
| 2 | Consolidate related state variables | Medium | `MyDialog.tsx:60-63` |
| 3 | Use destructuring instead of delete | Style | `helpers.ts:21-27` |
```

## Rules

- **Read project rules first** - Align suggestions with react.mdc, typescript.mdc
- **Prioritize by impact** - High impact = architecture, testability, reusability
- **Show examples** - Include before/after code snippets when helpful
- **Reference project patterns** - "Following pattern in useVersionsData.ts"
- **No false positives** - Only suggest when there's clear benefit
- **Respect trade-offs** - Acknowledge when current approach is valid
- **Don't be pedantic** - Skip trivial suggestions

## Suggestion Categories

### High Impact (Architecture)
- Extract data fetching to custom hook
- Split large component into smaller ones
- Introduce proper typed error handling
- Fix separation of concerns
- Extract repeated logic to shared hook

### Medium Impact (Patterns)
- Consolidate related state into object/reducer
- Use key prop for component reset instead of useEffect
- Replace useEffect with useMemo for derived values
- Add proper memoization for expensive operations
- Use destructuring for prop exclusion

### Style (Consistency)
- Fix hook ordering
- Follow project naming conventions
- Use project's preferred patterns (from rules files)
- Import organization

## Keywords

suggest, improvements, react, best practices, refactor, patterns, hooks, architecture
