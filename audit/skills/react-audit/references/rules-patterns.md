# Deep Analysis Patterns

Rules for the inline deep analysis track. These require judgment and context awareness — not suitable for mechanical checking.

## Memoization Strategy

### First: is the React Compiler on?

Look for `babel-plugin-react-compiler` in the Babel config, `reactCompiler: true` in `next.config`,
or the compiler plugin in the Vite/RSbuild config. If it is on, **skip this whole section**. The
compiler memoizes components, values, and callbacks itself, and hand-written `memo`/`useMemo`/
`useCallback` in a compiled project is at best redundant. The only memoization finding worth raising
there is the reverse one: existing manual memoization that can now be deleted, and only when the
project is actually migrating.

Everything below applies to projects without the compiler.

### When to use `memo()`
- Component receives objects/arrays as props and re-renders frequently
- Component is expensive to render (large lists, complex DOM)
- Component sits below a frequently updating parent

### When to use `useCallback`
- Function is passed as prop to a `memo()`-wrapped child
- Function is a dependency in `useEffect`, `useMemo`, or another hook

### When to use `useMemo`
- Expensive computation (filtering/sorting large arrays, complex transforms)
- Object/array passed to `memo()`-wrapped child or used as hook dependency

### When NOT to memoize
- Simple calculations (`a + b`, `user.name`, string concatenation)
- Primitives that aren't used as dependencies
- Functions only used in the same component (not passed down)
- Components that rarely re-render
- Over-memoization adds complexity without measurable benefit

## Ref Handling

### `ref` is a normal prop from React 19

Function components take `ref` as an ordinary prop. `forwardRef` still works but is deprecated, so
flag new code that reaches for it and leave existing wrappers alone unless the file is being
rewritten anyway.

```tsx
// React 19
type InputProps = ComponentPropsWithRef<'input'>;
export const Input = ({ ref, ...props }: InputProps) => <input ref={ref} {...props} />;
```

### Never put `ref.current` in dependency arrays

```tsx
// Wrong — .current changes don't trigger re-renders, deps become stale
useEffect(() => {
  contentRef.current?.focus();
}, [contentRef.current]);

// Correct — check .current inside the effect
useEffect(() => {
  contentRef.current?.focus();
}, []);
```

**Why:** Refs are mutable containers. React doesn't track `.current` changes, so the dependency array becomes a lie.

### Ref callbacks for dynamic elements

When you need to respond to a DOM node being attached/detached, use a ref callback instead of `useRef` + `useEffect`.

```tsx
const measureRef = useCallback((node: HTMLDivElement | null) => {
  if (node) setHeight(node.getBoundingClientRect().height);
}, []);

return <div ref={measureRef} />;
```

From React 19 a ref callback may return a cleanup function, which React calls on detach instead of
calling the callback again with `null`. Prefer that shape for anything that needs teardown — an
observer, a listener, a subscription:

```tsx
const observeRef = useCallback((node: HTMLDivElement) => {
  const observer = new ResizeObserver(([entry]) => setHeight(entry.contentRect.height));
  observer.observe(node);
  return () => observer.disconnect();
}, []);
```

A callback that returns a cleanup is never called with `null`, so a `if (node)` guard plus a
cleanup return in the same callback is a sign the two styles got mixed.

## Early Returns vs Conditional Rendering

### Prefer early returns
```tsx
// Good — clear guard clause
if (!data) return <Loading />;
if (error) return <ErrorBanner error={error} />;
return <Content data={data} />;
```

### Avoid conditional fragments
```tsx
// Bad — wrapping conditional content in fragments
return <>{isReady && <div>Content</div>}</>;

// Good
if (!isReady) return null;
return <div>Content</div>;
```

### When conditional rendering is fine
- Showing/hiding a small part of a larger component
- Toggle states within JSX (`{isOpen && <Dropdown />}`)
- Ternary for two variants (`{isEdit ? <Form /> : <Display />}`)

## Performance Patterns

### Throttle high-frequency event handlers
Scroll, resize, mousemove, and input events should be throttled or debounced — but the throttled
function has to survive re-renders, or its internal timer resets and the throttle does nothing.

```tsx
// Wrong — useCallback does not call throttle lazily; the throttled function is
// rebuilt whenever handleScroll changes, and each rebuild resets the timer.
const throttledScroll = useCallback(throttle(handleScroll, 100), [handleScroll]);

// Correct — build it once, keep the changing logic behind a ref, and cancel on unmount.
const handlerRef = useRef(handleScroll);
useLayoutEffect(() => { handlerRef.current = handleScroll; });

const throttledScroll = useMemo(() => throttle((e) => handlerRef.current(e), 100), []);
useEffect(() => () => throttledScroll.cancel(), [throttledScroll]);
```

Flag any throttle or debounce constructed inline in the render body or inside `useCallback` — both
re-create the timer. Missing cleanup on unmount is the second half of the same finding.

### Prefer CSS for animations
CSS transitions and animations are GPU-accelerated and don't cause React re-renders. Use JS animations only when CSS cannot express the behavior.

### Split context providers
If a context value changes frequently, split it into separate contexts for frequently-changing and rarely-changing data:
```tsx
// Instead of one big context:
<AppContext.Provider value={{ user, theme, notifications }}>

// Split into:
<UserContext.Provider value={user}>
  <ThemeContext.Provider value={theme}>
    <NotificationContext.Provider value={notifications}>
```

### Selective store subscriptions
When using external stores, subscribe only to the keys you need:
```tsx
const { account } = useStore($application, { keys: ['account'] });
```

## Data Fetching Patterns

### Extract to custom hooks when effect exceeds ~15 lines
```tsx
// Before — 40 lines of fetch logic inside component
useEffect(() => {
  let ignore = false;
  setLoading(true);
  fetch(`/api/items/${id}`)
    .then(res => res.json())
    .then(data => { if (!ignore) { setData(data); setLoading(false); } })
    .catch(err => { if (!ignore) { setError(err); setLoading(false); } });
  return () => { ignore = true; };
}, [id]);

// After
const { data, isLoading, error } = useItemData(id);
```

### Follow existing project patterns
If the project has `use*Data` or `use*Query` hooks, new fetch logic should follow that pattern rather than raw `useEffect`.

### Prefer framework/library solutions
Flag raw `useEffect` fetch patterns and recommend TanStack Query, SWR, or framework data loaders when the project already uses one of these. On React 19 without such a library, `use()` under a Suspense boundary is the alternative — see anti-pattern #13 in `rules-effects.md` for the caching caveat that makes or breaks it.

### Mutations belong to actions, not effects
On React 19, a submit path that hand-rolls `isSubmitting` and `error` state should use
`useActionState`, and a non-blocking update that hand-rolls an `isLoading` flag should use
`useTransition`. See anti-pattern #16 in `rules-effects.md`.

## Component Organization

### Size thresholds
- **>200 lines** — consider splitting into sub-components
- **>3 responsibilities** — definitely split (fetching + transforming + rendering = 3)
- **Repeated logic across 2+ components** — extract to custom hook

### Separation of concerns
- Data fetching → custom hooks
- Business logic → custom hooks or utility functions
- UI rendering → components
- Side effects → event handlers (not effects, unless syncing with external systems)

### Component file structure
1. Imports
2. Types
3. Constants (including name const for displayName)
4. Component function
5. displayName assignment
6. Helper components (small, private, used only here)
