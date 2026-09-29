# OpenHands Engineering Pattern

Alfaeq Yemen adopts selected OpenHands V1 architectural patterns for its engineering-agent layer. OpenHands itself is not embedded in the Flutter production binary.

## What we take

OpenHands V1 separates the system into composable boundaries:

- Agent: reasoning/action loop.
- Conversation: lifecycle and the single mutable source of conversation state.
- Tools: typed capabilities.
- Workspace: execution location.
- Agent Server: remote HTTP/WebSocket boundary.
- Automation: scheduling, webhooks, run history, and dispatch.

The V1 design favors immutable typed components, one explicit mutable state owner, composition over inheritance, and clear boundaries between the agent SDK and applications.

## Alfaeq architecture

The intended engineering-agent plane is:

Event / task
  -> Automation / dispatcher
  -> Agent Server
  -> Conversation
  -> Agent + Skills + Tools
  -> Isolated Workspace
  -> Git diff / commit
  -> Analyze / Test / Security checks
  -> GitHub Actions
  -> human/release gate

The production application plane remains separate:

Flutter
  -> Supabase Auth/RLS
  -> transactional domain functions
  -> canonical Event Bus
  -> n8n / external automation
  -> business services

An engineering agent may change source code and migrations in a controlled workspace, but it must not directly mutate production business data or receive production service-role credentials.

## State ownership

For agent workflows:

- Conversation state has one explicit owner.
- Durable product state remains owned by Supabase.
- Event state remains owned by the canonical event inbox/event bus.
- UI state must not become a second source of truth.

This prevents divergent state between Flutter, agents, automation, and PostgreSQL.

## Skills and tools

Use composable, typed capabilities rather than a monolithic agent implementation.

Examples for Alfaeq engineering:

- repository inspection
- Flutter analyze/test/build
- Supabase migration verification
- schema inspection
- Git diff/review
- security/RLS inspection
- event-contract verification
- CI status verification

Production business capabilities remain behind application APIs and database permissions.

## Security

Remote Agent Server deployments require authentication and secure transport. Never expose an unauthenticated agent endpoint to a public network because an agent can execute commands and read/write its workspace.

Use isolated workspaces for autonomous code-changing tasks whenever possible. Production secrets must remain outside the agent workspace.

## Relationship to Aider and mini-SWE-agent

Aider:
- interactive architecture/editor workflow.

mini-SWE-agent:
- minimal bounded linear autonomous execution loop.

OpenHands:
- composable long-running agent runtime, conversation state, workspace abstraction, tools/skills, remote Agent Server, and automation boundary.

They are complementary engineering patterns. None is a dependency of the Flutter runtime.

## Production gate

Agent completion is never equivalent to production readiness.

Production readiness requires the repository gates to pass: formatting/static analysis, tests, migration verification, security/RLS review, and GitHub Actions build/release evidence.
