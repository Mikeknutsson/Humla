import Link from 'next/link';
import {reviewPage} from '@/lib/hub/review-access';
import {nextResourceBatches,loadNextResourceFile,type ResourceAccess} from '@/lib/kpi/next-resource-source';
import {readNextArticleFile} from '@/lib/kpi/next-article-file';

const base='/kpi/verkstad';
const imports='/kpi?view=importhistorik&history_kind=next_articles';
const currency=new Intl.NumberFormat('sv-SE',{style:'currency',currency:'SEK'});
const quantity=new Intl.NumberFormat('sv-SE',{maximumFractionDigits:3});
const imported=new Intl.DateTimeFormat('sv-SE',{dateStyle:'short',timeStyle:'short',timeZone:'Europe/Stockholm'});
const money=(n:number|null)=>n===null?'–':currency.format(n);
const number=(n:number|null)=>n===null?'–':quantity.format(n);
type Financials={value:number|null;cost:number|null;hours:number|null;material:number|null;pending:number|null};
type Order=Financials & {center:string;project:string;project_name:string;work_order:string;order_name:string;rows:number;deviations:number};
type Detail={
  center_label:string;sheet:string;source_row:number;performed_on:string|null;code:string;article:string;unit:string;
  quantity:number|null;value:number|null;actual_cost:number|null;invoice_number:string;
  invoiced:boolean|null;billable:boolean|null;deviation:string|null;
};
type Report={
  totals:Financials & {rows:number;orders:number;pending_rows:number;deviations:number;undated:number};
  centers:(Financials & {center:string;rows:number})[];
  months:(Financials & {month_key:string})[];
  orders:Order[];
  details:Detail[];
};
const readQuery=(value:unknown,max=250)=>typeof value==='string'?value.trim().slice(0,max):'';

export async function WorkshopInternalJobs({access,q,from,to,months,periodQuery}:{access:ResourceAccess;q:Record<string,string|undefined>;from:string;to:string;months:number[];periodQuery:string}){
  const selected=readQuery(q.intern_batch), review=q.intern_tab==='review';
  const tab=review?'review':'work';
  const center=readQuery(q.intern_center);
  const drilling=typeof q.intern_project==='string'&&typeof q.intern_ao==='string';
  const project=drilling?readQuery(q.intern_project):null,order=drilling?readQuery(q.intern_ao):null;
  const page=Math.min(1000,reviewPage(typeof q.intern_page==='string'?q.intern_page:undefined));
  const {db,tenantId}=access;
  const batchResponse=await nextResourceBatches(access);
  const batches=batchResponse.data??[];
  const batch=selected?batches.find(entry=>entry.id===selected):
    batches.find(entry=>entry.period_start&&entry.period_end&&entry.period_start<=to&&entry.period_end>=from)??batches[0];

  const params:Record<string,string>={intern_tab:tab};
  if(batch)params.intern_batch=batch.id;
  if(center)params.intern_center=center;
  if(project!==null&&order!==null){params.intern_project=project;params.intern_ao=order;}
  const href=(changes:Record<string,string|null>)=>{
    const search=new URLSearchParams(periodQuery);
    for(const [key,value] of Object.entries(params))search.set(key,value);
    for(const [key,value] of Object.entries(changes)){
      if(value===null)search.delete(key);
      else search.set(key,value);
    }
    return base+'?'+search+'#internjobb';
  };

  let report:Report|null=null;
  let problem='';
  if(batchResponse.error)problem='Importerna kunde inte hämtas.';
  else if(selected&&!batch)problem='Den valda importen är inte tillgänglig. Välj en fil i listan.';
  else if(batch) {
    try{
      const bytes=await loadNextResourceFile(access,batch);
      const parsed=readNextArticleFile(bytes,{includeWorkshop:true});
      if(!parsed.workshopColumns)problem='Filen saknar de kolumner som behövs för internjobben. Välj en NeXT-export med Kontonr, Utförd datum och Utf intäkt.';
      else {
        const {data:result,error:reportError}=await db.rpc('hub_workshop_resource_report',{
          t:tenantId,p_batch:batch.id,p_rows:months.length?parsed.workshopRows.filter(row=>row.performed_on&&months.includes(Number(row.performed_on.slice(5,7)))):parsed.workshopRows,p_from:from,p_to:to,p_center:center||null,
          p_review:review,p_project:project,p_order:order,p_page:page,
        });
        if(reportError||!result)throw Error(reportError?.code??'Report returned no result');
        report=result as Report;
      }
    }catch(error){
      console.error('[workshop-resources]',{batchId:batch.id,reason:error instanceof Error?error.message:'Unknown error'});
      problem='Det sparade NeXT-underlaget kunde inte läsas. Försök igen eller välj en annan import.';
    }
  }

  const totals=report?.totals;
  const hasMore=Boolean(report&&(drilling?report.details:report.orders).length>50);
  return <section id="internjobb" aria-labelledby="internjobb-heading">
      <section className="panel">
        <div className="panel-head"><div><h2 id="internjobb-heading">Internjobb · NeXT</h2><p>Konto 4630 från NeXT Resursuppföljning. Varje rapport visar en sparad export, så periodöverlappar summeras inte.</p></div>
          <Link href={imports} className="secondary" prefetch={false}>Importhistorik</Link>
        </div>
        {batches.length>0&&<form action={base+'#internjobb'} method="get" className="period-form">
          <input type="hidden" name="intern_tab" value={tab}/>
          {[...new URLSearchParams(periodQuery)].map(([name,value])=><input key={name} type="hidden" name={name} value={value}/>)}
          <label>NeXT-export <select name="intern_batch" defaultValue={batch?.id??''}>
            {!batch&&<option value="" disabled>Välj en import</option>}
            {batches.map(b=><option key={b.id} value={b.id}>{b.file_name??'Resursuppföljning'}{b.completed_at?' · '+imported.format(new Date(b.completed_at)):''}</option>)}
          </select></label>
          <button type="submit">Visa</button>
        </form>}
        {batch?.period_start&&batch.period_end&&<p>Datum i exporterad fil {batch.period_start} – {batch.period_end}.</p>}
      </section>
      <nav className="panel" aria-label="Internjobb">
        <Link prefetch={false} className={review?'secondary':'primary'} aria-current={!review?'page':undefined} href={href({intern_tab:'work'})}>Utfört arbete</Link>{' '}
        <Link prefetch={false} className={review?'primary':'secondary'} aria-current={review?'page':undefined} href={href({intern_tab:'review'})}>Att stämma av</Link>
      </nav>
      {problem?<section className="panel" role="alert">{problem}</section>:!report||!totals?<section className="panel"><p>Importera en Resursuppföljning från NeXT för att börja följa upp internjobben.</p><Link href="/kpi?view=import#next-artikelimport">Öppna Dataimport</Link></section>:<>
        <section className="metrics-grid" aria-label="Internjobb i urvalet">
          <article className="metric-card"><span>Upparbetat internvärde</span><strong>{money(totals.value)}</strong><small>{totals.rows} resursrader · {totals.orders} arbetsorder</small></article>
          <article className="metric-card"><span>Registrerad kostnad</span><strong>{money(totals.cost)}</strong><small>Utf kostnad enligt NeXT</small></article>
          <article className="metric-card"><span>Övriga artiklar</span><strong>{money(totals.material)}</strong><small>Del av internvärdet, exklusive timartiklar</small></article>
          <article className="metric-card"><span>Registrerad tid</span><strong>{totals.hours===null?'–':number(totals.hours)+' tim'}</strong><small>Artiklar med enheten tim</small></article>
          <article className="metric-card"><span>Debiterbart, ej fakturamarkerat</span><strong>{totals.pending_rows===0?money(0):money(totals.pending)}</strong><small>{totals.pending_rows} rader enligt exporten</small></article>
        </section>
        <section className="panel">
          <h2>Kostnadsställen på projekten</h2>
          <p>Välj ett kostnadsställe för att se dess arbetsorder. Arbete inom Verkstad redovisas här som utfört arbete. Se bokförda belopp i Humlas <Link prefetch={false} href="/kpi?view=internal">internöverföringar</Link>.</p>
          {center&&<p>Visar {center} · <Link prefetch={false} href={href({intern_center:null,intern_project:null,intern_ao:null})}>Visa alla kostnadsställen</Link></p>}
          {report.centers.length>0?<div className="table-wrap"><table className="data-table">
            <thead><tr><th>Kostnadsställe</th><th>Internvärde</th><th>Kostnad</th><th>Timmar</th><th>Övriga artiklar</th><th>Ej fakturamarkerat</th></tr></thead>
            <tbody>{report.centers.map(c=><tr key={c.center}><th scope="row"><Link prefetch={false} href={href({intern_center:c.center,intern_project:null,intern_ao:null})}>{c.center}</Link></th><td>{money(c.value)}</td><td>{money(c.cost)}</td><td>{number(c.hours)}</td><td>{money(c.material)}</td><td>{money(c.pending)}</td></tr>)}</tbody>
          </table></div>:<p>Inga resursrader på konto 4630 i urvalet.</p>}
        </section>
        {!review&&!drilling&&report.months.length>0&&<section className="panel"><h2>Utfört per månad</h2><div className="table-wrap"><table className="data-table">
          <thead><tr><th>Månad</th><th>Internvärde</th><th>Kostnad</th><th>Timmar</th><th>Övriga artiklar</th><th>Ej fakturamarkerat</th></tr></thead>
          <tbody>{report.months.map(m=><tr key={m.month_key}><th scope="row">{m.month_key}</th><td>{money(m.value)}</td><td>{money(m.cost)}</td><td>{number(m.hours)}</td><td>{money(m.material)}</td><td>{money(m.pending)}</td></tr>)}</tbody>
        </table></div>{totals.undated>0&&<p>{totals.undated} rader utan utförandedatum ingår i totalsummorna.</p>}</section>}
        <section className="panel">
          <h2>{drilling?`Projekt ${project||'saknas'} · AO ${order||'saknas'}`:review?'Arbetsorder att stämma av':'Arbetsorder och artikelrader'}</h2>
          {review&&<p>Visar debiterbara rader utan fakturamarkering samt avvikelser i värde, kostnad eller fakturastatus. Fakturamarkeringen gäller vid exporttillfället.</p>}
          {drilling&&<p><Link prefetch={false} href={href({intern_project:null,intern_ao:null})}>Till arbetsorderlistan</Link></p>}
          {drilling?report.details.length>0?<div className="table-wrap"><table className="data-table">
            <thead><tr><th>Utfört</th><th>Artikel</th><th>Antal</th><th>Internvärde</th><th>Kostnad</th><th>Fakturastatus</th><th>Källrad</th></tr></thead>
            <tbody>{report.details.slice(0,50).map(r=><tr key={r.sheet+':'+r.source_row}>
              <td>{r.performed_on??'–'}</td><td>{r.code} {r.article}</td><td>{number(r.quantity)} {r.unit}</td><td>{money(r.value)}</td><td>{money(r.actual_cost)}</td>
              <td>{r.invoiced===true?`Fakturamarkerad${r.invoice_number?' · '+r.invoice_number:''}`:r.billable===false?'Ej debiterbar':r.invoiced===false?'Ej fakturamarkerad':'Okänd'}{r.deviation&&<small style={{display:'block'}}>{r.deviation}</small>}</td>
              <td>{r.sheet} · {r.source_row}</td>
            </tr>)}</tbody>
          </table></div>:<p>Inga artikelrader i urvalet.</p>:report.orders.length>0?<div className="table-wrap"><table className="data-table">
            <thead><tr><th>Projekt och arbetsorder</th><th>Kostnadsställe</th><th>Internvärde</th><th>Kostnad</th><th>Timmar</th><th>Övriga artiklar</th><th>Ej fakturamarkerat</th>{review&&<th>Avvikelser</th>}</tr></thead>
            <tbody>{report.orders.slice(0,50).map(o=><tr key={JSON.stringify([o.center,o.project,o.work_order])}>
              <th scope="row"><Link prefetch={false} href={href({intern_center:o.center,intern_project:o.project,intern_ao:o.work_order})}>{o.project} {o.project_name} · AO {o.work_order||'saknas'}</Link>{o.order_name&&<small style={{display:'block'}}>{o.order_name}</small>}</th>
              <td>{o.center}</td><td>{money(o.value)}</td><td>{money(o.cost)}</td><td>{number(o.hours)}</td><td>{money(o.material)}</td><td>{money(o.pending)}</td>
              {review&&<td>{o.deviations}</td>}
            </tr>)}</tbody>
          </table></div>:<p>{review?'Inga rader att stämma av i urvalet.':'Inga arbetsorder i urvalet.'}</p>}
          <nav aria-label="Rapportsidor">
            {page>0&&<Link prefetch={false} className="secondary" href={href({intern_page:String(page-1)})}>Föregående</Link>}{' '}
            {hasMore&&page<1000&&<Link prefetch={false} className="secondary" href={href({intern_page:String(page+1)})}>Nästa</Link>}
          </nav>
        </section>
      </>}
  </section>;
}
