import {redirect} from 'next/navigation';
import Link from 'next/link';
import {createClient} from '@/lib/supabase/server';
import {KpiDetailShell} from '@/app/_components/kpi-detail-shell';
import {AssetTcoWorkspace} from '@/app/_components/asset-tco-workspace';
import {FleetKpiWorkspace} from '@/app/_components/fleet-kpi-workspace';
import {KpiMonthPeriod} from '@/app/_components/kpi-month-period';
import {parseMonthPeriod,monthPeriodQuery} from '@/lib/kpi/period';
import type {AssetTcoReport} from '@/lib/hub/asset-tco';
import type {AssetRegisterReport} from '@/lib/hub/asset-register';
import type {FleetComparisonReport} from '@/lib/hub/fleet-kpi';
import {buildMarketDiscovery} from '@/lib/hub/market-discovery';
export const dynamic='force-dynamic';
export default async function Page({searchParams}:{searchParams:Promise<{asset?:string;date?:string;tab?:string;fiscal_year?:string;months?:string;department?:string}>}){
 const db=await createClient();const {data:{user}}=await db.auth.getUser();if(!user)redirect('/kpi/login');
 const {data:member}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').limit(1).maybeSingle();if(!member)redirect('/kpi');
 const q=await searchParams;const today=new Intl.DateTimeFormat('sv-SE',{timeZone:'Europe/Stockholm'}).format(new Date());
 const asOf=/^\d{4}-\d{2}-\d{2}$/.test(q.date??'')?q.date!:today;
 const asset=q.asset&&/^[0-9a-f-]{36}$/i.test(q.asset)?q.asset:null;const isTco=q.tab==='tco';
 let period;try{period=parseMonthPeriod(q.fiscal_year,q.months);}catch{return <KpiDetailShell query="" title="Fordon & maskiner"><div className="content"><section className="panel"><p role="alert">Ogiltig period. Välj ett verksamhetsår och minst en månad.</p><Link href="/kpi/fordon">Återställ perioden</Link></section></div></KpiDetailShell>;}
 const params=new URLSearchParams(monthPeriodQuery(period));if(asset)params.set('asset',asset);if(q.department)params.set('department',q.department);params.set('date',asOf);
 const fleetHref=`/kpi/fordon?${params}`;params.set('tab','tco');const tcoHref=`/kpi/fordon?${params}`;
 const result=isTco?await db.rpc('hub_asset_market_review_v1',{p_tenant:member.tenant_id,p_as_of:asOf,p_asset:asset}):await db.rpc('hub_fleet_comparison_v1',{p_tenant:member.tenant_id,p_year:period.fiscalYear,p_months:period.months,p_asset:asset,p_department:q.department||null});
 const registerResult=isTco?{data:(result.data as {register?:AssetRegisterReport}|null)?.register??null,error:null}:null;
 const {data,error}=result;
 const selectedTco=isTco&&!error?(data as AssetTcoReport)?.assets.find(a=>a.id===asset):null;
 const discovery=selectedTco?buildMarketDiscovery(selectedTco):null;
 return <KpiDetailShell query={monthPeriodQuery(period)} title="Fordon & maskiner" breadcrumb="Humla / Fordonsansvarig"><div className="content"><nav className="panel" aria-label="Fordonsvyer"><div className="fiscal-shortcuts"><Link className={isTco?'secondary':'primary'} aria-current={!isTco?'page':undefined} prefetch={false} href={fleetHref}>Fordons-KPI</Link><Link className={isTco?'primary':'secondary'} aria-current={isTco?'page':undefined} prefetch={false} href={tcoHref}>TCO & marknadsvärde</Link></div></nav>
 {error?<section className="panel"><h2>Fordonsvyn kunde inte öppnas</h2><p role="alert">{error.code==='42501'?'Du behöver behörigheten Visa fordonskostnader och TCO.':'Underlaget kunde inte hämtas. Kontrollera perioden och försök igen.'}</p></section>:isTco?<><AssetTcoWorkspace report={data as AssetTcoReport} register={registerResult?.error?null:registerResult?.data as AssetRegisterReport|null} selectedId={asset} today={today} discovery={discovery}/>{registerResult?.error&&<section className="panel"><p role="alert">Anläggningsunderlaget kunde inte hämtas. Försök igen.</p></section>}</>:<><KpiMonthPeriod period={period} costCenter="" costCenters={[]} pathname="/kpi/fordon" showFilters={false}/><FleetKpiWorkspace report={data as FleetComparisonReport} selectedId={asset} department={q.department??''}/></>}
 </div></KpiDetailShell>;
}
