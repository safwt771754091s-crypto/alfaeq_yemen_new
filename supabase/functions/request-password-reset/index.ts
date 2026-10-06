// request-password-reset — email a password recovery link.
//
// Supabase's built-in mailer is not configured for this project, so we mint a
// recovery link with the service role and deliver it through Resend, matching
// the existing `notify-login-event` delivery path.
//
// The endpoint always reports success so it cannot be used to enumerate which
// emails have accounts.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const MAIL_FROM = Deno.env.get("AUTH_EMAIL_FROM") ?? "onboarding@resend.dev";
const DEFAULT_REDIRECT = "https://safwt771754091s-crypto.github.io/alfaeq_yemen_new/";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return Response.json(body, { status, headers: corsHeaders });
}

function escapeHtml(value: string) {
  return value.replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const body = await req.json().catch(() => ({}));
  const email = String(body?.email ?? "").trim().toLowerCase();
  if (!email || !email.includes("@")) return json({ error: "invalid_email" }, 400);

  // Without server mail configuration we cannot deliver; report success anyway
  // so the caller cannot distinguish a missing account from a mail failure.
  if (!RESEND_API_KEY || !SUPABASE_URL || !SERVICE_ROLE_KEY) {
    return json({ ok: true });
  }

  const redirectTo = String(body?.redirectTo ?? DEFAULT_REDIRECT).trim() || DEFAULT_REDIRECT;
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    const { data, error } = await admin.auth.admin.generateLink({
      type: "recovery",
      email,
      options: { redirectTo },
    });
    if (error || !data?.properties?.action_link) {
      return json({ ok: true });
    }

    const link = escapeHtml(data.properties.action_link);
    const html = `<!doctype html><html dir="rtl" lang="ar"><body style="font-family:system-ui,Segoe UI,Tahoma,sans-serif;background:#f6f7f9;padding:24px">
  <div style="max-width:520px;margin:auto;background:#fff;border-radius:16px;padding:28px">
    <h2 style="margin:0 0 12px">إعادة تعيين كلمة المرور</h2>
    <p style="color:#444;line-height:1.7">وصلنا طلب لتعيين كلمة مرور جديدة لحسابك في الفائق يمن. اضغط الزر أدناه لإتمام العملية.</p>
    <p style="text-align:center;margin:26px 0">
      <a href="${link}" style="background:#0a7d32;color:#fff;text-decoration:none;padding:13px 26px;border-radius:10px;font-weight:700;display:inline-block">تعيين كلمة مرور جديدة</a>
    </p>
    <p style="color:#888;font-size:13px;line-height:1.7">إذا لم تطلب هذا، تجاهل الرسالة. الرابط صالح لفترة محدودة.</p>
  </div>
</body></html>`;

    const resend = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: MAIL_FROM,
        to: [email],
        subject: "إعادة تعيين كلمة المرور — الفائق يمن",
        html,
      }),
    });
    if (!resend.ok) {
      // Log the provider reason server-side only: it can name the Resend
      // account owner's address and would enable account enumeration.
      console.error("resend_rejected", resend.status, (await resend.text().catch(() => "")).slice(0, 300));
    }
  } catch (error) {
    console.error("reset_email_failed", String(error).slice(0, 200));
  }
  return json({ ok: true });
});
