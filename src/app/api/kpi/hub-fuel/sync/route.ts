import { createClient } from "@/lib/supabase/server";

export const runtime = "nodejs";
export const maxDuration = 60;

// Authenticated, bounded historical sync through the existing Hub PIUSI connector.
// Hub owns PIUSI credentials, canonical deduplication and transaction persistence.
export async function POST(request: Request) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return Response.json({ error: "Inloggning krävs." }, { status: 401 });
  const { data: member } = await supabase.from("hub_tenant_members")
    .select("tenant_id").eq("user_id", user.id).eq("status", "active").maybeSingle();
  if (!member) return Response.json({ error: "Aktivt företag saknas." }, { status: 403 });
  const { data: allowed } = await supabase.rpc("hub_has_permission", {
    p_tenant_id: member.tenant_id, p_permission: "hub.connections.manage",
  });
  if (!allowed) return Response.json({ error: "Behörighet saknas." }, { status: 403 });
  const { data: connection, error: connectionError } = await supabase.from("hub_connections")
    .select("id").eq("tenant_id", member.tenant_id).eq("connector_type", "piusi_bsmart").single();
  if (connectionError || !connection) return Response.json({ error: "B.Smart-anslutning saknas." }, { status: 404 });
  const { startDate, endDate } = await request.json() as { startDate?: string; endDate?: string };
  const start = startDate ? new Date(startDate) : new Date(Date.now() - 2 * 86400000);
  const end = endDate ? new Date(endDate) : new Date();
  if (!Number.isFinite(start.getTime()) || !Number.isFinite(end.getTime()) ||
      start > end || end.getTime() > Date.now() + 86400000 ||
      end.getTime() - start.getTime() > 31 * 86400000) {
    return Response.json({ error: "Ange ett giltigt intervall om högst 31 dagar. Kör äldre månader separat." }, { status: 400 });
  }
  const { data: { session } } = await supabase.auth.getSession();
  if (!session?.access_token) return Response.json({ error: "Sessionen behöver förnyas." }, { status: 401 });
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!base || !anon) return Response.json({ error: "Supabase-konfiguration saknas." }, { status: 500 });
  const response = await fetch(`${base}/functions/v1/piusi-sync`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${session.access_token}`,
      apikey: anon,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      action: "transactions", connection_id: connection.id,
      start_date: start.toISOString(), end_date: end.toISOString(),
    }),
    cache: "no-store",
  });
  const result = await response.json().catch(() => ({}));
  if (!response.ok) return Response.json({
    error: "Humla Hub kunde inte synkronisera B.Smart.", stage: result.stage ?? null,
  }, { status: 502 });
  return Response.json({
    syncedAt: result.synced_at, period: result.period,
    received: result.piusi_received, pages: result.api_pages_used,
    result: result.result,
  }, { headers: { "Cache-Control": "no-store" } });
}
