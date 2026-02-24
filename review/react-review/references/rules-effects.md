# useEffect Anti-Patterns

All 14 useEffect anti-patterns from react.dev's "You Might Not Need an Effect" guide, plus common pitfalls from "Synchronizing with Effects".

---

## 1. Transform Data in Effects

**Anti-pattern:** Using `useEffect` + `setState` to transform data for rendering.

```tsx
// Wrong
const [filtered, setFiltered] = useState([]);
useEffect(() => {
  setFiltered(todos.filter(t => t.status === filter));
}, [todos, filter]);
```

**Fix:** Calculate during render.

```tsx
const filtered = todos.filter(t => t.status === filter);
// Or with useMemo if expensive:
const filtered = useMemo(() => todos.filter(t => t.status === filter), [todos, filter]);
```

---

## 2. Handle User Events in Effects

**Anti-pattern:** Using a state flag + `useEffect` to respond to user actions.

```tsx
// Wrong
const [submitted, setSubmitted] = useState(false);
useEffect(() => {
  if (submitted) sendAnalytics('form_submit');
}, [submitted]);
```

**Fix:** Call directly in the event handler.

```tsx
const handleSubmit = () => {
  sendAnalytics('form_submit');
};
```

---

## 3. Redundant Computed State

**Anti-pattern:** Storing derived state that can be calculated from existing state/props.

```tsx
// Wrong
const [fullName, setFullName] = useState('');
useEffect(() => {
  setFullName(`${firstName} ${lastName}`);
}, [firstName, lastName]);
```

**Fix:** Compute inline.

```tsx
const fullName = `${firstName} ${lastName}`;
```

---

## 4. Missing useMemo for Expensive Calculations

**Anti-pattern:** Expensive computation runs every render without memoization.

```tsx
// Wrong — runs on every render
const sorted = bigArray.filter(predicate).sort(comparator);
```

**Fix:** Wrap in `useMemo`.

```tsx
const sorted = useMemo(
  () => bigArray.filter(predicate).sort(comparator),
  [bigArray, predicate, comparator],
);
```

**Note:** Only flag when the computation is genuinely expensive (large arrays, complex transforms). Simple operations don't need memoization.

---

## 5. Reset State via Effects on Prop Change

**Anti-pattern:** Using `useEffect` to reset component state when a prop changes.

```tsx
// Wrong
function ProfilePage({ userId }) {
  const [comment, setComment] = useState('');
  useEffect(() => {
    setComment('');
  }, [userId]);
}
```

**Fix:** Use the `key` prop to remount the component.

```tsx
function ProfilePage({ userId }) {
  return <Profile key={userId} userId={userId} />;
}
```

---

## 6. Adjust State via Effects on Prop Change

**Anti-pattern:** Using `useEffect` to update state based on prop/state changes that aren't a full reset.

```tsx
// Wrong
function List({ items }) {
  const [selection, setSelection] = useState(null);
  useEffect(() => {
    if (selection && !items.includes(selection)) {
      setSelection(null);
    }
  }, [items, selection]);
}
```

**Fix:** Calculate during render or restructure the data.

```tsx
function List({ items }) {
  const [selectedId, setSelectedId] = useState(null);
  const selection = items.find(item => item.id === selectedId) ?? null;
}
```

---

## 7. Duplicate Event Logic in Effects

**Anti-pattern:** Both an event handler and an Effect run the same logic.

```tsx
// Wrong
function handleChange(value) {
  setInput(value);
}
useEffect(() => {
  validate(input); // Duplicated from event handler
}, [input]);
```

**Fix:** Extract shared logic into a function called from the handler.

```tsx
function handleChange(value) {
  setInput(value);
  validate(value);
}
```

---

## 8. Event-triggered POST in Effects

**Anti-pattern:** Sending a request in `useEffect` in response to a user action (button click, form submit).

```tsx
// Wrong
const [shouldSave, setShouldSave] = useState(false);
useEffect(() => {
  if (shouldSave) {
    post('/api/save', { data });
    setShouldSave(false);
  }
}, [shouldSave, data]);
```

**Fix:** Call the API directly in the event handler.

```tsx
const handleSave = () => {
  post('/api/save', { data });
};
```

---

## 9. Chain Effects

**Anti-pattern:** Multiple `useEffect` calls that trigger each other by setting state.

```tsx
// Wrong
useEffect(() => {
  if (card) setRound(round + 1);
}, [card]);
useEffect(() => {
  if (round > 3) setGameOver(true);
}, [round]);
useEffect(() => {
  if (gameOver) showResults();
}, [gameOver]);
```

**Fix:** Calculate what you can during rendering, trigger remaining logic from the event handler.

```tsx
const handlePlayCard = (nextCard) => {
  const nextRound = round + 1;
  setCard(nextCard);
  setRound(nextRound);
  if (nextRound > 3) {
    setGameOver(true);
    showResults();
  }
};
```

---

## 10. App Init in Effects Without Guards

**Anti-pattern:** Running one-time initialization code in `useEffect` without a guard, causing it to run twice in StrictMode.

```tsx
// Wrong
useEffect(() => {
  loadConfiguration();
  connectToDatabase();
}, []);
```

**Fix:** Use a module-level guard variable or run outside the component.

```tsx
let initialized = false;

function App() {
  useEffect(() => {
    if (initialized) return;
    initialized = true;
    loadConfiguration();
    connectToDatabase();
  }, []);
}

// Or at module level:
if (typeof window !== 'undefined') {
  loadConfiguration();
}
```

---

## 11. Notify Parent via Effects

**Anti-pattern:** Using `useEffect` to call a parent callback when state changes.

```tsx
// Wrong
function Toggle({ onChange }) {
  const [isOn, setIsOn] = useState(false);
  useEffect(() => {
    onChange(isOn);
  }, [isOn, onChange]);
}
```

**Fix:** Call the callback in the event handler alongside the state update.

```tsx
function Toggle({ onChange }) {
  const [isOn, setIsOn] = useState(false);
  const handleToggle = () => {
    const next = !isOn;
    setIsOn(next);
    onChange(next);
  };
}
```

---

## 12. Child Fetch + Pass to Parent via Effects

**Anti-pattern:** Child component fetches data and passes it to parent through an Effect.

```tsx
// Wrong — child fetches, then pushes to parent
function Child({ onData }) {
  const data = useFetch('/api/data');
  useEffect(() => {
    if (data) onData(data);
  }, [data, onData]);
}
```

**Fix:** Move fetching to the parent (data flows down, not up).

```tsx
function Parent() {
  const data = useFetch('/api/data');
  return <Child data={data} />;
}
```

---

## 13. Race Conditions in Fetch Effects

**Anti-pattern:** Fetching data in `useEffect` without handling stale responses.

```tsx
// Wrong — stale responses can overwrite fresh data
useEffect(() => {
  fetch(`/api/user/${id}`)
    .then(res => res.json())
    .then(setUser);
}, [id]);
```

**Fix:** Use a cleanup flag to ignore stale responses.

```tsx
useEffect(() => {
  let ignore = false;
  fetch(`/api/user/${id}`)
    .then(res => res.json())
    .then(data => {
      if (!ignore) setUser(data);
    });
  return () => { ignore = true; };
}, [id]);
```

**Better:** Use a data-fetching library (TanStack Query, SWR, etc.) or framework-level data loading.

---

## 14. Manual Store Subscription in Effects

**Anti-pattern:** Manually subscribing to an external store with `useEffect` + `setState`.

```tsx
// Wrong
const [value, setValue] = useState(store.getValue());
useEffect(() => {
  const unsubscribe = store.subscribe(() => {
    setValue(store.getValue());
  });
  return unsubscribe;
}, []);
```

**Fix:** Use `useSyncExternalStore`.

```tsx
const value = useSyncExternalStore(
  store.subscribe,
  store.getValue,
  store.getServerValue, // optional SSR snapshot
);
```
