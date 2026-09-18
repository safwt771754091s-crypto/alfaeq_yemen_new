# WhatsApp Business Cloud API — Alfaeq Yemen

## Production endpoint
Webhook:
https://us-central1-alfaeq-yemen-fed37.cloudfunctions.net/whatsappWebhook

## Firebase Secrets
Create these in Firebase Secret Manager before deploying Functions:
- WHATSAPP_VERIFY_TOKEN
- WHATSAPP_ACCESS_TOKEN
- WHATSAPP_APP_SECRET
- WHATSAPP_PHONE_NUMBER_ID
- WHATSAPP_API_VERSION

Do not place these values in GitHub source, Flutter code, Firestore, or chat.

## Meta setup
1. Create/use a Meta app with WhatsApp Business Platform.
2. Add the WhatsApp Business Account and business phone number.
3. Configure the webhook callback URL above.
4. Use the same value as WHATSAPP_VERIFY_TOKEN in Meta's Verify Token field.
5. Subscribe the webhook to the messages field.
6. Subscribe the app to the WABA so message events are delivered.
7. Keep the Phone Number ID in WHATSAPP_PHONE_NUMBER_ID.
8. Use a long-lived/system-user access token for production and store it as WHATSAPP_ACCESS_TOKEN.

Meta webhook verification uses the GET hub.mode/hub.verify_token/hub.challenge handshake. POST notifications must be authenticated with X-Hub-Signature-256 using the Meta App Secret.

## Alfaeq Yemen WhatsApp product format

Example:

اسم: سكر
سعر: 1200
الوحدة: كجم
المخزون: 25
الخطوة: 0.25
الحد الأدنى: 0.25

The webhook creates a safe import draft. The product is not published unless the configured authorization and confirmation rules allow it.

Supported units:
piece, kg, g, l, ml, m

Weighted inventory is normalized to a base unit:
- kg -> g
- l -> ml
- piece/g/ml/m -> themselves

## Production sequence when Cloud Functions deployment is available

1. Deploy Functions with deploy_functions.yml.
2. Verify GET webhook handshake from Meta.
3. Subscribe the WABA to the app.
4. Link the merchant WhatsApp number to its store in مركز الإدارة > أتمتة واتساب.
5. Send the sample product message.
6. Confirm the generated draft.
7. Verify Firestore collections: products, whatsappMessages, whatsappProductImports, and auditLogs.
8. Only after this end-to-end test consider auto-publish for a trusted merchant.

## Security
App Check remains enabled for callable functions. The webhook itself is authenticated by Meta's signature and does not bypass Firebase Security Rules for client-side callable operations.
