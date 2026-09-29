# Alfaeq Engineering Agent Stack Registry

This repository is the production application. External agent projects are engineering-plane components, not copied wholesale into the Flutter runtime.

## Current stack

| Source | Role | Status | Alfaeq integration |
|---|---|---|---|
| OpenHands | long-running agent runtime, conversations, tools/skills, server/automation | integrated as executor provider | docs/engineering/openhands.md, .github/workflows/alfaeq-project-executor.yml |
| Alfaeq Project Executor | issue/manual -> OpenHands -> PR execution loop | integrated | .github/workflows/alfaeq-project-executor.yml, docs/engineering/project-executor.md |
| mini-SWE-agent | bounded autonomous issue-fix loop | integrated conceptually | docs/engineering/mini-swe-agent.md |
| Aider | architect/editor workflow | integrated | .aider.conf.yml, CONVENTIONS.md |
| Jev Ultrafast | fast structured browser action selection | integrated as a documented capability | docs/engineering/jev-ultrafast.md |
| security-audit-skill | six-phase security audit, independent validation, coverage ledger and machine-readable findings | integrated as engineering security gate | docs/engineering/security-audit.md |
| SWE-ReX | isolated/remote command execution for agents | NEW | sandbox contract below |
| OpenSandbox | secure/extensible sandbox runtime | already present as a separate fork | use as sandbox implementation candidate |
| OpenCode | coding-agent/runtime patterns | already present as a separate fork | use selectively; never expose an unauthenticated server |
| SWE-agent | mature issue-fixing architecture | reference only | do not duplicate mini-SWE-agent |
| Roo Code | editor multi-mode agent patterns | reference only | archived; do not make it a production dependency |
| OpenDevin | historical name of OpenHands | superseded | no separate copy needed |
| OpenCode Bench | agent evaluation methodology | NEW | use as verification/benchmark design |

## Rule: integrate capabilities, not repositories

We do not dump entire third-party repositories into alfaeq_yemen_new. That would create duplicated and difficult-to-maintain code and can introduce incompatible dependencies or license obligations.

Instead:
1. Keep upstream/fork repositories independently updateable.
2. Extract only architecture/contracts that solve an Alfaeq engineering problem.
3. Record source, license, and integration boundary.
4. Keep production business state in Supabase.
5. Keep agent-run state in the agent runtime/conversation layer.
6. Keep business events in the canonical Supabase event bus.
7. Run agent work in an isolated workspace/sandbox.
8. Require lint, tests, security checks and GitHub Actions evidence before release.

## Target engineering loop

GitHub issue/event -> dispatcher -> agent runtime -> isolated workspace -> inspect -> edit -> test -> security -> diff review -> commit/PR -> GitHub Actions -> human release gate

The engineering-agent plane must never receive production service-role credentials or mutate production business data directly.

## Production application loop

Flutter -> Supabase Auth/RLS -> transactional domain functions -> canonical event bus -> n8n/external automation -> notifications/integrations

The engineering-agent plane and production application plane remain separate.

### Jev Ultrafast
- structured visible-control observation;
- one typed operation plus a compatible target per decision cycle;
- target revalidation before browser mutation;
- text generation only when typing is required;
- independent postcondition verification after DONE.

## What we are taking from the listed repositories

### SWE-ReX
- provider-independent execution interface
- local/remote sandbox abstraction
- session-oriented command execution
- parallel execution capability
- infrastructure/agent separation

### OpenCode
- explicit permission boundary
- session/runner separation
- provider abstraction
- typed API/core boundaries
- benchmark/test entry points

OpenCode's own security documentation says its permission system is not a sandbox; real isolation should be provided by Docker/VM. Alfaeq therefore keeps sandboxing outside the agent permission UX.

### Roo Code
- Architect / Code / Debug / Ask mode separation
- custom modes
- MCP/tool integration
- editor-oriented workflow patterns

Roo Code is archived, so these are patterns only, not a runtime dependency.

### SWE-agent / mini-SWE-agent
- issue-to-fix loop
- explicit step/cost/time limits
- observation-driven execution
- reproducible task trajectories
- isolated workspaces

mini-SWE-agent is the preferred lightweight execution pattern; the upstream SWE-agent project itself now recommends it for new use.

### OpenHands / OpenDevin
- agent/conversation/tools/skills/workspace/server boundaries
- long-running agent sessions
- automation/dispatch separation
- typed actions/observations

OpenDevin is the former name of OpenHands, so it is not a second implementation.

### OpenCode Bench
- fresh isolated evaluation episodes
- production-commit-based tasks
- deterministic project checks
- multi-dimensional evaluation
- repeated episodes to detect instability

This becomes a verification design for engineering agents, not a product feature.

## License policy

Only code that is actually incorporated must carry the corresponding attribution/license requirements. Before copying source files, inspect the exact file's license and NOTICE requirements.

## Definition of done

An agent-generated change is not production-ready merely because an agent reports success. It requires:
- clean diff
- no secrets
- RLS/security review
- migration verification when applicable
- Flutter analyze
- Flutter tests
- relevant build
- agent/evaluation evidence where the change is agent-generated
- GitHub Actions result
- explicit release decision