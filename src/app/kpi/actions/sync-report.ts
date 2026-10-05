'use server';
import {createClient} from '@/lib/supabase/server';
import type {ReportSyncStatus} from '@/lib/kpi/report-sync';

export async function syncKpiReport():Promise<{data?:ReportSyncStatus;error?:string}> {
 const db=await createClient();
 const {data:{user}}=await db.auth.getUser();
 if(!user)return {error:'Logga in för att synka.'};
 const {data:member}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').limit(1).maybeSingle();
 if(!member)return {error:'Arbetsyta saknas.'};
 // Hub checks kpi.manage and only queues work; no computation in this request.
 const {data,error}=await db.rpc('hub_kpi_request_report_sync_v1',{p_tenant_id:member.tenant_id});
 if(error)return {error:error.code==='42501'?'Du saknar behörighet att synka KPI.':'Synkningen kunde inte startas. Senaste underlaget ligger kvar.'};
 return {data:data as ReportSyncStatus};
}
