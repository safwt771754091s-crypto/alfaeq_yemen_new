
# Alfaeq Project Executor

## Purpose

The Project Executor turns an engineering request into a bounded agent execution. It is an engineering-plane component; it does not execute production business mutations.

## Execution contract

```
Issue / task
  -> ai_tasks
  -> agent claim
  -> ai_agent_runs
  -> OpenHands conversation
  -> isolated workspace
  -> inspect / plan / edit
  -> tests / build / security audit
  -> focused PR
  -> GitHub Actions
  -> independent verification
  -> release gate
```

### Durable ownership

- `public.ai_tasks`: canonical engineering work item.
- `public.ai_agent_runs`: durable attempt, provider, repository, branch, external run ID, conversation ID, status and result.
- OpenHands Conversation: agent execution state.
- Git/GitHub: source history and PR state.
- Supabase product tables: production business state; engineering agents do not write them directly.

### Provider boundary

The executor must treat OpenHands as a provider behind a narrow API boundary. Provider-specific identifiers are recorded in `ai_agent_runs.external_run_id` and `ai_agent_runs.conversation_id`.

If OpenHands is unavailable, the task remains recoverable and must not be marked succeeded.

### Release gate

A successful agent conversation is not a successful release. Completion requires:

1. clean focused diff;
2. no committed secrets;
3. migration/RLS review where applicable;
4. formatting/static analysis/tests;
5. relevant Flutter/Web/Android build;
6. security-audit gate;
7. GitHub Actions evidence;
8. human/release approval before merge or production deployment.

### Safety

The executor must never pass production service-role credentials to the agent. Browser automation and target-controlled commands require an isolated environment with resource limits. External paid/live checks remain separate from offline CI.
