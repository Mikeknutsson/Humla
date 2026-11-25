import 'server-only';
import {admin} from './server';
import type {SawInvoiceCoverage} from './saw-invoices';

const resource = 'saw_article_check_v1';

export async function saveSawControl(tenant: string, coverage: SawInvoiceCoverage) {
  const {error} = await admin().from('hub_fortnox_raw').upsert({
    tenant_id:tenant,resource,external_id:coverage.from+'_'+coverage.to,
    payload:coverage,fetched_at:new Date().toISOString(),
  },{onConflict:'tenant_id,resource,external_id'});
  if (error) throw Error('Underlaget gick inte att spara.');
}

export async function readSawControl(tenant: string, from: string, to: string) {
  const db = admin();
  const [{data:connection},{data:snapshot}] = await Promise.all([
    db.from('hub_fortnox_connections').select('connected_at').eq('tenant_id',tenant).maybeSingle(),
    db.from('hub_fortnox_raw').select('payload,fetched_at').eq('tenant_id',tenant).eq('resource',resource)
      .lte('payload->>from',from).gte('payload->>to',to).order('fetched_at',{ascending:false}).limit(1).maybeSingle(),
  ]);
  return {connected:Boolean(connection),snapshot:snapshot ? {
    ...(snapshot.payload as SawInvoiceCoverage),fetchedAt:snapshot.fetched_at as string,
  } : null};
}
