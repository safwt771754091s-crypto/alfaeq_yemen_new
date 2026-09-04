# WhatsApp OTP setup — Alfaeq Yemen

The `whatsappOtp` Firebase Function sends registration OTPs through WhatsApp Cloud API. No WhatsApp credential belongs in the Flutter app or Git repository.

## Firebase / Secret Manager

Set these values:

```bash
firebase functions:secrets:set WHATSAPP_ACCESS_TOKEN
firebase functions:secrets:set WHATSAPP_PHONE_NUMBER_ID
```

The function also uses these parameters:

- `WHATSAPP_OTP_TEMPLATE` — approved WhatsApp authentication template name. Default: `alfaeq_otp`.
- `WHATSAPP_OTP_LANGUAGE` — template language code. Default: `ar`.

Then deploy only the function:

```bash
firebase deploy --only functions:whatsappOtp
```

The WhatsApp template must accept one body text parameter for the six-digit OTP. The Meta/WhatsApp Business account must have the sending phone number configured and the required messaging permission.

## Test flow

1. Register in Alfaeq Yemen with a phone number in international format, e.g. `+9677xxxxxxxx`.
2. The app obtains a Firebase ID token and calls `whatsappOtp`.
3. The function sends the OTP and stores only a SHA-256 hash of the code for five minutes.
4. Enter the six-digit code in the app.
5. On success, Firebase gets the `whatsappVerified` custom claim and the user's Firestore record is updated.
6. Login is accepted when either WhatsApp or the fallback email is verified.
