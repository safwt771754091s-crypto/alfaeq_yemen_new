# Alfaeq Yemen — Claude Chrome User Testing Integration

The `claude-chrome-user-testing` repository is approved as a **development/staging QA capability**, not as a production runtime dependency.

## Capabilities to adopt

- critical-path smoke testing for web
- multi-persona UX testing
- Arabic/RTL persona testing
- mobile/tablet/desktop viewport testing
- slow-network/offline behavior testing
- WCAG accessibility audits
- broken-link checks
- form security fuzzing in isolated staging environments
- Playwright trace/session evidence
- JSON results suitable for CI

## Alfaeq critical paths

The first journeys to automate are:

1. Sign in / sign up
2. Browse section
3. Open product
4. Add product to cart
5. Checkout
6. Order status
7. Merchant product/inventory workflow
8. Delivery tracking
9. Support/chat
10. Arabic RTL navigation

## Safety boundary

- Run against preview/staging or a dedicated test environment.
- Never point fuzzing, checkout simulation, or destructive tests at production.
- Do not create real financial transactions.
- Use test accounts and test payment providers/cards only.
- Keep Supabase production data authoritative and untouched by QA fixtures.

## CI target

After the production web preview is available, add a separate browser-QA workflow that:
- waits for the preview URL,
- runs smoke/critical-path tests,
- stores JSON/trace artifacts,
- fails the workflow on critical journey regressions.

This repository is MIT and is a fork; exact upstream/plugin changes must still be reviewed before importing source.
