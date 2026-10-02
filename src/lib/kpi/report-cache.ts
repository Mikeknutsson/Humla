import 'server-only';
import {unstable_cache} from 'next/cache';
/** Membership and KPI permission are checked before every call. Reports are
 * isolated per user, tenant and exact scope, and refreshed each Stockholm day.
 * The Dashboard refresh action invalidates all reports for the current user. */
export async function cachedKpiReport<T>(userId:string,tenantId:string,scope:unknown,load:()=>Promise<{data:T|null;error:{message:string;code?:string}|null}>) {
 const day=new Intl.DateTimeFormat('sv-SE',{timeZone:'Europe/Stockholm',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
 try {
  const data=await unstable_cache(async()=>{
   const result=await load();
   if(result.error||!result.data)throw new Error(result.error?.message??'Hub report unavailable');
   return result.data;
  },['kpi-report-daily-v1',userId,tenantId,day,JSON.stringify(scope)],{revalidate:86400,tags:[`kpi-report:${userId}`]})();
  return {data,error:null};
 }catch(error){return {data:null,error:{message:error instanceof Error?error.message:'Hub report unavailable',code:undefined as string|undefined}};}
}
