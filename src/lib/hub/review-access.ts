import 'server-only';
import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';

/** Recheck membership and permission on every request; never pick an arbitrary tenant. */
export async function reviewAccess() {
  const db = await createClient();
  const { data: { user }, error } = await db.auth.getUser();
  if (error || !user) redirect('/kpi/login');
  const member = await db.from('hub_tenant_members').select('tenant_id')
    .eq('user_id', user.id).eq('status', 'active').maybeSingle();
  if (member.error || !member.data) return null;
  const permission = await db.rpc('hub_has_permission', { p_tenant_id: member.data.tenant_id, p_permission: 'kpi.read' });
  if (permission.error || permission.data !== true) return null;
  return { db, tenantId: member.data.tenant_id };
}

export function reviewPage(value?: string) {
  return value && /^\d{1,6}$/.test(value) ? Math.min(Number(value), 100000) : 0;
}
