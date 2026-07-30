# Convention Rules

Mechanical checks for project-specific React conventions. These rules are only enforced when convention auto-detection confirms the project uses them.

## displayName

Every exported arrow-function component must have `displayName` set via a named constant.

**Pattern:**
```tsx
const BUTTON_NAME = 'Button';

export const Button = ({ children }: ButtonProps): ReactElement => {
  return <button>{children}</button>;
};

Button.displayName = BUTTON_NAME;
```

**Variants:**
- `memo()` — set `displayName` on the memoized result
- `forwardRef()` — set `displayName` on the forwarded ref result

**Check:** For each exported `const Foo = (` or `export const Foo = React.memo(`, verify `Foo.displayName` exists in the same file.

## data-component

Root JSX element of every component should have a `data-component` attribute matching the component name constant.

**Standard pattern:**
```tsx
const MY_COMPONENT_NAME = 'MyComponent';

return (
  <div data-component={MY_COMPONENT_NAME}>
    {children}
  </div>
);
```

**Overridable pattern** (for foundational/composable components):
```tsx
export type ContentLabelProps = {
  'data-component'?: string;
};

export const ContentLabel = ({
  'data-component': dataComponent = CONTENT_LABEL_NAME,
}: ContentLabelProps): ReactElement => {
  return <ItemLabel data-component={dataComponent} />;
};
```

**Rules:**
- `data-component` should appear before spread props (`{...props}`) so it is not accidentally overridden
- For composable components, expose `'data-component'?: string` in props

## Props Type Naming

Props type must be named `<ComponentName>Props` and exported from the same file.

**Check:** For component `Button`, look for `export type ButtonProps` or `export interface ButtonProps` in the same file.

**Props ordering:**
1. Required props first
2. Optional props next
3. Drop `is`/`has` prefixes for boolean flags (use `active` not `isActive`)
4. `className?` and `children?` last

## Variable Placement Order

Inside component functions, variables must follow this order:

1. **Hooks** — `useRef`, `useState`, `useMemo`, `useCallback`, `useEffect` (effects last among hooks)
2. **Derived state and business logic** — computed values, conditions
3. **Class variables** — `cn()` / `classNames` calls, right before return
4. **Early returns** — loading, error, guard clauses (after class preparation)
5. **JSX return**

**Anti-pattern:** Hooks scattered between logic, or early returns before className preparation.

## ComponentPropsWithoutRef over ComponentProps

When extending native HTML element props, use `ComponentPropsWithoutRef<'element'>` (or `ComponentPropsWithRef` when forwarding refs). Never use bare `ComponentProps`.

**Check:** Grep for `ComponentProps<` without `Without` or `With` qualifier.

```tsx
// Wrong
type BadProps = { value: string } & ComponentProps<'input'>;

// Correct
type GoodProps = { value: string } & ComponentPropsWithoutRef<'input'>;
```

## Destructuring over omit/pick/delete

Prefer native destructuring over utility functions for object manipulation.

**Anti-patterns to flag:**
- `omit(props, ['excluded'])` → `const { excluded, ...rest } = props;`
- `pick(obj, ['a', 'b'])` → `const { a, b } = obj;`
- `delete obj.prop` → `const { prop, ...rest } = obj;`

**Exception:** Dynamic keys computed at runtime where destructuring isn't possible.
