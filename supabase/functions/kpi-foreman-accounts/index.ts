import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const reply = (status: number, body: object) => Response.json(body, {
  status,
  headers: { "Cache-Control": "no-store" },
});
const fail = (status: number, error: string) => reply(status, { error });
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return fail(405, "method");
  const token = request.headers.get("Authorization")?.match(/^Bearer (\S+)$/i)?.[1];
  if (!token) return fail(401, "access");

  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) return fail(503, "unavailable");
  const admin = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: { user }, error: authError } = await admin.auth.getUser(token);
  if (authError || !user) return fail(401, "access");

  let input;
  try { input = await request.json(); }
  catch { return fail(400, "validation"); }
  if (!input || typeof input.tenantId !== "string" || !uuid.test(input.tenantId)) return fail(400, "validation");
  const tenantId = input.tenantId;
  const { data: owner, error: ownerError } = await admin.from("hub_tenant_members")
    .select("tenant_id").eq("tenant_id", tenantId).eq("user_id", user.id)
    .eq("status", "active").eq("role", "owner").maybeSingle();
  if (ownerError) return fail(503, "unavailable");
  if (!owner) return fail(403, "access");

  if (input.action === "list") {
    const { data: members, error } = await admin.from("hub_tenant_members")
      .select("user_id,display_name,role,status").eq("tenant_id", tenantId).order("display_name");
    if (error) return fail(503, "unavailable");
    const accounts = await Promise.all((members ?? []).map(async (member) => {
      const account = await admin.auth.admin.getUserById(member.user_id);
      return { ...member, email: account.data.user?.email ?? null };
    }));
    return reply(200, { members: accounts });
  }

  const password = typeof input.password === "string" ? input.password : "";
  if (input.action === "create" || input.action === "reset") {
    if (password.length < 12 || new TextEncoder().encode(password).length > 72) return fail(400, "validation");
  }

  if (input.action === "create") {
    const email = typeof input.email === "string" ? input.email.trim().toLowerCase() : "";
    const name = typeof input.name === "string" ? input.name.trim() : "";
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254 || !name || name.length > 120) {
      return fail(400, "validation");
    }
    const { data, error } = await admin.auth.admin.createUser({ email, password, email_confirm: true });
    if (error || !data.user) {
      return fail(400, error?.code === "email_exists" || error?.code === "user_already_exists" ? "duplicate" : "create");
    }
    const membership = await admin.from("hub_tenant_members").insert({
      tenant_id: tenantId, user_id: data.user.id, role: "supervisor", status: "active", display_name: name,
    });
    if (membership.error) {
      const cleanup = await admin.auth.admin.deleteUser(data.user.id);
      if (cleanup.error) console.error("Could not remove account after failed membership insert", cleanup.error.code);
      return fail(500, "membership");
    }
    return reply(200, { ok: true });
  }

  if (input.action !== "status" && input.action !== "reset") return fail(400, "validation");
  if (typeof input.id !== "string" || !uuid.test(input.id)) return fail(400, "validation");
  const { data: member, error: memberError } = await admin.from("hub_tenant_members")
    .select("user_id").eq("tenant_id", tenantId).eq("user_id", input.id).eq("role", "supervisor").maybeSingle();
  if (memberError) return fail(503, "unavailable");
  if (!member) return fail(403, "access");

  if (input.action === "status") {
    if (input.status !== "active" && input.status !== "inactive") return fail(400, "validation");
    const { error } = await admin.from("hub_tenant_members").update({ status: input.status })
      .eq("tenant_id", tenantId).eq("user_id", member.user_id).eq("role", "supervisor").select("user_id").single();
    return error ? fail(500, "update") : reply(200, { ok: true });
  }

  const { data: otherMemberships, error: otherMemberError } = await admin.from("hub_tenant_members")
    .select("user_id").eq("user_id", member.user_id).neq("tenant_id", tenantId).limit(1);
  if (otherMemberError) return fail(503, "unavailable");
  if (otherMemberships.length) return fail(403, "shared_account");
  const { error } = await admin.auth.admin.updateUserById(member.user_id, { password });
  return error ? fail(500, "reset") : reply(200, { ok: true });
});
