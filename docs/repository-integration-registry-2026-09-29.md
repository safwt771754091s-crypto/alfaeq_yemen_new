# Alfaeq Yemen — Full Repository Integration Registry
Date: 2026-09-29

This registry covers the repositories discovered in the user's GitHub account during the 2026-09-29 audit. The decision is to integrate capabilities, not copy repositories wholesale.

## Direct integration / engineering value
- alfaeq_yemen_new — core production app; keep as system of record.
- alfaeq_yemen — compare for reusable domain logic only.
- alfaeqyemen — compare for reusable domain logic only.
- n8n — automation orchestration.
- Jev — structured AI decision/guardrail adapter.
- jev-ultrafast — isolated browser automation worker.
- learn-harness-engineering — reliability/verification methodology.
- agent-skills — delivery workflow methodology.
- security-audit-skill — security review methodology.
- paperclip — candidate internal AI-agent operations plane.
- OpenHands — candidate engineering agent plane.
- deer-flow — candidate research/operations agent plane.
- langfuse — AI observability candidate.
- firecrawl — web ingestion/search service; keep isolated because AGPL.
- crawl4ai — self-hosted web ingestion worker.
- Website-downloader — website import utility.
- docling — document ingestion/OCR service.
- LightRAG — AI knowledge/RAG layer.
- pinchtab — isolated browser worker.
- impeccable — frontend accessibility/UI quality methodology.
- drawdb — schema/design tooling.
- gaia — agent orchestration governance, execution contracts, memory separation, and deterministic safety gates.

## Useful references / optional services
- GPT-researcher
- open_deep_research
- PaperQA
- OpenScholar
- Kotaemon
- Vane
- GraphRAG
- Understand-Anything
- Resala
- VoiceStudio (separate AGPL service only)
- OpenSandbox (account copy inspected; not assumed to be upstream OpenSandbox)
- Agent-Reach
- orca
- Buzz
- Reader
- Scrapling
- storm
- papermage
- m3e-canvas
- Website-downloader
- awesome-claude-skills
- awesome-claude-prompts
- ui-ux-pro-max-skill
- superpowers
- opencode
- aider
- mini-swe-agent
- spec-kit
- cli
- free-claude-code
- Naive-N0.5-Flash
- VoiceStudio
- vicoa

## Product/app references that must not become core dependencies without separate review
- nowinandroid
- vscode-hexeditor
- purge-app
- optimizerDuck
- awesome-free-apps
- fictional-octo-enigma
- ponytail
- kotaemon
- OpenSandbox account copy
- Aden-Super-App.
- alfaeq-alfaeq-yemenyemen
- alfaig-yemen-assets
- docs

## License/supply-chain guardrails
- Do not copy AGPL source from Firecrawl or VoiceStudio into the core Flutter/Supabase repository.
- Treat all forks as external reference code until the exact files and license obligations are reviewed.
- No service-role keys or private credentials may enter repositories.
- AI/browser/RAG/ingestion systems remain downstream of Supabase.

## Production architecture
Flutter -> Supabase/Auth/Postgres/RLS -> transactional domain functions -> automation_events -> automation-worker -> n8n/external workers -> AI/RAG/browser/ingestion/observability.

Orders, inventory, payments, wallets and settlements remain authoritative in Supabase/Postgres.

## Execution status
The first engineering gate from claude-skills has been added under docs/engineering/ALFAEQ_CLAUDE_SKILLS_GATES.md.
The next integration work should prioritize real services rather than adding documentation-only dependencies.
