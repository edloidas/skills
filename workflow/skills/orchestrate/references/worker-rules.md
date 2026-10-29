# Worker Rules

Appended verbatim to every unit prompt, after its **Report** section, so each worker carries the
same rules about the processes it starts and the writes it is refused.

````text
## Every worker
- To learn that a subagent you started has finished, wait for the host's completion notification.
  Never read or poll another agent's output or transcript files, and never start a loop that
  watches for one to finish.
- Stop every background shell or process you started before you hand back. End the report with
  `Left running: <each process you could not stop — its command and why>`, or `Left running: none`.
- A write the host's permission layer refuses — a merge, a push, an issue edit, anything else — is
  final for this run. Do not retry it in another form and do not ask anyone else to run it. Report
  it under Unfinished, or at the end where the report has no such section, as
  `blocked: permission — <the exact refused command>`.
````
