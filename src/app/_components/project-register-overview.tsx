import Link from 'next/link';
import type {createClient} from '@/lib/supabase/server';
import {projectPeriodParams,projectReportHref,type ProjectPeriod} from '@/lib/kpi/project-period';
import styles from '@/app/kpi/projekt/project-report.module.css';

type RegisterProject={
 project_number:string; project_name:string; project_manager:string|null; source_center:string|null; cost_center_name:string|null;
 source_business_groups:string|null; cost_center:string|null; business_group:string|null; kpi_project_id:string|null;
 has_identity:boolean; booked_amount:number|null; booked_rows:number;
};
type RegisterResult={
 latest:{file_name:string;row_count:number;completed_at:string|null;created_at:string}|null;
 matched:number; projects:RegisterProject[];
};
type Context={db:Awaited<ReturnType<typeof createClient>>;tenant:string;selection:ProjectPeriod};
const money=new Intl.NumberFormat('sv-SE',{style:'currency',currency:'SEK',minimumFractionDigits:2,maximumFractionDigits:2});
const number=new Intl.NumberFormat('sv-SE');
const time=new Intl.DateTimeFormat('sv-SE',{dateStyle:'short',timeStyle:'short',timeZone:'Europe/Stockholm'});

async function getRegister({db,tenant,selection}:Context,search:string,page:number,exact=false){
 const {data,error}=await db.rpc('hub_kpi_project_register_overview',{
  t:tenant,p_from:selection.from,p_to:selection.to,p_months:selection.months,p_search:search,p_page:page,p_exact:exact,
 }).abortSignal(AbortSignal.timeout(20000));
 return error?null:data as RegisterResult|null;
}

export async function ProjectRegisterOverview({search,page,...context}:Context&{search:string;page:number}){
 const {selection}=context;
 const period=projectPeriodParams(selection);
 const report=await getRegister(context,search,page);
 const href=(targetPage:number)=>{
  const params=new URLSearchParams(period);
  params.set('register','1');
  if(search)params.set('search',search);
  if(targetPage)params.set('register_page',String(targetPage));
  return '/kpi/projekt?'+params;
 };
 return <section className="panel">
  <h2>NeXT-projektregistret</h2>
  <p>Här visas även projekt utan bokförda poster eller aktiv KPI-koppling. Bokförd intäkt från NeXT visas för vald period, separat från projektuppföljningens KPI-intäkt.</p>
  {report?.latest&&<p>Senaste projektimporten {time.format(new Date(report.latest.completed_at??report.latest.created_at))} · {report.latest.file_name} · {number.format(report.latest.row_count)} projekt.</p>}
  <form className={styles.filters} action="/kpi/projekt" method="get">
   {Array.from(period,([key,value])=><input type="hidden" key={key} name={key} value={value}/>)}
   <input type="hidden" name="register" value="1"/>
   <label>Sök i projektregistret<input name="search" defaultValue={search} maxLength={150} placeholder="Projektnummer, namn eller grupp"/></label>
   <button className="primary">Sök</button>
  </form>
  {!report?<p role="alert">Projektregistret kunde inte hämtas.</p>:<>
   <p>{number.format(report.matched)} projekt i urvalet.</p>
   <div className={styles.scroll}><table className={styles.table}>
    <thead><tr><th scope="col">Projekt</th><th scope="col">KST</th><th scope="col">Projektledare / grupp</th><th scope="col">Bokförd intäkt · NeXT</th><th scope="col">KPI-koppling</th></tr></thead>
    <tbody>{report.projects.map(p=><tr key={p.project_number}>
     <th scope="row">{p.kpi_project_id?<Link prefetch={false} href={projectReportHref(period,{project:p.kpi_project_id})}>{p.project_number} · {p.project_name}</Link>:<>{p.project_number} · {p.project_name}</>}</th>
     <td>{p.cost_center||(p.cost_center_name??p.source_center??'—')}</td>
     <td>{p.project_manager||'—'}<br/><small>{p.business_group??p.source_business_groups??'—'}</small></td>
     <td>{p.booked_amount===null?'—':money.format(p.booked_amount)}{p.booked_rows>0&&<small style={{display:'block'}}>{p.booked_rows} bokförda rader</small>}</td>
     <td>{p.kpi_project_id?'Kopplat':p.cost_center?'Projektidentitet saknas':'KST-klassificering saknas'}</td>
    </tr>)}</tbody>
   </table></div>
   <nav className={styles.pager} aria-label="Sidor i projektregistret">
    {page>0&&<Link prefetch={false} href={href(page-1)}>← Föregående</Link>}
    {report.matched>(page+1)*50&&<Link prefetch={false} href={href(page+1)}>Nästa →</Link>}
   </nav>
  </>}
 </section>;
}

export async function ProjectNextBookedRevenue({projectNumber,...context}:Context&{projectNumber:string}){
 const report=await getRegister(context,projectNumber,0,true);
 const p=report?.projects[0];
 if(!p?.booked_rows)return null;
 return <section className="panel">
  <h2>Bokförd intäkt i NeXT</h2>
  <strong>{p.booked_amount===null?'—':money.format(p.booked_amount)}</strong>
  <p>{p.booked_rows} bokförda rader för projekt {projectNumber} i valt datumurval. På KST 20 och 30 utgår KPI-intäkten från Workify.</p>
 </section>;
}
