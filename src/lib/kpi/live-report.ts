import 'server-only';
import {cookies} from 'next/headers';
import {createClient} from '@/lib/supabase/server';
import {cachedKpiReport} from '@/lib/kpi/report-cache';
import {parseMonthPeriod} from '@/lib/kpi/period';
import {filterKeys} from '@/lib/kpi/analysis';
import {selectionCookie,selectionFromQuery,readSavedSelection} from '@/lib/kpi/selection';
import type {KpiAppProps,Dashboard} from '@/app/_components/kpi-app';

type Report = Dashboard & {
 monthly:KpiAppProps['overviewMonthly']; previous:Dashboard|null;
 transpa_vehicle_time:KpiAppProps['transpaVehicleTime'];
 efficiency:KpiAppProps['efficiency']; hired_capacity:KpiAppProps['hiredCapacity'];
 driver_productivity:KpiAppProps['driverProductivity'];
};

// Read the same prepared Hub report as the page, without rendering a new page.
// Recheck membership and permissions on every call, including cache hits.
export async function loadKpiPeriod(query:string) {
 if(query.length>4000)throw new Error('Ogiltigt urval.');
 const p=new URLSearchParams(query);
 const monthPeriod=parseMonthPeriod(p.get('fiscal_year')??undefined,p.get('months')??undefined);
 const activeFilters=Object.fromEntries(filterKeys.filter(k=>p.get(k)).map(k=>[k,p.get(k)!]));
 const costCenter=p.get('cost_center')?.trim()||null;
 const from=`${monthPeriod.fiscalYear}-09-01`,to=`${monthPeriod.fiscalYear+1}-08-31`;
 const db=await createClient();
 const {data:{user}}=await db.auth.getUser();
 if(!user)throw new Error('Logga in igen för att hämta rapporten.');
 const {data:member,error:memberError}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').limit(1).maybeSingle();
 if(memberError||!member)throw new Error('Arbetsytan kunde inte öppnas.');
 const {data:canRead,error:permissionError}=await db.rpc('hub_has_permission',{p_tenant_id:member.tenant_id,p_permission:'kpi.read'});
 if(permissionError||!canRead)throw new Error('KPI-behörigheten kunde inte verifieras.');
 const result=await cachedKpiReport<Report>(user.id,member.tenant_id,{useMonths:true,monthPeriod,costCenter,activeFilters,from,to},async()=>db.rpc('hub_kpi_overview_months_v1',{p_tenant_id:member.tenant_id,p_fiscal_year:monthPeriod.fiscalYear,p_selected_months:monthPeriod.months,p_cost_center:costCenter,p_filters:activeFilters}));
 if(result.error||!result.data)throw new Error('Rapporten kunde inte hämtas. Tidigare urval visas fortfarande. Försök igen.');
 const saved=JSON.stringify({version:1,query:selectionFromQuery(p).toString()});
 if(readSavedSelection(saved))(await cookies()).set(selectionCookie(user.id),saved,{httpOnly:true,secure:process.env.NODE_ENV==='production',sameSite:'lax',path:'/',maxAge:31536000});
 const dashboard=result.data;
 return {monthPeriod,activeFilters,from,to,dashboard,overviewMonthly:dashboard.monthly??[],overviewPrevious:dashboard.previous??null,
  overviewPeriod:{current:{from,to},previous:{from:`${monthPeriod.fiscalYear-1}-09-01`,to:`${monthPeriod.fiscalYear}-08-31`},label:`${monthPeriod.fiscalYear}/${monthPeriod.fiscalYear+1}`},
  transpaVehicleTime:dashboard.transpa_vehicle_time??null,efficiency:dashboard.efficiency??null,hiredCapacity:dashboard.hired_capacity??null,driverProductivity:dashboard.driver_productivity??null};
}
