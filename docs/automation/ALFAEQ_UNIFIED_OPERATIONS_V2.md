# Alfaeq Unified Operations Plane v2

## Purpose
One canonical n8n workflow for Alfaeq external automation. Supabase remains the source of truth for commerce, inventory, wallet/ledger and transactional state.

## Flow
Supabase automation-worker -> n8n `alfaeq-events` -> Validate & Normalize -> Unified Event Router -> AI Gate / External Channel Router -> channel adapter -> Respond.

## Included channels
- AI Control Plane: only `ai.*` events are sent to `ai-event-worker`.
- WhatsApp Automation: `whatsapp.*` events use `ALFAEQ_WHATSAPP_AUTOMATION_URL`.
- Google Chat: `notification.*` and chat events can use `ALFAEQ_GOOGLE_CHAT_WEBHOOK_URL`.
- Notification Dispatcher: `notification.*` can use `ALFAEQ_NOTIFICATION_WEBHOOK_URL`.
- Google Sheets: catalog/store/merchant/customer events can append to the configured Automation Events sheet.

## n8n variables required
- `ALFAEQ_N8N_SHARED_SECRET`
- `ALFAEQ_WHATSAPP_AUTOMATION_URL`
- `ALFAEQ_GOOGLE_CHAT_WEBHOOK_URL`
- `ALFAEQ_NOTIFICATION_WEBHOOK_URL`
- `ALFAEQ_GOOGLE_SHEETS_DOCUMENT_ID`
- optional `ALFAEQ_GOOGLE_SHEETS_TAB`

The Google Sheets node requires an authorized n8n Google Sheets OAuth credential named `Alfaeq Google Sheets`. External URLs/credentials are intentionally not stored in Git.

## Transaction boundary
n8n does not directly mutate orders, stock, wallets, settlements or other transactional business state. Those operations remain in Supabase/RPC/Edge Functions. n8n performs orchestration and external side effects.

## Activation
Import `n8n/alfaeq_unified_operations_plane_v2.json` into the production n8n workflow and activate it only after the listed external variables/credentials exist. The repository change does not itself grant OAuth access or create third-party credentials.

## Verification contract
A production-ready state requires successful end-to-end tests for:
1. `order.created`
2. `inventory.*`
3. `product.created/updated`
4. `merchant.*`
5. `notification.*`
6. `whatsapp.*`
7. `chat_message.*`
8. `ai.requested`
9. Google Sheets append
10. Google Chat delivery
11. WhatsApp delivery

No external channel is considered active merely because its node exists in the imported workflow.
