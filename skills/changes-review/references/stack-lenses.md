# Stack lenses

The reviewers are stack-agnostic on purpose. A lens adds the one thing they cannot carry: a catalog
of failure modes specific to a library, deep enough that it would drown a general prompt.

## Dispatch

Invoke the lens skill by name, the same way the external leg goes through `outsider`, and tell it
four things:

1. That it is running in **lens mode**.
2. The exact files Phase 1 resolved.
3. The base ref, when the scope has one.
4. The finding contract the native reviewers return: claim, location, actor, severity, confidence,
   defect, cases.

Both lens skills return whatever shape the caller asks for, so a lens nobody asks returns its own
tally on its own scale, and Phase 4 gets no actor or confidence to work with. A lens must not widen
its own scope — a lens that audits the whole project returns findings this run cannot attribute to
the change.

## Mapping what comes back

Map each result onto the finding contract above. A lens rates its own findings by its own catalog,
so re-rate them rather than trusting the labels:

- A lens finding is `minor` unless it names a concrete failure this diff can produce.
- Anything the lens calls a convention violation is `minor` with no exceptions — that is cleanup,
  and `edloidas:code-cleanup` owns it.

## When a lens is missing

Lenses are optional in the same way the external reviewer is. A lens skill that is not installed is
a skipped leg, never a failed run, and the report says which lenses ran.
