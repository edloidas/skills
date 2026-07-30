---
paths:
  - '**/*.tsx'
---

# Three.js / R3F Rules

## `useFrame` priority convention

```ts
useFrame((state, delta) => {
  /* gameplay */
}, 1);
useFrame((state, delta) => {
  /* visual effects */
}, 2);
```

Priority `1` for gameplay/sim, priority `2` for visual effects. Lets gameplay update before effects sample it.

## Separate 3D scene components from DOM/HUD components

3D (`<mesh>`, `<group>`, R3F children) lives under `src/scene/`. DOM/HUD (`<div>`, Tailwind, Radix) lives under `src/components/`. A single file should not mix the two.

## Nanostore wiring

Subscribe with `@nanostores/react`'s `useStore`. Batch related writes:

```tsx
import {useStore} from '@nanostores/react';
import {batch} from 'nanostores';
import {$position, $rotation} from '@/stores/game';

const updateTransform = useMemo(
  () =>
    throttle((next: Transform) => {
      batch(() => {
        $position.set(next.position);
        $rotation.set(next.rotation);
      });
    }, 16),
  [],
);
```
