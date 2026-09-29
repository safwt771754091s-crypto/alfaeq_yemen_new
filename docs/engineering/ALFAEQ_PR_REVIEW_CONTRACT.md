# Alfaeq PR Review Contract

Date: 2026-09-29

## Purpose

Apply the useful pr-inbox pattern to Alfaeq: review state and evidence must be explicit rather than relying on memory or an agent final message.

## Review contract

For every production-relevant PR, identify:

- PR number and repository
- head commit SHA
- scope and affected architectural boundary
- acceptance criteria
- changed files and relevant migration/function changes
- tests executed and results
- CI workflow evidence
- security considerations
- event/idempotency impact, when applicable
- unresolved review comments
- final verification evidence

## Review states

- unreviewed — no verified review evidence exists for the current head SHA.
- reviewed — the current head SHA has been inspected against the contract.
- changes-requested — a correctness, security or operational issue remains.
- verified — required checks passed and review evidence matches the current head SHA.

A new commit invalidates verified state until the changed head is reviewed again.

## Evidence rule

Review evidence is immutable by commit identity. Do not claim a PR is verified from evidence belonging to an older head SHA.

## Safety

pr-inbox is a review workflow reference only. No PR automation may merge, deploy, mutate production data, or approve a financial operation solely because an AI agent produced a recommendation.

## Source

Reference repository: safwt771754091s-crypto/pr-inbox
