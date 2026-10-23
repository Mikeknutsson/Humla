import Link from 'next/link';
import { reviewAccess, reviewPage } from '@/lib/hub/review-access';
export const dynamic = 'force-dynamic';
const states: Record<string,string> = {
 all:'Alla rader', candidate_include:'Unika kandidater med godkänd orderstatus', candidate_duplicate:'Dubblettkandidater',
 excluded_status:'Annan orderstatus', ignored_zero:'Nollrader', invalid:'Ogiltigt datum eller belopp',
 review_required:'Övrig granskning', excluded_withdrawn:'Återtagen import', excluded_accounted_elsewhere:'Bokförd i NEXT'
};
type Review = {
 mode:string;approved:boolean;totalRows:number;selectedRows:number;activeGeneration:string|null;
 totals:{currency:string;review_state:string;rows:number;source_amount:string;current_prepared_amount:string;missing_from_prepared_rows:number;allocation_review_rows:number}[];
 controls:{currency:string;raw_amount:string;current_prepared_amount:string;partition_difference:string}[];
 months:{month:string;currency:string;current_amount:string;retained_current_amount:string;duplicate_candidate_amount:string;status_excluded_amount:string;other_held_amount:string;missing_candidate_rows:number}[];
 items:{row_id:string;canonical_row_id:string;batch_id:string;file_name:string;row_number:number;occurred_on:string;order_number:string;amount:string;currency:string;prepared_amount:string;original_status:string;effective_status:string;review_state:string;allocation_review:boolean;source_data:Record<string,unknown>;validation_errors:unknown}[];
};
const number = new Intl.NumberFormat('sv-SE',{minimumFractionDigits:2,maximumFractionDigits:2});
const money = (value:string,currency:string) => `${number.format(Number(value))} ${currency}`;
export default async function RevenueReview({searchParams}:{searchParams:Promise<{page?:string;state?:string}>}) {
 const access=await reviewAccess();
 if(!access)return <section className="card"><h1>Åtkomst saknas</h1><p>En entydig aktiv arbetsyta med KPI-läsbehörighet krävs.</p></section>;
 const query=await searchParams,page=reviewPage(query.page),state=Object.hasOwn(states,query.state??'')?query.state!:'all';
 const {data,error}=await access.db.rpc('hub_workify_review_v1',{p_tenant_id:access.tenantId,p_page:page,p_state:state});
 if(error||!data)return <section className="card"><h1>Intäktskontroll</h1><p>Jämförelsen kunde inte hämtas. Inga ekonomiska data har ändrats.</p></section>;
 const report=data as Review;
 return <>
  <header className="topbar"><div><span className="eyebrow">HUMLA HUB · {report.mode==='active'?'GODKÄND AVSTÄMNING':'AVSTÄMNINGSFÖRSLAG'}</span><h1>Workify – intäktskontroll</h1>
   <p>Reported, ReadyForInvoicing och Invoiced ingår i {report.mode==='active'?'KPI':'förslaget'}. Statusändringar skapar inte en ny radidentitet. Hela importhistoriken jämförs innan sidurvalet görs.</p></div></header>
  <section className="card"><h2>{report.totalRows} ursprungsrader</h2>
   <p>{report.mode==='active'?'Den godkända avstämningen är införd i KPI. Dubblettbesluten och statusobservationerna är spårbara till originalraderna.':report.approved?'Avstämningen är godkänd, men den nya KPI-generationen har ännu inte passerat verifieringen. Den tidigare KPI-versionen visas tills kontrollerna är godkända.':'Förslaget påverkar ännu inte KPI. Identiskt innehåll och antal förekomster ger dubblettkandidater som behöver styrkas mot källan.'} Rader som endast saknar artikel- eller fordonsmappning behålls i avstämningsunderlaget och granskas separat för fördelning.</p>
   {!report.activeGeneration && <p>Ingen aktiv KPI-generation finns att jämföra med.</p>}
   <table><thead><tr><th>Kontroll</th><th>Rader</th><th>Råbelopp</th><th>Belopp i dagens KPI</th><th>Saknar KPI-rad</th><th>Mappning behöver granskas</th></tr></thead>
    <tbody>{report.totals.map(t=><tr key={t.currency+t.review_state}><td><Link href={`?state=${t.review_state}`}>{states[t.review_state]??t.review_state}</Link></td><td>{t.rows}</td><td>{money(t.source_amount,t.currency)}</td><td>{money(t.current_prepared_amount,t.currency)}</td><td>{t.missing_from_prepared_rows}</td><td>{t.allocation_review_rows}</td></tr>)}</tbody></table>
   <p>Belopp i dagens KPI avser endast fakta som kan spåras till dessa Workify-orderrader. Uppdelade material- och transportdelar summeras tillsammans.</p>
   {report.controls.map(c=><p key={c.currency}>Kontrolldifferens vid uppdelning av befintliga KPI-belopp: <strong>{money(c.partition_difference,c.currency)}</strong>. {report.mode==='active'?'Den godkända Workify-avstämningen gäller intäkter. NEXT-kostnadernas granskning fortsätter.':'Detta är inte ett färdigt nytt KPI-resultat.'}</p>)}
  </section>
  <section className="section"><h2>Påverkan per månad – befintliga KPI-belopp</h2>
   <table><thead><tr><th>Månad</th><th>Idag</th><th>Kvar enligt förslaget</th><th>Dubblettkandidater</th><th>Annan status</th><th>Övrigt</th><th>Unika kandidater utan KPI-rad</th></tr></thead><tbody>
    {report.months.map(m=><tr key={m.month+m.currency}><td>{m.month?.slice(0,7)??'Datum saknas'}</td><td>{money(m.current_amount,m.currency)}</td><td>{money(m.retained_current_amount,m.currency)}</td><td>{money(m.duplicate_candidate_amount,m.currency)}</td><td>{money(m.status_excluded_amount,m.currency)}</td><td>{money(m.other_held_amount,m.currency)}</td><td>{m.missing_candidate_rows}</td></tr>)}
   </tbody></table><p>Kandidater utan KPI-rad måste räknas genom Hub-motorn innan ett nytt totalresultat kan godkännas. Råbelopp läggs inte direkt ovanpå omräknade KPI-belopp.</p>
  </section>
  <section className="section"><h2>{states[state]} – {report.selectedRows} rader</h2><p>Sida {page+1}. <Link href="?state=all">Visa alla kontrollgrupper</Link></p>
   <table><thead><tr><th>Order / datum</th><th>Status i original → senaste i förslaget</th><th>Råbelopp / dagens KPI</th><th>Kontroll och original</th></tr></thead><tbody>
    {report.items.map(r=><tr key={r.row_id}><td>{r.order_number}<br/>{r.occurred_on}</td><td>{r.original_status} → {r.effective_status}</td><td>{money(r.amount,r.currency)}<br/>{money(r.prepared_amount,r.currency)}</td><td>{states[r.review_state]}{r.allocation_review&&<p>Mappning/validering behöver granskas.</p>}
     <details><summary>Visa ursprungsrad</summary><p>{r.file_name} · rad {r.row_number}<br/>Rad-ID: {r.row_id}<br/>Föreslagen kanonisk rad: {r.canonical_row_id}</p><pre>{JSON.stringify(r.source_data,null,2)}</pre><p>{JSON.stringify(r.validation_errors)}</p></details></td></tr>)}
   </tbody></table>
   <nav aria-label="Sidor">{page>0&&<Link href={`?state=${state}&page=${page-1}`}>Föregående sida</Link>} {' '}{(page+1)*100<report.selectedRows&&<Link href={`?state=${state}&page=${page+1}`}>Nästa sida</Link>}</nav>
   <p><Link href="/kostnadskontroll">Kostnadskontroll</Link> · <Link href="/fordonshistorik">Fordonshistorik</Link></p>
  </section>
 </>;
}
