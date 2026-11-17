import {createHash} from 'node:crypto';
import Link from 'next/link';
import {KpiDetailShell} from '@/app/_components/kpi-detail-shell';
import {reviewAccess, reviewPage} from '@/lib/hub/review-access';
import {readNextArticleFile} from '@/lib/kpi/next-article-file';

export const dynamic='force-dynamic';
const base='/kpi/verkstad/internjobb';
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
type Query={batch?:string;tab?:string;from?:string;to?:string;center?:string;project?:string;ao?:string;page?:string};
const readQuery=(value:unknown,max=250)=>typeof value==='string'?value.trim().slice(0,max):'';
function dateInput(value:string){
  if(!/^\d{4}-\d{2}-\d{2}$/.test(value))return null;
  const n=Date.parse(value);
  return Number.isFinite(n)&&new Date(n).toISOString().slice(0,10)===value?value:null;
}

export default async function WorkshopResourcePage({searchParams}:{searchParams:Promise<Query>}){
  const access=await reviewAccess();
  if(!access)return <main className="content"><h1>Du saknar åtkomst till verkstadens uppföljning.</h1></main>;
  const q=await searchParams;
  const selected=readQuery(q.batch), review=q.tab==='review';
  const tab=review?'review':'work';
  const fromText=readQuery(q.from),toText=readQuery(q.to),from=dateInput(fromText),to=dateInput(toText);
  const invalidDates=Boolean((fromText&&!from)||(toText&&!to)||(from&&to&&from>to));
  const center=readQuery(q.center);
  const drilling=typeof q.project==='string'&&typeof q.ao==='string';
  const project=drilling?readQuery(q.project):null,order=drilling?readQuery(q.ao):null;
  const page=Math.min(1000,reviewPage(typeof q.page==='string'?q.page:undefined));
  const {db,tenantId}=access;
  const batchResponse=await db.from('kpi_import_batches')
    .select('id,file_name,file_hash,storage_path,completed_at,period_start,period_end')
    .eq('tenant_id',tenantId).eq('data_kind','next_articles').eq('status','completed')
    .order('completed_at',{ascending:false,nullsFirst:false}).order('id',{ascending:false}).limit(50);
  const batches=batchResponse.data??[];
  const batch=selected?batches.find(entry=>entry.id===selected):batches[0];

  const params:Record<string,string>={tab};
  if(batch)params.batch=batch.id;
  if(from)params.from=from;
  if(to)params.to=to;
  if(center)params.center=center;
  if(project!==null&&order!==null){params.project=project;params.ao=order;}
  const href=(changes:Record<string,string|null>)=>{
    const search=new URLSearchParams(params);
    for(const [key,value] of Object.entries(changes)){
      if(value===null)search.delete(key);
      else search.set(key,value);
    }
    return base+'?'+search;
  };

  let report:Report|null=null;
  let problem='';
  if(batchResponse.error)problem='Importerna kunde inte hämtas.';
  else if(invalidDates)problem='Välj ett giltigt datumintervall.';
  else if(selected&&!batch)problem='Den valda importen är inte tillgänglig. Välj en fil i listan.';
  else if(batch) {
    try{
      if(!batch.storage_path?.startsWith(`${tenantId}/${batch.id}/`)||!batch.file_hash)throw Error('Batch source metadata missing');
      const {data,error}=await db.storage.from('kpi-imports').download(batch.storage_path);
      if(error||!data)throw Error('Batch download failed');
      const bytes=new Uint8Array(await data.arrayBuffer());
      if(bytes.length>4_000_000||createHash('sha256').update(bytes).digest('hex')!==batch.file_hash)throw Error('Batch source verification failed');
      const parsed=readNextArticleFile(bytes,{includeWorkshop:true});
      if(!parsed.workshopColumns)problem='Filen saknar de kolumner som behövs för internjobben. Välj en NeXT-export med Kontonr, Utförd datum och Utf intäkt.';
      else {
        const {data:result,error:reportError}=await db.rpc('hub_workshop_resource_report',{
          t:tenantId,p_batch:batch.id,p_rows:parsed.workshopRows,p_from:from,p_to:to,p_center:center||null,
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
  return <KpiDetailShell query="" title="Verkstad · Internjobb" breadcrumb="Humla Dashboard / Verkstad / Internjobb"
    extraNavigation={<Link href="/kpi/verkstad" prefetch={false}>Tillbaka till verkstaden</Link>}>
    <div className="content">
      <section className="panel">
        <div className="panel-head"><div><h2>NeXT · Konto 4630</h2><p>Verkstadens registrerade internjobb från Resursuppföljning. Varje rapport visar en sparad export, så periodöverlappar summeras inte.</p></div>
          <Link href={imports} className="secondary" prefetch={false}>Importhistorik</Link>
        </div>
        {batches.length>0&&<form action={base} method="get" className="period-form">
          <input type="hidden" name="tab" value={tab}/>
          <label>NeXT-export <select name="batch" defaultValue={batch?.id??''}>
            {!batch&&<option value="" disabled>Välj en import</option>}
            {batches.map(b=><option key={b.id} value={b.id}>{b.file_name??'Resursuppföljning'}{b.completed_at?' · '+imported.format(new Date(b.completed_at)):''}</option>)}
          </select></label>
          <label>Utfört från <input name="from" type="date" defaultValue={from??''}/></label>
          <label>Utfört till <input name="to" type="date" defaultValue={to??''}/></label>
          <button type="submit">Visa</button>
        </form>}
        {batch?.period_start&&batch.period_end&&<p>Datum i exporterad fil {batch.period_start} – {batch.period_end}.</p>}
      </section>
      <nav className="panel" aria-label="Internjobb">
        <Link prefetch={false} className={review?'secondary':'primary'} aria-current={!review?'page':undefined} href={href({tab:'work'})}>Utfört arbete</Link>{' '}
        <Link prefetch={false} className={review?'primary':'secondary'} aria-current={review?'page':undefined} href={href({tab:'review'})}>Att stämma av</Link>
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
          {center&&<p>Visar {center} · <Link prefetch={false} href={href({center:null,project:null,ao:null})}>Visa alla kostnadsställen</Link></p>}
          {report.centers.length>0?<div className="table-wrap"><table className="data-table">
            <thead><tr><th>Kostnadsställe</th><th>Internvärde</th><th>Kostnad</th><th>Timmar</th><th>Övriga artiklar</th><th>Ej fakturamarkerat</th></tr></thead>
            <tbody>{report.centers.map(c=><tr key={c.center}><th scope="row"><Link prefetch={false} href={href({center:c.center,project:null,ao:null})}>{c.center}</Link></th><td>{money(c.value)}</td><td>{money(c.cost)}</td><td>{number(c.hours)}</td><td>{money(c.material)}</td><td>{money(c.pending)}</td></tr>)}</tbody>
          </table></div>:<p>Inga resursrader på konto 4630 i urvalet.</p>}
        </section>
        {!review&&!drilling&&report.months.length>0&&<section className="panel"><h2>Utfört per månad</h2><div className="table-wrap"><table className="data-table">
          <thead><tr><th>Månad</th><th>Internvärde</th><th>Kostnad</th><th>Timmar</th><th>Övriga artiklar</th><th>Ej fakturamarkerat</th></tr></thead>
          <tbody>{report.months.map(m=><tr key={m.month_key}><th scope="row">{m.month_key}</th><td>{money(m.value)}</td><td>{money(m.cost)}</td><td>{number(m.hours)}</td><td>{money(m.material)}</td><td>{money(m.pending)}</td></tr>)}</tbody>
        </table></div>{totals.undated>0&&<p>{totals.undated} rader utan utförandedatum ingår i totalsummorna.</p>}</section>}
        <section className="panel">
          <h2>{drilling?`Projekt ${project||'saknas'} · AO ${order||'saknas'}`:review?'Arbetsorder att stämma av':'Arbetsorder och artikelrader'}</h2>
          {review&&<p>Visar debiterbara rader utan fakturamarkering samt avvikelser i värde, kostnad eller fakturastatus. Fakturamarkeringen gäller vid exporttillfället.</p>}
          {drilling&&<p><Link prefetch={false} href={href({project:null,ao:null})}>Till arbetsorderlistan</Link></p>}
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
              <th scope="row"><Link prefetch={false} href={href({center:o.center,project:o.project,ao:o.work_order})}>{o.project} {o.project_name} · AO {o.work_order||'saknas'}</Link>{o.order_name&&<small style={{display:'block'}}>{o.order_name}</small>}</th>
              <td>{o.center}</td><td>{money(o.value)}</td><td>{money(o.cost)}</td><td>{number(o.hours)}</td><td>{money(o.material)}</td><td>{money(o.pending)}</td>
              {review&&<td>{o.deviations}</td>}
            </tr>)}</tbody>
          </table></div>:<p>{review?'Inga rader att stämma av i urvalet.':'Inga arbetsorder i urvalet.'}</p>}
          <nav aria-label="Rapportsidor">
            {page>0&&<Link prefetch={false} className="secondary" href={href({page:String(page-1)})}>Föregående</Link>}{' '}
            {hasMore&&page<1000&&<Link prefetch={false} className="secondary" href={href({page:String(page+1)})}>Nästa</Link>}
          </nav>
        </section>
      </>}
    </div>
  </KpiDetailShell>;
}
