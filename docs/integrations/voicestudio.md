# VoiceStudio integration

Alfaeq Yemen can use a separately deployed VoiceStudio backend for speech features without embedding the VoiceStudio desktop application or its server code into the Flutter application.

## Integrated contracts

- GET /health — backend readiness
- GET /v1/audio/voices — discover real installed voices
- POST /v1/audio/speech — text-to-speech
- POST /v1/audio/transcriptions — speech-to-text

The Flutter bridge is in lib/services/voice_studio_service.dart.

## Configuration

Do not hard-code a production VoiceStudio server URL or bearer token.

Build with VOICESTUDIO_BASE_URL and, when required by the deployment, VOICESTUDIO_API_KEY.

If VOICESTUDIO_BASE_URL is empty, the speech service is simply unavailable and the core Alfaeq app remains independent from it.

## Architecture

Flutter app -> VoiceStudio HTTPS API -> local or remote speech engine.

For n8n or other server-side automation, call the VoiceStudio API from the automation environment rather than exposing a local 127.0.0.1 endpoint to the public internet.

For AI-agent workflows, VoiceStudio's MCP interface can provide speech and transcription tools. Keep the MCP endpoint protected and reachable only from a trusted integration environment.

## License boundary

VoiceStudio is licensed AGPL-3.0-only. Alfaeq does not copy the VoiceStudio desktop/backend source into the Flutter application. This integration reuses documented API contracts while keeping the VoiceStudio runtime as a separate service.

Before redistributing modified VoiceStudio source or linking its source into the Alfaeq distribution, review the AGPL obligations and the licenses of individual speech models.

## Security

- Never commit VOICESTUDIO_API_KEY.
- Use HTTPS/WSS for remote deployments.
- Do not expose an unauthenticated VoiceStudio MCP endpoint to the public internet.
- Voice cloning should only be used with an authorized reference recording.
- Treat generated audio and recordings as user data and apply Alfaeq access controls and retention policy.
