# npm Publishing Controls

Read from `repo-hardening` Step 7 when the repo publishes packages to npm. None of these can be set through `gh`; list each for the user in the Step 8 report.

- **npm** (when the repo publishes packages), at
  `https://www.npmjs.com/package/<name>/access` — give the user the resolved URL, one per
  public package in a monorepo, not a generic "your package settings":
  - Trusted Publisher pinned to the exact `owner/repo` + release workflow filename.
  - **Enable only "Allow npm stage publish"**, so a plain `npm publish` from that workflow
    is rejected and every release has to pass through a maintainer's 2FA approval
    (`npm stage approve <stage-id>`, or Staged Packages on npmjs.com). This is the control
    a fully compromised CI job cannot forge — the workflow holds a legitimate OIDC
    identity, and staging is what stops that identity from being enough. It only binds if
    it is set registry-side; the workflow using `npm stage publish` without this
    restriction is a convention, not a control.
  - Publishing access set to *require 2FA and disallow bypass tokens* once OIDC is the
    only publish path. Warn first: this revokes existing tokens, so any other automation
    publishing with a token breaks.
  - Requires npm CLI >= 11.15.0 and Node >= 22.14.0 in the release workflow. Check the
    workflow's `node-version` before recommending the switch.
