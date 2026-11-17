import Link from 'next/link';
import {Suspense} from 'react';
import {WorkshopInternalJobs} from './workshop-internal-jobs';
import {validTransportDate} from '@/lib/kpi/transport-leader';
import {reviewAccess} from '@/lib/hub/review-access';
import {stockholmToday} from '@/lib/kpi/period';
import {foremanPeriodQuery,resolveForemanPeriod} from '@/lib/kpi/foreman-period';
import {analysisHref} from '@/lib/kpi/analysis';
import type {Dashboard} from '@/app/_components/kpi-app';
import {KpiDetailShell} from '@/app/_components/kpi-detail-shell';
import {ForemanPeriodPicker} from '@/app/_components/foreman-period-picker';
import {KpiMarginGauge} from '@/app/_components/kpi-margin-gauge';
import {KpiMonthChart,type MonthlyPoint} from '@/app/_components/kpi-month-chart';
import {WorkshopTimeKpi} from '@/app/_components/workshop-time-kpi';
import {KpiPrint} from '@/app/_components/kpi-print';

export const dynamic='force-dynamic';
export const maxDuration=60;
const currency=new Intl.NumberFormat('sv-SE',{style:'currency',currency:'SEK',maximumFractionDigits:0});
const number=new Intl.NumberFormat('sv-SE',{maximumFractionDigits:1});
const money=(n:unknown)=>n==null||!Number.isFinite(Number(n))?'Underlag saknas':currency.format(Number(n));
const costs:Record<string,string>={personnel:'Personal',fuel:'Bränsle',service_repair:'Service och reparation',fixed:'Fasta kostnader',depreciation:'Avskrivning',material:'Material',tipp_deponi:'Tipp och deponi',hired:'Inhyrda',management:'Arbetsledning',overhead:'Övrig overhead',other:'Övrigt'};
type WorkshopReport=Dashboard & {monthly?:MonthlyPoint[];previous?:{metrics?:Dashboard['metrics']};sync?:{synced_at?:string}};

export default async function Workshop({searchParams}:{searchParams:Promise<Record<string,string|undefined>>}){
 const access=await reviewAccess();
 if(!access)return <main className="content"><h1>Du saknar åtkomst till verkstadens uppföljning.</h1></main>;
 const raw=await searchParams;
 let period:ReturnType<typeof resolveForemanPeriod>;
 try{
  period=resolveForemanPeriod(raw,null,stockholmToday());
  if(!raw.period_mode&&!raw.fiscal_year&&raw.from&&raw.to){
   if(!validTransportDate(raw.from)||!validTransportDate(raw.to)||raw.from>raw.to)throw new Error('Invalid period');
   period={...period,from:raw.from,to:raw.to};
  }
  if(!period.to)throw new Error('Missing date');
 }
 catch{return <main className="content"><h1>Ogiltigt periodval</h1><Link href="/kpi/verkstad">Återställ</Link></main>;}
 const from=period.from,to=period.to!;
 // Always request the fixed workshop scope from Hub; URL filters cannot widen it.
 const selection:Record<string,string>=period.mode==='months'?{fiscal_year:String(period.fiscalYear),months:period.months.join(',')}:{};
 const query=new URLSearchParams({from,to,cost_center:'40',...selection}).toString();
 const resourcePeriodQuery=new URLSearchParams({from,to,cost_center:'40'});
 if(raw.period_mode||raw.fiscal_year)for(const [key,value] of foremanPeriodQuery(period))resourcePeriodQuery.set(key,value);
 const {data,error}=await (period.mode==='months'?access.db.rpc('hub_kpi_overview_months_v1',{p_tenant_id:access.tenantId,p_fiscal_year:period.fiscalYear,p_selected_months:period.months,p_cost_center:'40',p_filters:{}}):access.db.rpc('hub_kpi_cost_center_dashboard_v1',{p_tenant_id:access.tenantId,p_from:from,p_to:to,p_cost_center:'40'})).abortSignal(AbortSignal.timeout(48_000));
 const report=data as WorkshopReport|null;
 const valid=!error&&report?.cost_center_scope==='40';
 const objects=valid?(report.economic_units??[]).flatMap(unit=>unit.children.map(child=>({unit:unit.key,child}))):[];
 const projectNumbers=[...new Set(objects.flatMap(({child})=>!child.vehicle&&child.project?[child.project]:[]))];
 const registrations=[...new Set(objects.flatMap(({child})=>child.vehicle?[child.vehicle]:[]))];
 const [projects,vehicles]=await Promise.all([
  projectNumbers.length?access.db.from('kpi_next_project_register').select('project_number,project_name')
   .eq('tenant_id',access.tenantId).in('project_number',projectNumbers):null,
  registrations.length?access.db.from('hub_identity_keys')
   .select('identity_value,vehicle:hub_objects!hub_identity_keys_object_id_fkey!inner(make:data->>make,model:data->>model)')
   .eq('tenant_id',access.tenantId).eq('identity_type','registration_number').in('identity_value',registrations)
   .eq('vehicle.tenant_id',access.tenantId).eq('vehicle.object_type','Vehicle')
   .overrideTypes<Array<{identity_value:string;vehicle:{make:string|null;model:string|null}}>,{merge:false}>():null,
 ]);
 const projectNames=new Map(projects?.data?.flatMap(p=>p.project_name?.trim()?[[p.project_number,p.project_name.trim()] as const]:[])??[]);
 const vehicleNames=new Map(vehicles?.data?.flatMap(row=>{
  const names=[row.vehicle?.make,row.vehicle?.model].filter((value):value is string=>typeof value==='string'&&!!value.trim());
  return names.length?[[row.identity_value,names.join(' ')] as const]:[];
 })??[]);
 const previous=valid&&report.comparison_available!==false?report.previous?.metrics:undefined;
 const months=(report?.monthly??[]).filter(p=>p.period_start<=to&&p.period_end>=from&&(period.mode!=='months'||period.months.includes(Number(p.period_start.slice(5,7)))));
 const metric=(key:string)=>valid?report.metrics[key]:null;
 return <KpiDetailShell title="Verkstaden – arbetsledarvy" breadcrumb="Humla Dashboard / Verkstad / KST 40" query={query} extraNavigation={<Link prefetch={false} href="/kpi/mina-enheter">Arbetsledarvyer</Link>}>
 <div className="content"><section className="panel"><div className="panel-head"><div><h2>Verkstaden · KST 40</h2><p>Ekonomi, kostnadsfördelning och registrerad verkstadstid · Läsåtkomst</p></div><div><Link prefetch={false} className="primary" href="#internjobb">Internjobb · NeXT</Link>{' '}<KpiPrint/></div></div><ForemanPeriodPicker period={period} pathname="/kpi/verkstad" showRevenueShortcut={false}/></section>
 {!valid?<section className="panel" role="alert"><h2>Verkstadsunderlaget kunde inte hämtas</h2><p>Försök igen med samma period. Saknade belopp visas inte som noll.</p></section>:<>
 <section className="metrics-grid">{([['Intäkter','revenue'],['Kostnader','total_cost'],['Resultat','result']]as const).map(([label,key])=><article className="metric-card" key={key}><span>{label}</span><strong>{money(metric(key))}</strong><small>Samma period föregående år: {money(previous?.[key])}</small></article>)}<article className="metric-card"><span>Marginal</span><KpiMarginGauge label="Verkstaden" margin={metric('margin_pct')==null?null:Number(metric('margin_pct'))} target={20}/><small>Standardmål 20 % · Skala −50 till +50 %</small></article></section>
 {Number(metric('revenue'))===0&&<section className="panel" role="status"><p>Inga intäkter finns registrerade på KST 40 i valt underlag. Resultatet visar därför kostnadsbelastningen. Marginal kan inte beräknas utan intäkter. Internt debiterbar verkstadstid visas separat och räknas inte automatiskt som intäkt.</p></section>}
 <WorkshopTimeKpi query={query}/>
 {months.length>0&&<KpiMonthChart points={months} query={query}/>}
 <section className="panel"><h2>Kostnader – verkstaden</h2><div className="table-wrap"><table><thead><tr><th>Kostnadsslag</th><th>Belopp</th></tr></thead><tbody>{Object.entries(report.cost_categories??{}).map(([key,value])=><tr key={key}><td><Link prefetch={false} href={analysisHref(query,{kind:'cost',category:key})}>{costs[key]??key} →</Link></td><td>{money(value)}</td></tr>)}</tbody><tfoot><tr><th>Total kostnad</th><td>{money(metric('total_cost'))}</td></tr></tfoot></table></div><p>Beloppen ingår redan i totalen. {report.personnel_basis}</p></section>
 <section className="panel">
  <h2>Projekt och fordon i verkstadens ekonomi</h2>
  <div className="table-wrap"><table>
   <thead><tr><th scope="col">Objekt</th><th scope="col">Intäkter</th><th scope="col">Kostnader</th><th scope="col">Resultat</th></tr></thead>
   <tbody>{objects.map(({unit,child})=>{
    const name=child.vehicle?vehicleNames.get(child.vehicle):child.project?projectNames.get(child.project):null;
    const reference=child.vehicle??child.project;
    return <tr key={unit+':'+child.key}>
     <td><Link prefetch={false} href={analysisHref(query,{unit,vehicle:child.vehicle,project:child.vehicle?null:child.project})}>
      {name&&reference?<><strong>{name}</strong><br/><small>{child.vehicle?'Regnr':'Projekt'} {reference} →</small></>:<>{child.label} →</>}
     </Link></td>
     <td>{money(child.revenue)}</td><td>{money(child.cost)}</td><td>{money(child.result)}</td>
    </tr>;
   })}</tbody>
  </table></div>
  {(projects?.error||vehicles?.error)&&<p role="status">Vissa projektnamn eller fordonsuppgifter kunde inte hämtas.</p>}
  <p>Visar poster som hör till KST 40. Verkstadsarbete som redan belastar ett annat kostnadsställe flyttas inte tillbaka hit.</p>
 </section>
 <section className="panel"><h2>Underlag</h2><p>{number.format(Number(report.quality?.valid_rows??0))} giltiga ekonomirader. Samma publicerade Hub-underlag som Dashboard, avgränsat till KST 40.</p><p>{report.sync?.synced_at?'Senast uppdaterat: '+new Intl.DateTimeFormat('sv-SE',{dateStyle:'short',timeStyle:'short',timeZone:'Europe/Stockholm'}).format(new Date(report.sync.synced_at)):'Uppdateringstid saknas.'}</p><Link prefetch={false} href={analysisHref(query)}>Visa originalrader →</Link> · <Link prefetch={false} href={'/kpi/projekt?'+new URLSearchParams({from,to,center:'40',...selection})}>Projektuppföljning →</Link></section>
 </>}
 <Suspense fallback={<section id="internjobb" className="panel"><h2>Internjobb · NeXT</h2><p role="status">Hämtar internjobb…</p></section>}>
  <WorkshopInternalJobs access={access} q={raw} from={from} to={to} months={period.months} periodQuery={resourcePeriodQuery.toString()}/>
 </Suspense>
 </div></KpiDetailShell>;
}
