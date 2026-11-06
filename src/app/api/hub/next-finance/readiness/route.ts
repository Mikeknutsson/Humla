import { createClient } from '@/lib/supabase/server';
import { NEXT_FINANCE_CONTRACT } from '@/lib/hub/next-finance';

export const dynamic = 'force-dynamic';
/** Preparation status only. Deliberately no POST, token handling or activation. */
export async function GET() {
  const db = await createClient();
  const { data: { user } } = await db.auth.getUser();
  if (!user) return Response.json({ error: 'Inloggning krävs' }, { status: 401 });
  const { data: member, error } = await db.from('hub_tenant_members').select('tenant_id').eq('user_id', user.id).eq('status', 'active').maybeSingle();
  if (error || !member) return Response.json({ error: 'Entydig aktiv arbetsyta krävs' }, { status: 403 });
  const permission = await db.rpc('hub_has_permission', { p_tenant_id: member.tenant_id, p_permission: 'kpi.manage' });
  if (permission.error || permission.data !== true) return Response.json({ error: 'Behörighet saknas' }, { status: 403 });
  const connections = await db.from('hub_connections')
    .select('id,name,status,configuration,last_success_at')
    .eq('tenant_id', member.tenant_id).eq('connector_type', 'next_project_api');
  if (connections.error) return Response.json({ error: 'Anslutningsstatus kunde inte hämtas' }, { status: 503 });
  // Only expose operational status; never return configuration or credential references.
  const connectionStatus = (connections.data ?? []).map(connection => ({
    id: connection.id, name: connection.name, status: connection.status,
    environment: connection.configuration?.environment ?? 'unknown',
    readOnly: connection.configuration?.read_only !== false,
    lastSuccessAt: connection.last_success_at,
  }));
  return Response.json({ ...NEXT_FINANCE_CONTRACT, enabled: false, tenantId: member.tenant_id,
    connections: connectionStatus, financialLedgerConnected: false,
  }, { headers: { 'Cache-Control': 'private, no-store' } });
}
