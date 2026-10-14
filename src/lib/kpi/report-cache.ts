import 'server-only';
import {unstable_cache} from 'next/cache';
import {getKpiReportStatus} from './report-sync';
/** Membership and KPI permission are checked before every call. Reports are
 * isolated per user, tenant, prepared Hub generation and exact scope.
 * The Dashboard refresh action invalidates all reports for the current user. */
export async function cachedKpiReport<T>(userId:string,tenantId:string,scope:unknown,load:()=>Promise<{data:T|null;error:{message:string;code?:string}|null}>) {
 try {
  const status=await getKpiReportStatus(tenantId);
  if(status.error||!status.data?.generation)throw Object.assign(new Error(status.error?.message??'Prepared Hub report unavailable'),{code:status.error?.code??'HUB_GENERATION_UNAVAILABLE'});
  const data=await unstable_cache(async()=>{
   const result=await load();
   if(result.error||!result.data)throw Object.assign(new Error(result.error?.message??'Hub report unavailable'),{code:result.error?.code??'HUB_REPORT_UNAVAILABLE'});
   return result.data;
  },['kpi-report-prepared-v10',userId,tenantId,status.data.generation,String(status.data.correction_revision??0),JSON.stringify(scope)],{revalidate:86400,tags:[`kpi-report:${userId}`]})();
  return {data,error:null};
 }catch(error){return {data:null,error:{message:error instanceof Error?error.message:'Hub report unavailable',code:error instanceof Error&&'code' in error&&typeof error.code==='string'?error.code:'REPORT_LOAD_FAILURE'}};}
}
