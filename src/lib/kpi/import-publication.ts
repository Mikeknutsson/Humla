import 'server-only';
import {revalidateTag} from 'next/cache';
import type {createClient} from '@/lib/supabase/server';
import {invalidatePaymentSourceSessions} from '@/lib/hub/payment-source-session';

/** Call only after an authorized import has committed. A queue failure must not
 * turn an already saved import into a failed batch or encourage a replay. */
export async function queueImportedKpiData(db:Awaited<ReturnType<typeof createClient>>,tenantId:string,userId:string){
 try{
 invalidatePaymentSourceSessions(tenantId);
 revalidateTag('kpi-report:'+userId,{expire:0});
 revalidateTag('kpi-tenant-report:'+tenantId,{expire:0});
  const {data,error}=await db.rpc('hub_kpi_request_report_sync_v1',{p_tenant_id:tenantId});
  if(error||!data)return {reportSync:null,reportSyncWarning:'Filen är sparad, men rapportomräkningen kunde inte begäras. Använd Synka innan du använder rapporterna.'};
  return {reportSync:data,reportSyncWarning:null};
 }catch{
  return {reportSync:null,reportSyncWarning:'Filen är sparad, men rapportomräkningen kunde inte begäras. Använd Synka innan du använder rapporterna.'};
 }
}
