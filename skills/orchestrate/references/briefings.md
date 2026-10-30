# Briefings

How a briefing is written. `SKILL.md` → **Asking the User** owns when one is needed.

A briefing makes one decision readable cold, to a user who has not followed the workers, in at
most twelve lines:

1. **The question**, bold, as the user would ask it.
2. **The situation** in two or three plain sentences: what happened, and why it needs a decision
   now. Real names — the function, the PR, the issue — each with what it is.
3. **What we know**, two to four bullets, each one fact that moves the decision.
4. **Options**, recommended first and marked, one line each with what it costs.

Then the question, with the same options in the same order. Example:

```markdown
**Should `suspendAccount` keep running its stop as admin?**
Suspending an account has to stop its environments, but the account check refuses stops on a suspended account for anyone but a superuser. The #2598 worker ran the stop as admin, after the caller's own check.

- Owners can suspend their own account, so the stop has to work for non-superusers.
- Admin rights reach only the account already checked; nothing new becomes reachable.
- The `allow*` flags the issue suggested do nothing for non-superusers — dead code.

1. **Keep the admin stop (recommended)** — no change to PR #2606; file the dead flags as their own issue.
2. **Make the account check honour `allow*`** — six call sites, and it loosens deletes on expired trials.
3. **Stop only in the sweep** — breaks #2598's "stop in the same call"; environments run up to ten more minutes.
```
