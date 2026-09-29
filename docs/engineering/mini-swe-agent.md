# mini-SWE-agent Engineering Pattern

Alfaeq Yemen uses the ideas from SWE-agent's mini-SWE-agent as an engineering pattern, not as a runtime dependency of the Flutter application.

## Why it matters

mini-SWE-agent v2 demonstrates that a coding agent can remain small, deterministic, inspectable, and effective by reducing the agent loop to:

1. Inspect the repository.
2. Ask the model for the next action.
3. Execute an independent shell command.
4. Append the observation to a linear history.
5. Repeat until completion or a safety limit is reached.

The project currently supports sandboxable environments and explicit step, cost, and wall-clock limits.

## Alfaeq adaptation

The pattern is applied to repository engineering as follows:

- **Linear task history:** preserve task, commands, observations, validation results, and final status in order.
- **Independent commands:** do not depend on a long-lived shell session for correctness.
- **Hard limits:** every automated coding run must have bounded steps, cost, and wall-clock time.
- **Sandbox first:** code-changing agents should operate in an isolated workspace/container when available.
- **Explicit completion:** an agent must produce a machine-detectable completion status before a change is considered finished.
- **Verification after mutation:** Flutter analyze/test, migration verification, security review, and GitHub Actions remain the authoritative gates.
- **No direct production mutation:** an engineering agent must not bypass repository review or directly mutate production business data.
- **Canonical architecture:** Supabase remains the transactional source of truth and the existing event bus remains the canonical event boundary.

## Relationship to Aider

Aider remains the interactive architect/editor workflow for human-directed development.

mini-SWE-agent adds a complementary minimal autonomous loop for bounded repository tasks:

Aider Architect -> focused edit -> mini agent verification loop -> Git diff -> CI -> Supabase verification.

Neither tool becomes part of the production Flutter binary.

## Safety boundary

The agent may inspect and modify source code inside an isolated development workspace. It must not receive Supabase service-role credentials, payment credentials, or other production secrets. External side effects should be represented as reviewed code changes or canonical application events.

## Upstream tracking

Source: https://github.com/SWE-agent/mini-swe-agent

At the time this pattern was adopted, upstream v2 was the active architecture and v2.4.6 was the latest release observed. Re-check upstream release notes before changing any pinned implementation or configuration.

## Production rule

An agent saying "done" is not evidence of correctness. A change is production-ready only after the repository's normal static analysis, tests, security checks, migration verification, and GitHub Actions gates pass.
