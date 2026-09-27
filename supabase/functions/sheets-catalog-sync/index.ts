import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const SYNC_SECRET = Deno.env.get("ALFAEQ_SHEETS_SYNC_SECRET") ?? "";
const MAX_ROWS = 1000;

const sectionIds = new Set([
  "markets", "restaurants", "pharmacies", "beauty", "construction", "cars",
  "travel", "hotels", "banks", "services", "electronics", "real_estate",
  "jobs", "education", "health", "local_tourism",
]);

const text = (value: unknown) => String(value ?? "").trim();
const num = (value: unknown) => {
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  const parsed = Number(text(value).replace(/,/g, ""));
  return Number.isFinite(parsed) ? parsed : null;
};

function normalizeRows(input: unknown): Record<string, unknown>[] {
  if (Array.isArray(input)) return input.filter((r) => r && typeof r === "object") as Record<string, unknown>[];
  if (input && typeof input === "object") {
    const obj = input as Record<string, unknown>;
    if (Array.isArray(obj.rows)) return normalizeRows(obj.rows);
  }
  return [];
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return Response.json({ ok: false, error: "method_not_allowed" }, { status: 405 });
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY || !SYNC_SECRET) {
    return Response.json({ ok: false, error: "server_configuration_missing" }, { status: 500 });
  }

  const supplied = req.headers.get("x-alfaeq-sheets-secret") ?? "";
  if (!supplied || supplied !== SYNC_SECRET) {
    return Response.json({ ok: false, error: "unauthorized" }, { status: 401 });
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return Response.json({ ok: false, error: "invalid_json" }, { status: 400 });
  }

  const entity = text(body.entity).toLowerCase();
  const dryRun = body.dry_run === true;
  const rows = normalizeRows(body.rows ?? body.data);

  if (!["product", "customer"].includes(entity)) {
    return Response.json({ ok: false, error: "unsupported_entity", allowed: ["product", "customer"] }, { status: 400 });
  }
  if (!rows.length) return Response.json({ ok: false, error: "rows_required" }, { status: 400 });
  if (rows.length > MAX_ROWS) return Response.json({ ok: false, error: "too_many_rows", max_rows: MAX_ROWS }, { status: 413 });

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const job = crypto.randomUUID();
  const errors: Array<{ row: number; error: string }> = [];
  let applied = 0;
  const reject = (row: number, error: string) => { if (errors.length < 100) errors.push({ row, error }); };

  if (entity === "product") {
    for (let i = 0; i < rows.length; i++) {
      const row = rows[i];
      const reference = text(row.reference ?? row.ref ?? row.sku);
      const name = text(row.name ?? row.product_name);
      const storeId = text(row.store_id ?? row.storeId);
      const sectionId = text(row.section_id ?? row.sectionId ?? row.category_id ?? row.category);
      const price = num(row.price);
      const description = text(row.description);
      const imageUrl = text(row.image_url ?? row.imageUrl ?? row.image);
      const currency = text(row.currency) || "YER";
      const status = text(row.status) || "active";
      const saleUnit = text(row.sale_unit) || "piece";

      if (!reference) { reject(i + 2, "reference مطلوب"); continue; }
      if (!name) { reject(i + 2, "name مطلوب"); continue; }
      if (!storeId) { reject(i + 2, "store_id مطلوب"); continue; }
      if (!sectionId || !sectionIds.has(sectionId)) { reject(i + 2, "section_id غير صالح: " + sectionId); continue; }
      if (price === null || price < 0) { reject(i + 2, "price غير صالح"); continue; }
      if (!["active", "inactive", "draft", "archived"].includes(status)) { reject(i + 2, "status غير صالح"); continue; }

      const { data: store, error: storeError } = await admin.from("stores").select("id,owner_id").eq("id", storeId).maybeSingle();
      if (storeError || !store) { reject(i + 2, "المتجر غير موجود"); continue; }

      const { data: existing, error: findError } = await admin.from("products")
        .select("id").eq("store_id", storeId).eq("reference", reference).limit(1).maybeSingle();
      if (findError) { reject(i + 2, "تعذر البحث عن المنتج: " + findError.message); continue; }

      const patch: Record<string, unknown> = {
        store_id: storeId,
        section_id: sectionId,
        owner_id: text(row.owner_id) || store.owner_id,
        reference,
        name,
        description,
        image_url: imageUrl,
        price,
        currency,
        sale_unit: saleUnit,
        status,
        metadata: { source: "google_sheets", sync_job: job },
      };

      // Inventory is deliberately not changed here. Stock mutations must use the inventory/ledger path.
      if (dryRun) { applied++; continue; }

      if (existing?.id) {
        const { error } = await admin.from("products").update(patch).eq("id", existing.id);
        if (error) reject(i + 2, error.message); else applied++;
      } else {
        const { error } = await admin.from("products").insert({
          id: crypto.randomUUID(),
          ...patch,
          stock: 0,
          stock_base: 0,
          unit_label: saleUnit === "piece" ? "قطعة" : saleUnit,
          base_unit: saleUnit,
          unit_scale: 1,
          step_base: 1,
          min_order_base: 1,
          sold_quantity: 0,
          sold_quantity_base: 0,
        });
        if (error) reject(i + 2, error.message); else applied++;
      }
    }
  } else {
    for (let i = 0; i < rows.length; i++) {
      const row = rows[i];
      const uid = text(row.uid ?? row.user_id);
      if (!uid) { reject(i + 2, "uid مطلوب؛ لا يتم إنشاء حسابات Auth من Google Sheets"); continue; }
      const patch: Record<string, unknown> = {};
      if (row.name !== undefined) patch.name = text(row.name);
      if (row.metadata !== undefined && typeof row.metadata === "object") patch.metadata = row.metadata;
      if (!Object.keys(patch).length) { reject(i + 2, "لا توجد حقول مسموح بتعديلها"); continue; }
      if (dryRun) { applied++; continue; }

      const { error } = await admin.from("users").update({ ...patch, updated_at: new Date().toISOString() }).eq("uid", uid);
      if (error) reject(i + 2, error.message); else applied++;
    }
  }

  const result = {
    ok: errors.length === 0, job_id: job, entity, dry_run: dryRun,
    rows_received: rows.length, rows_applied: applied, rows_rejected: errors.length, errors,
  };

  await admin.from("automation_import_jobs").insert({
    id: job, source: "google_sheets", entity,
    status: errors.length ? "completed_with_errors" : "completed",
    rows_received: rows.length, rows_applied: applied, rows_rejected: errors.length,
    errors, dry_run: dryRun,
  });

  return Response.json(result, { status: errors.length ? 207 : 200 });
});
