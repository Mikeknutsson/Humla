import { createClient } from "@/lib/supabase/server";
import {
  ACCOUNT_CATEGORIES, CALCULATION_ROLES, validRoleCategory,
  type AccountCategory, type CalculationRole,
} from "@/lib/kpi/account-mapping";

export const runtime = "nodejs";

async function context() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { error: Response.json({ error: "Inloggning krävs." }, { status: 401 }) };
  const { data: member } = await supabase.from("hub_tenant_members").select("tenant_id").eq("user_id", user.id).eq("status", "active").limit(1).maybeSingle();
  if (!member) return { error: Response.json({ error: "Aktiv KPI-arbetsyta saknas." }, { status: 403 }) };
  const { data: allowed } = await supabase.rpc("hub_has_permission", { p_tenant_id: member.tenant_id, p_permission: "kpi.manage" });
  if (!allowed) return { error: Response.json({ error: "KPI-administratör krävs." }, { status: 403 }) };
  return { supabase, user, tenantId: member.tenant_id };
}

function integer(value: unknown) {
  if (typeof value !== "number" && (typeof value !== "string" || !/^\d+$/.test(value.trim()))) return null;
  const parsed = Number(value);
  return Number.isInteger(parsed) ? parsed : null;
}

function date(value: unknown, required = false) {
  const text = String(value ?? "").trim();
  if (!text && !required) return null;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) return undefined;
  const parsed = new Date(`${text}T00:00:00Z`);
  return Number.isFinite(parsed.getTime()) && parsed.toISOString().slice(0, 10) === text ? text : undefined;
}

function payload(body: Record<string, unknown>) {
  const accountFrom = integer(body.accountFrom);
  const accountTo = integer(body.accountTo ?? body.accountFrom);
  const priority = integer(body.priority ?? 100);
  const name = String(body.name ?? "").trim();
  const role = String(body.calculationRole ?? "") as CalculationRole;
  const category = String(body.costCategory ?? "") as AccountCategory;
  const validFrom = date(body.validFrom, true);
  const validTo = date(body.validTo);
  if (accountFrom === null || accountTo === null || accountFrom < 0 || accountTo > 99999999 || accountTo < accountFrom) throw new Error("Kontointervallet är ogiltigt.");
  if (!name || name.length > 120) throw new Error("Ange ett namn på högst 120 tecken.");
  if (!(role in CALCULATION_ROLES) || !(category in ACCOUNT_CATEGORIES) || !validRoleCategory(role, category)) throw new Error("Roll och kategori är inte en giltig kombination.");
  if (priority === null || priority < 0 || priority > 10000) throw new Error("Prioriteten måste vara 0–10000.");
  if (!validFrom || validTo === undefined || (validTo && validTo < validFrom)) throw new Error("Giltighetsperioden är ogiltig.");
  return {
    account_from: accountFrom,
    account_to: accountTo,
    name,
    calculation_role: role,
    cost_category: category,
    include_in_vehicle_result: Boolean(body.includeInVehicleResult),
    priority,
    valid_from: validFrom,
    valid_to: validTo,
    notes: String(body.notes ?? "").trim() || null,
  };
}

export async function POST(request: Request) {
  const auth = await context();
  if ("error" in auth) return auth.error;
  try {
    const values = payload(await request.json());
    const { data, error } = await auth.supabase.from("kpi_account_mappings").insert({
      ...values, tenant_id: auth.tenantId, created_by: auth.user.id, updated_by: auth.user.id,
    }).select("id").single();
    if (error?.code === "23505") return Response.json({ error: "Samma kontointervall och startdatum finns redan." }, { status: 409 });
    if (error) throw error;
    return Response.json({ id: data.id }, { status: 201 });
  } catch (error) {
    return Response.json({ error: error instanceof Error ? error.message : "Kontomappningen kunde inte sparas." }, { status: 400 });
  }
}

export async function PATCH(request: Request) {
  const auth = await context();
  if ("error" in auth) return auth.error;
  try {
    const body = await request.json() as Record<string, unknown>;
    const id = String(body.id ?? "");
    if (!/^[0-9a-f-]{36}$/i.test(id)) return Response.json({ error: "Ogiltigt regel-ID." }, { status: 400 });
    const update = body.action === "toggle"
      ? { enabled: Boolean(body.enabled), updated_by: auth.user.id, updated_at: new Date().toISOString() }
      : { ...payload(body), updated_by: auth.user.id, updated_at: new Date().toISOString() };
    const { data, error } = await auth.supabase.from("kpi_account_mappings").update(update).eq("id", id).eq("tenant_id", auth.tenantId).select("id").maybeSingle();
    if (error) throw error;
    if (!data) return Response.json({ error: "Regeln hittades inte." }, { status: 404 });
    return Response.json({ id: data.id });
  } catch (error) {
    return Response.json({ error: error instanceof Error ? error.message : "Kontomappningen kunde inte uppdateras." }, { status: 400 });
  }
}
