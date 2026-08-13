---
paths:
  - '**/*.tsx'
---

# React Rules

React 19.

## Component shape

Arrow function + explicit `displayName` + explicit return type (`ReactElement` or `JSX.Element` — both are accepted). Named export only — no default exports from component files:

```tsx
export type ToggleProps = {
  label: string;
  disabled?: boolean;
  className?: string;
  children?: ReactNode;
};

export const Toggle = ({label, disabled, className, children}: ToggleProps): ReactElement => {
  // ...
  return (
    <label className={className}>
      {label}
      {children}
    </label>
  );
};
Toggle.displayName = 'Toggle';
```

When the component name is reused inside the body (e.g. for `useId`), define it as a const first:

```tsx
const TOOLTIP_NAME = 'Tooltip';
export const Tooltip = ({id, ...props}: TooltipProps): ReactElement => {
  const tooltipId = id ?? `${TOOLTIP_NAME}-${useId()}`;
  return <div id={tooltipId} role='tooltip' {...props} />;
};
Tooltip.displayName = TOOLTIP_NAME;
```

## Props

- Type named `<Component>Props`, exported, colocated.
- Drop `is`/`has` prefixes on boolean props (`disabled`, `loading`, `active` — not `isDisabled`).
- `className?` and `children?` last.
- Event handler props use `on*`; internal handlers use `handle*`.

## Extending HTML props — `ComponentPropsWithoutRef`

```ts
type ButtonProps = {
  variant?: 'primary' | 'ghost';
} & ComponentPropsWithoutRef<'button'>;

type InputProps = {
  label?: string;
} & ComponentPropsWithRef<'input'>;
```

Avoid `ComponentProps` (doesn't distinguish ref handling) and the `*HTMLAttributes` types.

## Refs — ref-as-prop, never `forwardRef`

`forwardRef` is legacy. In React 19, accept `ref` as a regular prop:

```tsx
type InputProps = {
  ref?: React.Ref<HTMLInputElement>;
  label?: string;
};

export const Input = ({ref, label, ...props}: InputProps): ReactElement => (
  <input ref={ref} aria-label={label} {...props} />
);
Input.displayName = 'Input';
```

## Nanostore subscription

If the store is a map and only some keys are read, subscribe to those keys:

```ts
const {account} = useStore($application, {keys: ['account']});
```
