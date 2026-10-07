import 'server-only';
import {unstable_cache} from 'next/cache';
import {getKpiReportStatus} from './report-sync';
/** Membership and KPI permission are checked before every call. Reports are
 * isolated per user, tenant, prepared Hub generation and exact scope.
 * The Dashboard refresh action invalidates all reports for the current user. */
export async function cachedKpiReport<T>(userId:string,tenantId:string,scope:unknown,load:()=>Promise<{data:T|null;error:{message:string;code?:string}|null}>) {
 try {
  const status=await getKpiReportStatus(tenantId);
  if(status.error||!status.data?.generation)throw new Error('Prepared Hub report unavailable');
  const data=await unstable_cache(async()=>{
   const result=await load();
   if(result.error||!result.data)throw new Error(result.error?.message??'Hub report unavailable');
   return result.data;
  },['kpi-report-prepared-v7',userId,tenantId,status.data.generation,JSON.stringify(scope)],{revalidate:86400,tags:[`kpi-report:${userId}`]})();
  return {data,error:null};
 }catch(error){return {data:null,error:{message:error instanceof Error?error.message:'Hub report unavailable',code:undefined as string|undefined}};}
}
