# Alfaeq Project Executor

The Alfaeq engineering plane turns a concrete project task into a bounded engineering run:

Task/Issue -> OpenHands -> isolated workspace -> inspect -> edit -> test -> security -> PR -> GitHub Actions -> release gate

The production Flutter/Supabase application remains separate from the engineering-agent plane.

## Triggering

### Issue-driven execution
1. Create or update a GitHub Issue with a precise engineering task.
2. Add the \`alfaeq-execute\` label.
3. The \`Alfaeq Project Executor\` workflow starts OpenHands.
4. OpenHands works on the repository and proposes a focused PR.
5. Existing GitHub Actions provide the build/test verdict.
6. The PR is reviewed before merging.

### Manual execution
Run **Alfaeq Project Executor** from GitHub Actions and provide a task. This is useful for large planned platform milestones.

## Required secret

The repository needs the GitHub Actions secret \`OPENHANDS_API_KEY\`.

The workflow deliberately does not run the agent when that secret is absent. GitHub documents that secrets are supplied through the \`secrets\` context and should not be used directly in \`if\` expressions; the workflow therefore copies the secret to a job environment and gates execution there. OpenHands' current GitHub Action supports repository targeting and polling.

No Supabase service-role credential is given to the engineering agent. Product data stays behind Supabase/RLS and server-side functions.

## Database execution state

Production now contains \`public.ai_agent_runs\` plus service-only claim/complete functions. This gives the agent plane a durable execution record without exposing agent credentials or internal run state to public clients.

## Definition of done

A task is not complete merely because the agent says it is complete. The repository must have:
- focused diff;
- no secrets;
- migration/RLS/security review;
- Flutter analyze/tests;
- relevant APK/Web build;
- GitHub Actions evidence;
- PR review;
- explicit release decision.

## Existing agent stack

- Aider: architecture/editor workflow
- mini-SWE-agent: bounded issue-fix loop
- OpenHands: long-running agent runtime and GitHub execution
- Jev Ultrafast: structured browser decision layer
- OpenSandbox/SWE-ReX: isolation/execution candidates
- Supabase: product state and event bus
- n8n: external business automation

The executor is intentionally a composition of these capabilities, not a monolithic runtime.
