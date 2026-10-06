import 'server-only';
import {cache} from 'react';
import {createClient} from '@/lib/supabase/server';

export type ReportSyncStatus = {
 generation:string|null;
 synced_at:string|null;
 status:'queued'|'ready'|'failed'|'unavailable';
 requested_at?:string;
 can_sync:boolean;
 error?:string|null;
 schedule:string;
};

// Request-local deduplication, never share authenticated status across tenants.
export const getKpiReportStatus=cache(async(tenantId:string)=>{
 const db=await createClient();
 const {data,error}=await db.rpc('hub_kpi_report_status_v1',{p_tenant_id:tenantId});
 return {data:data as ReportSyncStatus|null,error};
});
