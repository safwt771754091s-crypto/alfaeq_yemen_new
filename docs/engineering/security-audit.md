# Alfaeq Security Audit Engineering

The `security-audit-skill` fork is used as the security-methodology reference for the Alfaeq engineering-agent plane.

## What Alfaeq adopts

The security workflow is a six-phase gate:

1. reconnaissance: architecture, trust boundaries, inputs, prior evidence, deterministic coverage ledger;
2. coverage-led hunting by isolated workers;
3. independent candidate validation by a fresh verifier whose job is to disprove the candidate;
4. schema-validated machine-readable findings;
5. independent verification of the final records;
6. reports derived only from verified records.

The three finding states are deliberately distinct:

- `confirmed`: source trace plus bounded observed evidence establishes the security failure;
- `needs_validation`: the source evidence is meaningful but a decisive fact is unavailable;
- `rejected`: the candidate was disproved.

A clean scanner result is not a security verdict.

## Alfaeq security boundary

Security review applies across both planes:

**Production plane**

Flutter -> Supabase Auth/RLS -> transactional functions -> event bus -> automation/integrations.

**Engineering-agent plane**

GitHub event -> dispatcher -> agent runtime -> isolated workspace -> inspect/edit/test -> security audit -> diff review -> PR -> GitHub Actions -> release gate.

The engineering agents must not receive production service-role credentials or directly mutate production business data.

## Security domains for Alfaeq

The audit coverage ledger should explicitly include:

- Supabase Auth, JWT/session handling and RLS;
- tenant/store/merchant isolation;
- order, inventory, payment, wallet and settlement authorization;
- Edge Functions and webhook authentication;
- event idempotency, replay and trust boundaries;
- n8n and external automation ingress/egress;
- AI agents, prompt injection and tool permissions;
- browser automation and target freshness;
- secrets, API keys and CI/CD environments;
- dependencies, supply chain, release artifacts and signing;
- Flutter deep links, WebViews and exported Android components;
- data export, deletion, backup and lifecycle;
- resource exhaustion, queues and worker limits.

## Execution rule

Target-controlled builds, tests, fuzzers, browsers and fixtures must run only in an OS-enforced isolated sandbox with:

- no external network;
- sanitized allowlisted environment;
- bounded CPU, memory, processes, disk and wall time;
- write access restricted to an assigned scratch directory.

If the required isolation is unavailable, the result remains `needs_validation`; do not execute untrusted target-controlled code against production or shared infrastructure.

## Release gate

An agent may propose or implement a fix, but security completion requires:

1. source-grounded finding/fix evidence;
2. independent verification;
3. migration/RLS review when database behavior changes;
4. Flutter analyze/tests and relevant builds;
5. GitHub Actions evidence;
6. human/release approval.

The skill is a security control for the engineering plane, not a Flutter runtime dependency.
