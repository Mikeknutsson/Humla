import Link from 'next/link';
import {KpiDetailShell} from '@/app/_components/kpi-detail-shell';
import {reviewAccess} from '@/lib/hub/review-access';
import {nextResourceBatches,loadNextResourceFile} from '@/lib/kpi/next-resource-source';
import {readNextArticleFile} from '@/lib/kpi/next-article-file';
import {validTransportDate} from '@/lib/kpi/transport-leader';

export const dynamic='force-dynamic';
const base='/kpi/maskiner';
const imported=new Intl.DateTimeFormat('sv-SE',{dateStyle:'short',timeStyle:'short',timeZone:'Europe/Stockholm'});
const currency=new Intl.NumberFormat('sv-SE',{style:'currency',currency:'SEK',maximumFractionDigits:2});
const quantity=new Intl.NumberFormat('sv-SE',{maximumFractionDigits:3});
const money=(value:number|null)=>value===null?'–':currency.format(value);
const number=(value:number|null)=>value===null?'–':quantity.format(value);
const text=(value:unknown)=>typeof value==='string'?value.trim().slice(0,250):'';
type Metrics={rows:number;hours:number|null;value:number|null;value_per_hour:number|null};
type Machine=Metrics & {machine_id:string;name:string;codes:string[]};
type Job={project:string;work_order:string;project_name:string;order_name:string;rows:number;hours:number|null;value:number|null};
type Other={category:string;code:string;article:string;unit:string;rows:number;quantity:number|null;value:number|null};
type Report={
 machines:Machine[];
 months:(Metrics & {month_key:string})[];
 jobs:Job[];
 others:Other[];
 details:{sheet:string;source_row:number;performed_on:string|null;code:string;article:string;quantity:number|null;value:number|null}[];
};

export default async function MachineFollowup({searchParams}:{searchParams:Promise<Record<string,string|undefined>>}){
 const access=await reviewAccess();
 if(!access)return <main className="content"><h1>Du saknar åtkomst till maskinuppföljningen.</h1></main>;
 const raw=await searchParams;
 const selected=text(raw.batch);
 const machine=/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(text(raw.machine))?text(raw.machine):null;
 const drilling=Boolean(machine)&&typeof raw.project==='string'&&typeof raw.ao==='string';
 const project=drilling?text(raw.project):null,order=drilling?text(raw.ao):null;
 const requestedFrom=text(raw.from),requestedTo=text(raw.to);
 const from=validTransportDate(requestedFrom)?requestedFrom:null,to=validTransportDate(requestedTo)?requestedTo:null;
 const {data,error}=await nextResourceBatches(access);
 const batches=data??[];
 const batch=selected?batches.find(b=>b.id===selected):
  batches.find(b=>(!from||!b.period_end||b.period_end>=from)&&(!to||!b.period_start||b.period_start<=to))??batches[0];
 const viewQuery=new URLSearchParams({from:from??'',to:to??''});
 if(batch)viewQuery.set('batch',batch.id);
 if(machine)viewQuery.set('machine',machine);
 const href=(changes:Record<string,string|null>)=>{
  const params=new URLSearchParams(viewQuery);
  for(const [key,value] of Object.entries(changes)){
   if(value===null)params.delete(key);
   else params.set(key,value);
  }
  return base+'?'+params;
 };

 let report:Report|null=null;
 let problem='';
 if(error)problem='NeXT-importerna kunde inte hämtas.';
 else if((requestedFrom&&!from)||(requestedTo&&!to)||(from&&to&&from>to))problem='Kontrollera datumintervallet.';
 else if(selected&&!batch)problem='Den valda exporten är inte tillgänglig.';
 else if(batch){
  try{
   const parsed=readNextArticleFile(await loadNextResourceFile(access,batch),{includeMachines:true});
   if(!parsed.workshopColumns)problem='Exporten behöver innehålla Kontonr, Utförd datum och Utf intäkt.';
   else{
    const result=await access.db.rpc('hub_next_machine_followup',{
     t:access.tenantId,p_batch:batch.id,p_rows:parsed.machineRows,p_from:from,p_to:to,p_machine:machine,p_project:project,p_order:order,
    });
    if(result.error||!result.data)throw Error(result.error?.code??'Empty report');
    report=result.data as Report;
   }
  }catch(error){
   console.error('[machine-followup]',{batchId:batch.id,reason:error instanceof Error?error.message:'Unknown error'});
   problem='Maskinunderlaget kunde inte läsas. Försök igen eller välj en annan export.';
  }
 }
 const current=report?.machines.find(row=>row.machine_id===machine);
 const categories=[...new Set(report?.others.map(row=>row.category))];
 return <KpiDetailShell title="Maskinuppföljning" breadcrumb="Humla Dashboard / Entreprenad och maskinuthyrning / Maskiner" query="cost_center=10">
  <div className="content">
   <section className="panel">
    <div className="panel-head"><div><h2>Maskiner · NeXT Resursuppföljning</h2><p>Registrerad tid och upparbetat värde efter utförandedatum. Varje urval visar en sparad export.</p></div>
     <Link className="secondary" prefetch={false} href="/kpi?view=importhistorik&history_kind=next_articles">Importhistorik</Link></div>
    {batches.length>0&&<form action={base} className="period-form">
     {machine&&<input type="hidden" name="machine" value={machine}/>}
     <label>NeXT-export <select name="batch" defaultValue={batch?.id??''}>
      {!batch&&<option value="" disabled>Välj en export</option>}
      {batches.map(b=><option key={b.id} value={b.id}>{b.file_name??'Resursuppföljning'}{b.completed_at?' · '+imported.format(new Date(b.completed_at)):''}</option>)}
     </select></label>
     <label>Utfört från <input type="date" name="from" defaultValue={from??''}/></label>
     <label>Utfört till <input type="date" name="to" defaultValue={to??''}/></label>
     <button type="submit">Visa</button>
    </form>}
    {batch?.period_start&&batch.period_end&&<p>Datum i exporten {batch.period_start} – {batch.period_end}.</p>}
   </section>
   {problem?<section className="panel" role="alert">{problem}</section>:!report?<section className="panel"><p>Importera Resursuppföljning från NeXT för att börja följa upp maskiner.</p><Link href="/kpi?view=import#next-artikelimport">Öppna Dataimport</Link></section>:<>
    {machine?<section className="panel">
     <p><Link prefetch={false} href={href({machine:null})}>← Alla maskiner</Link></p>
     <h2>{current?.name??'Vald maskin'}</h2>
     {current?<div className="metrics-grid">
      <article className="metric-card"><span>Registrerad tid</span><strong>{number(current.hours)} tim</strong></article>
      <article className="metric-card"><span>Upparbetat värde</span><strong>{money(current.value)}</strong></article>
      <article className="metric-card"><span>Värde per timme</span><strong>{money(current.value_per_hour)}</strong></article>
     </div>:<p>Inget underlag för maskinen i urvalet.</p>}
    </section>:<section className="panel">
     <h2>Egna maskiner</h2><p>Bekräftade artikelkopplingar i Humla Hub. Välj en maskin för att se månader, projekt och arbetsorder.</p>
     {report.machines.length?<div className="table-wrap"><table className="data-table">
      <thead><tr><th scope="col">Maskin</th><th scope="col">NeXT-artikel</th><th scope="col">Registrerad tid</th><th scope="col">Upparbetat värde</th><th scope="col">Värde/tim</th></tr></thead>
      <tbody>{report.machines.map(m=><tr key={m.machine_id}><th scope="row"><Link prefetch={false} href={href({machine:m.machine_id})}>{m.name} →</Link></th><td>{m.codes.join(', ')}</td><td>{number(m.hours)}</td><td>{money(m.value)}</td><td>{money(m.value_per_hour)}</td></tr>)}</tbody>
     </table></div>:<p>Inga bekräftade egna maskiner har resursrader i urvalet.</p>}
    </section>}
    {machine&&report.months.length>0&&<section className="panel"><h2>Per månad</h2><div className="table-wrap"><table className="data-table">
     <thead><tr><th scope="col">Månad</th><th scope="col">Registrerad tid</th><th scope="col">Upparbetat värde</th><th scope="col">Värde/tim</th></tr></thead>
     <tbody>{report.months.map(m=><tr key={m.month_key}><th scope="row">{m.month_key}</th><td>{number(m.hours)}</td><td>{money(m.value)}</td><td>{money(m.value_per_hour)}</td></tr>)}</tbody>
    </table></div></section>}
    {machine&&!drilling&&report.jobs.length>0&&<section className="panel"><h2>Projekt och arbetsorder</h2><div className="table-wrap"><table className="data-table">
     <thead><tr><th scope="col">Projekt</th><th scope="col">Arbetsorder</th><th scope="col">Registrerad tid</th><th scope="col">Upparbetat värde</th></tr></thead>
     <tbody>{report.jobs.map(j=><tr key={JSON.stringify([j.project,j.work_order])}><th scope="row">{j.project} {j.project_name}</th><td><Link prefetch={false} href={href({project:j.project,ao:j.work_order})}>AO {j.work_order||'saknas'} {j.order_name} →</Link></td><td>{number(j.hours)}</td><td>{money(j.value)}</td></tr>)}</tbody>
    </table></div></section>}
    {drilling&&<section className="panel"><p><Link prefetch={false} href={href({})}>← Till projekt och arbetsorder</Link></p><h2>Projekt {project||'saknas'} · AO {order||'saknas'}</h2>
     {report.details.length?<div className="table-wrap"><table className="data-table">
      <thead><tr><th scope="col">Utförd</th><th scope="col">Artikel</th><th scope="col">Registrerad tid</th><th scope="col">Upparbetat värde</th><th scope="col">Källrad</th></tr></thead>
      <tbody>{report.details.map(r=><tr key={r.sheet+':'+r.source_row}><td>{r.performed_on??'–'}</td><th scope="row">{r.code} {r.article}</th><td>{number(r.quantity)}</td><td>{money(r.value)}</td><td>{r.sheet} · {r.source_row}</td></tr>)}</tbody>
     </table></div>:<p>Inga resursrader i urvalet.</p>}
    </section>}
    {!machine&&categories.map(category=><details className="panel" key={category}><summary>{category}</summary><div className="table-wrap"><table className="data-table">
     <thead><tr><th scope="col">Artikel</th><th scope="col">Mängd</th><th scope="col">Upparbetat värde</th><th scope="col">Källrader</th></tr></thead>
     <tbody>{report.others.filter(a=>a.category===category).map(a=><tr key={JSON.stringify([a.code,a.article,a.unit])}><th scope="row">{a.code} {a.article}</th><td>{number(a.quantity)} {a.unit}</td><td>{money(a.value)}</td><td>{a.rows}</td></tr>)}</tbody>
    </table></div></details>)}
   </>}
  </div>
 </KpiDetailShell>;
}
