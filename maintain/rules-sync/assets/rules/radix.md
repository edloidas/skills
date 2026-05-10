---
paths:
  - '**/*.tsx'
---

# Radix Rules

## Umbrella imports only

Import primitives from the `radix-ui` umbrella as namespaces. Never the individual `@radix-ui/react-*` packages.

```tsx
import {Tabs, Switch, Slider, Dialog, Slot} from 'radix-ui';
```

## No Button primitive — use `<button>` + `Slot.Root`

There is no `Button` primitive. Build on a regular `<button>` plus `Slot.Root` for `asChild` composition, so a parent (e.g. `Tabs.Trigger`) can render through the styled `Button` without an extra wrapper:

```tsx
import {Slot} from 'radix-ui';

export const Button = ({asChild = false, className, ...props}: ButtonProps): ReactElement => {
  const Component = asChild ? Slot.Root : 'button';
  return <Component className={cn(buttonVariants(...), className)} {...props} />;
};
```

## Style via `data-state`

Don't strip `data-state`, `data-disabled`, `data-orientation` from primitives — Tailwind selectors target them (`data-[state=open]:opacity-100`). Always render `Dialog.Title` (wrap in `VisuallyHidden` if not visually wanted) — required for screen readers.

## When to reach for Radix

Use Radix for primitives with a non-trivial keyboard, focus, or ARIA contract: `Dialog`, `DropdownMenu`, `Tabs`, `Switch`, `Slider`, `Tooltip`, `Popover`, `Toast`, `RadioGroup`, `Checkbox`. Skip it for plain layout, simple presentational components, or anything you'd build in 10 lines of `<div>` + Tailwind without ARIA concerns.
