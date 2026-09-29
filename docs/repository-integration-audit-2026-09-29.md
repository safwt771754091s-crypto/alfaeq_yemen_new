# Alfaeq Yemen — Repository Integration Audit (2026-09-29)

## Decision rule
External repositories are treated as reference implementations or isolated services. Core business truth remains in Supabase; no repository is copied wholesale into the Flutter application.

## Audited and actionable

| Repository | Finding | Alfaeq action |
|---|---|---|
| learn-harness-engineering | Reliable agent/harness design, verification and control patterns | Adopt as engineering methodology and CI evidence policy |
| agent-skills | DEFINE → PLAN → BUILD → VERIFY → REVIEW → SHIP lifecycle | Adopt as delivery gates; do not add runtime dependency |
| security-audit-skill | Coverage-led security hunting, independent validation, structured findings | Existing Alfaeq security gate is aligned; extend audits rather than copy runtime |
| Jev | Structured decision primitives and guardrail-oriented model interface | Candidate AI decision/guardrail adapter; keep outside transactional path |
| jev-ultrafast | Browser agent with constrained action space | Candidate isolated browser-automation worker |
| OpenHands | Self-hosted agent control center and webhook/scheduled automations | Candidate internal engineering/operations agent plane |
| DeerFlow | Super-agent harness with sub-agents, memory, sandboxes and tracing | Candidate research/operations plane; not order processing |
| Langfuse | LLM tracing, evaluation, prompt/version management | Candidate AI observability layer |
| Firecrawl | Search/scrape/interact/crawl and structured web extraction | Candidate catalog/research ingestion service |
| Crawl4AI | Async crawler and structured extraction | Candidate lower-cost/self-hosted ingestion worker |
| Website-downloader | Website source/assets ingestion | Candidate website import utility, isolated from product truth |
| Docling | PDF/Office/image/audio parsing and OCR | Candidate document ingestion pipeline |
| LightRAG | RAG + knowledge graph + multimodal/document support | Candidate knowledge layer for AI assistant |
| GraphRAG | Graph-based context pipeline; project is maintenance mode | Reference only; prefer LightRAG for new work |
| PinchTab | Local-first browser control with privileged control surfaces | Candidate isolated browser worker; never expose directly to public users |
| Impeccable | Deterministic UI/a11y/performance design checks | Adopt as frontend QA methodology |
| drawDB | ERD/SQL schema visualization | Reference/tooling only |

## Important repository integrity findings
- `OpenSandbox` in this account currently contains an Alfaeq localization example rather than the expected OpenSandbox project; do not treat it as the upstream OpenSandbox implementation.
- `VoiceStudio` is AGPL-3.0. Treat it as a separate optional service; do not copy its source into the core Alfaeq application without a deliberate license review.
- `GraphRAG` is explicitly in maintenance mode; it should not become a new core dependency.

## Architecture rule
Flutter -> Supabase -> Event Bus/automation_events -> automation-worker -> n8n/external workers.

AI, browser automation, web ingestion, RAG and observability remain downstream services. They may propose or enrich actions, but they must not become the source of truth for orders, inventory, payments, wallets or settlements.

## Current verified build evidence
Commit `a18aeacd7c6aeb17ff16f6429639596d1eee5a0d` passed:
- Flutter CI run 36618307013
- Build Fresh Alfaeq Yemen Android run 36618306844
- Flutter Build run 36618306843
- Alfaeq Yemen Android Release run 36618307062

These are CI/build results, not proof that production payments, settlements or live n8n automation are operational.
