# Jev Ultrafast — Alfaeq browser decision layer

Source: `safwt771754091s-crypto/jev-ultrafast` (fork of `browser-use/jev-ultrafast`)
License: MIT
Boundary: engineering/automation plane; not a Flutter runtime dependency.

## What we adopt

Jev Ultrafast uses a structured browser observation and typed decision loop:

`page -> indexed visible controls -> operation + compatible target -> guarded execution -> independent outcome verification`

The useful Alfaeq pattern is not the repository itself. It is the strict separation between:

- observation: enumerate only currently usable controls;
- decision: choose a typed operation and operation-specific target;
- execution: resolve the target against the current DOM and reject stale/covered targets;
- text generation: call a text model only for `TYPE_TEXT`;
- verification: independently verify the business outcome instead of trusting `DONE`.

This reduces unnecessary model calls and prevents model output from becoming selectors, coordinates, shell commands, or executable JavaScript.

## Alfaeq integration

Use this decision layer for browser-facing automation tasks such as:

- merchant/admin portal navigation;
- supplier/catalog portal updates;
- operational dashboards;
- external integration consoles;
- controlled web research and data-entry workflows.

The canonical production business state remains in Supabase. Browser automation is an integration boundary, not a second database.

### Safety contract

1. Never allow a model to emit raw selectors, coordinates, JavaScript, shell commands, or arbitrary browser code.
2. Every target must originate from the latest observed control set.
3. Never blindly retry a browser mutation. Re-observe and decide again.
4. Log the intended execution before observing its result.
5. Treat a `DONE` action as a request for verification, not proof of success.
6. Keep credentials in the execution environment/secret store, never in prompts, traces, or repository files.
7. Keep paid/live browser tests separate from offline CI tests.
8. External side effects require an explicit action policy and, where appropriate, a human approval gate.
9. Business mutations still go through the canonical Supabase APIs/functions/event bus whenever an API boundary exists; browser automation should not bypass transactional domain rules.

## Fit with the Alfaeq agent plane

`Event -> JEV assessment -> Agent/Task -> Browser decision layer -> guarded action -> independent verification -> event/result`

Jev is a fast action-selection component inside a larger agent runtime. It does not replace OpenHands, mini-SWE-agent, Aider, or the sandbox layer:

- OpenHands: long-running agent/conversation/runtime boundary.
- mini-SWE-agent: bounded repository execution.
- Aider: interactive architecture/editor workflow.
- Jev Ultrafast: fast structured browser action selection.
- Sandbox/SWE-ReX/OpenSandbox: isolation and execution boundary.
- Supabase event bus: canonical business event state.

## Performance evidence and limits

The upstream README reports a 7.073-second Google Flights demonstration and a small before/after comparison reducing median browser protocol calls from 1,092 to 101. These are project-authored measurements for a limited task set, not a general production SLA.

The upstream MVP explicitly excludes or has limited support for cases such as shadow roots, frames, canvas, uploads, pop-up tabs, nested scrolling, and arbitrary keyboard widgets. Alfaeq must therefore route unsupported browser tasks to another tool or human review rather than assuming universal coverage.

## Verification

For any production browser workflow, verify:

- target was visible and compatible at decision time;
- target remained valid at execution time;
- mutation was executed at most once per decision;
- expected postcondition is independently observed;
- failure/blocked states are persisted;
- external side effects are idempotent where possible.

Upstream offline checks include Ruff, pytest, JavaScript syntax checks, and package build. Alfaeq CI should test our adapters/contracts without requiring paid Jev or browser APIs.
