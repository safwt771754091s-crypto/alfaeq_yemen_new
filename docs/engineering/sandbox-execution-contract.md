# Alfaeq Agent Sandbox Execution Contract

## Purpose

Provide a hard boundary between autonomous engineering agents and the Alfaeq production system.

## Execution providers

The contract is provider-neutral. A deployment may use:
- SWE-ReX for local/remote execution abstraction.
- OpenSandbox for sandbox runtime/isolation.
- Docker/VM/Kubernetes as infrastructure.
- OpenHands Agent Server as the agent-facing runtime.

The agent code must not depend on a specific sandbox vendor.

## Workspace lifecycle
1. Create an isolated workspace from a known Git commit.
2. Inject only task-scoped non-production configuration.
3. Execute inspect/reproduce/edit/test commands.
4. Capture stdout, stderr, exit codes and timing.
5. Produce a Git diff.
6. Run static analysis, tests and security checks.
7. Persist the trajectory/result metadata.
8. Destroy the workspace after completion unless retention is explicitly required for review.

## Forbidden credentials
Never inject:
- Supabase service-role keys
- production database passwords
- payment provider secrets
- WhatsApp production secrets
- signing keys
- user/session tokens
- GitHub personal access tokens with broad write access

Use short-lived, least-privilege credentials where a task genuinely requires an external service.

## Allowed production interaction
Agents may read documented architecture and schema artifacts. They must not directly mutate production business tables.

Production mutations remain behind the normal application/service boundary and Supabase RLS/transactional functions.

## Required result envelope
Every autonomous run should produce:
- task id
- repository
- base commit
- workspace id
- agent/runtime
- model/provider
- start/end timestamps
- commands executed
- exit codes
- changed files
- test/analyze/build results
- security result
- final diff/commit reference
- failure reason when incomplete

## Failure policy
A timeout, sandbox failure, test failure or ambiguous result is a failed engineering run until independently verified.

No agent may mark a release successful based only on its own textual claim.