import 'server-only';
import type { SupabaseClient } from '@supabase/supabase-js';
export type RepairFinancialScope = { id: string; published: boolean; reason: string };
export async function repairFinancialScope(db: SupabaseClient, tenant: string, ids: string[]) {
  const unique = [...new Set(ids)], rows: RepairFinancialScope[] = [];
  for (let offset = 0; offset < unique.length; offset += 1000) {
    const { data, error } = await db.rpc('hub_repair_financial_scope_v1', { p_tenant: tenant, p_ids: unique.slice(offset, offset + 1000) });
    if (error || !Array.isArray(data)) throw new Error('Reparationskostnadernas källkoppling kunde inte verifieras.');
    rows.push(...data as RepairFinancialScope[]);
  }
  return new Map(rows.map(row => [row.id, row]));
}
