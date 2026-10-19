'use client';
import {useEffect,useState} from 'react';
import dynamic from 'next/dynamic';
import type {InternalCenterSummary,InternalSummaryRow} from '@/lib/kpi/internal-center-summary';
import type {InternalRow} from '@/lib/kpi/internal-transfers';
import {InternalMaterialRefunds} from './internal-material-refunds';
const PurchaseEvidence=dynamic(()=>import('./internal-purchase-evidence').then(m=>m.InternalPurchaseEvidence),{loading:()=> <p>Laddar inköpsunderlag…</p>});
const money=new Intl.NumberFormat('sv-SE',{style:'currency',currency:'SEK'});
const statusLabel={new:'Nytt underlag',review:'Behöver granskas',changed:'Ändrat efter export',exported:'Exporterat',posted:'Omfört'};
function EvidenceRows({rows,conflict=false}:{rows:Array<InternalRow&Partial<InternalSummaryRow>>;conflict?:boolean}){
 const [page,setPage]=useState(0);
 return <><div className="table-wrap"><table><thead><tr><th>Datum</th><th>Order</th><th>Littra</th><th>Kostnads-KST</th><th>Intäkts-KST</th><th>Belopp</th><th>Rapportgrund</th><th>Exportstatus</th><th>Anmärkning</th></tr></thead><tbody>{rows.slice(page*100,(page+1)*100).map(r=><tr key={r.row_id}><td>{r.occurred_on}</td><td>{r.order}</td><td>{r.littra||'—'}</td><td>{r.receiver_center||'Saknas'}</td><td>{r.source_center||'Saknas'}</td><td>{r.amount===null?'Belopp saknas':money.format(r.amount)}</td><td>{conflict?'Motstridigt':r.report_basis==='confirmed'?'Bekräftat':'Preliminärt'}{(r.report_copies??1)>1&&<small>{r.report_copies} importkopior · räknas en gång</small>}</td><td>{statusLabel[r.status]}</td><td>{r.review_reason||'—'}</td></tr>)}</tbody></table></div><div className="actions"><button disabled={page===0} onClick={()=>setPage(n=>n-1)}>Föregående</button><span>Sida {page+1} / {Math.max(1,Math.ceil(rows.length/100))}</span><button disabled={(page+1)*100>=rows.length} onClick={()=>setPage(n=>n+1)}>Nästa</button></div></>;
}
export function InternalTransfers({query}:{query:string;canManage:boolean}){
 const [loaded,setLoaded]=useState<{query:string;report:InternalCenterSummary}|null>(null),[issue,setIssue]=useState<{query:string;message:string}|null>(null),[busy,setBusy]=useState(false),[refresh,setRefresh]=useState(0),[expanded,setExpanded]=useState<string|null>(null);
 const [purchaseOpen,setPurchaseOpen]=useState(false);
 const original=new URLSearchParams(query),params=new URLSearchParams({view:'summary'});
 for(const key of ['from','to','months'])if(original.has(key))params.set(key,original.get(key)!);
 const reportQuery=params.toString();
 const report=loaded?.query===reportQuery?loaded.report:null,error=issue?.query===reportQuery?issue.message:'';
 function setError(message:string){setIssue(message?{query:reportQuery,message}:null);}
 useEffect(()=>{
  const controller=new AbortController();
  fetch('/api/kpi/internal-transfers?'+reportQuery,{cache:'no-store',signal:controller.signal}).then(async r=>{const d=await r.json();if(!r.ok)throw Error(d.error||'Underlaget kunde inte läsas');if(!controller.signal.aborted){setLoaded({query:reportQuery,report:d});setIssue(null);setExpanded(null);}}).catch(e=>{if(!controller.signal.aborted)setIssue({query:reportQuery,message:e instanceof Error?e.message:'Underlaget kunde inte läsas'});});
  return()=>controller.abort();
 },[reportQuery,refresh]);
 async function download(){setBusy(true);setError('');try{
  const p=new URLSearchParams(reportQuery);p.set('download','summary');
  const r=await fetch('/api/kpi/internal-transfers?'+p,{cache:'no-store'});if(!r.ok){const d=await r.json();throw Error(d.error||'Exporten misslyckades');}
  const url=URL.createObjectURL(await r.blob()),a=document.createElement('a');a.href=url;a.download='humla-interna-kst-'+p.get('from')+'-'+p.get('to')+'.csv';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
 }catch(e){setError(e instanceof Error?e.message:'Exporten misslyckades');}finally{setBusy(false);}}
 async function downloadEconomy(center:string){setBusy(true);setError('');try{
  const p=new URLSearchParams(reportQuery);p.set('download','economy_pdf');p.set('to_center',center);
  const response=await fetch('/api/kpi/internal-transfers?'+p,{cache:'no-store'});
  if(!response.ok){const data=await response.json();throw Error(data.error||'PDF kunde inte skapas');}
  const url=URL.createObjectURL(await response.blob()),a=document.createElement('a');a.href=url;a.download=`Internoverforing-${center}-${p.get('from')}-${p.get('to')}.pdf`;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
 }catch(e){setError(e instanceof Error?e.message:'PDF kunde inte skapas');}finally{setBusy(false);}}
 const selected=report?.transfers.find(t=>t.toCenter===expanded);
 const extraRows=expanded==='unassigned'?report?.unassignedItems:expanded==='other'?report?.otherItems:undefined;
 const toggle=(key:string)=>setExpanded(v=>v===key?null:key);
 return <section className="panel">
  <div className="panel-head"><div><span className="section-kicker">Överföringar mellan kostnadsställen</span><h2>Interna körningar</h2></div><button className="secondary" disabled={busy||(!report&&!error)} onClick={()=>setRefresh(n=>n+1)}>Uppdatera underlag</button></div>
  <p>Entreprenad (KST 10) bär kostnaden och Transport (KST 30) eller Sortergården (KST 20) får internintäkten. Periodbeloppen omfattar även preliminära rader, oavsett fakturerings- och exportstatus.</p>
  <p>Workify-underlag för Elleholms Maskin AB. STENA är extern kund. Kompatibla kopior av samma källrad räknas en gång. Motstridiga uppgifter och belopp utan KST-koppling visas i avstämningen. Rapporten utför ingen bokföring.</p>
  {error&&<p role="alert">{error}</p>}{!report&&!error&&<p role="status">Hämtar interna körningar…</p>}
  {report&&<>
   <section aria-label="Underlag till ekonomi"><h3>PDF för internöverföring till ekonomi</h3><p>Material till självkostnadspris. Tipp/deponi till debiteringsbelopp minus 10 %. Transport till fullt debiteringspris. Filen visar projekt, orderrader, prisunderlag och belopp att överföra. Uppskattade priser markeras. Beloppen skiljer sig därför från periodens ursprungliga internintäkter nedan.</p><div className="actions">{report.transfers.map(t=><button className="primary" key={t.toCenter}disabled={busy||!t.rows.length}onClick={()=>void downloadEconomy(t.toCenter)}>{busy?'Skapar fil…':`PDF till ekonomi - ${t.toName} (${t.toCenter})`}</button>)}</div></section>
   {!report.sourceRows&&<p>Inga interna orderrader hittades i perioden.</p>}
   {report.preliminaryTotal!==0&&<p role="status">Periodbeloppen är preliminära till den del som inte är bekräftad för omföring. Granskningsrader är synliga och ingår där KST och belopp kan bestämmas.</p>}
   <div className="table-wrap"><table><thead><tr><th>Överföring</th><th>Från KST – kostnad</th><th>Till KST – intäkt</th><th>Periodbelopp</th><th>Bekräftat för omföring</th><th>Preliminärt</th></tr></thead><tbody>{report.transfers.map(t=><tr key={t.toCenter}><td>{t.fromName} → {t.toName}</td><td>{t.fromCenter}</td><td>{t.toCenter}</td><td><button aria-expanded={expanded===t.toCenter} onClick={()=>toggle(t.toCenter)}><strong>{money.format(t.amount)}</strong></button><small>{t.rows.length} unika orderrader · visa underlag</small></td><td>{money.format(t.confirmedAmount)}</td><td>{money.format(t.preliminaryAmount)}</td></tr>)}</tbody><tfoot><tr><th colSpan={3}>Sammanlagt – de två överföringarna</th><td><strong>{money.format(report.total)}</strong></td><td>{money.format(report.confirmedTotal)}</td><td>{money.format(report.preliminaryTotal)}</td></tr></tfoot></table></div>
   {selected&&<section aria-label="Överföringens underlag"><h3>Underlag: {selected.fromName} → {selected.toName}</h3><p>{selected.rows.length} unika orderrader · {money.format(selected.amount)}. Exportstatusen visas separat och styr inte periodens ekonomiska belopp.</p><EvidenceRows key={expanded} rows={selected.rows}/></section>}
   <section aria-label="Avstämning av hela underlaget"><h3>Avstämning – inget belopp försvinner</h3><p>Importerat brutto innehåller samtliga kopior. Varje läsbart belopp återfinns i en av delarna nedan. Motstridiga källrader visas som brutto och kan innehålla kopior; de har ingen fastställd nettosumma.</p><div className="table-wrap"><table><thead><tr><th>Del av underlaget</th><th>Belopp</th><th>Underlag</th></tr></thead><tbody>
    <tr><td>De två överföringarna</td><td>{money.format(report.total)}</td><td>{report.transfers.map(t=>t.rows.length).join(' + ')} unika orderrader</td></tr>
    <tr><td>Entreprenad – saknar intäkts-KST</td><td><button aria-expanded={expanded==='unassigned'} onClick={()=>toggle('unassigned')}>{money.format(report.unassignedAmount)}</button></td><td>{report.unassignedRows} unika orderrader · visa underlag</td></tr>
    <tr><td>Andra KST-överföringar</td><td><button aria-expanded={expanded==='other'} onClick={()=>toggle('other')}>{money.format(report.otherAmount)}</button></td><td>{report.otherRows} unika orderrader · visa underlag</td></tr>
    <tr><td>Importkopior – borträknade en gång</td><td>{money.format(report.duplicateAmountRemoved)}</td><td>{report.duplicateRowsRemoved} extra kopior</td></tr>
    <tr><td>Motstridiga källrader – brutto</td><td><button aria-expanded={expanded==='conflict'} onClick={()=>toggle('conflict')}>{money.format(report.conflictRawAmount)}</button></td><td>{report.conflictCount} källnycklar · jämför varianter</td></tr>
   </tbody><tfoot><tr><th>Importerat brutto</th><td>{money.format(report.sourceAmount)}</td><td>{report.sourceRows} importerade rader</td></tr></tfoot></table></div>
    <p role={report.reconciles?'status':'alert'}>{report.reconciles?'Avstämningen stämmer: samtliga läsbara belopp är redovisade.':'Avstämningen har en avvikelse och behöver granskas.'}</p>
    {report.invalidAmountRows>0&&<p role="alert">{report.invalidAmountRows} importerade rader saknar läsbart belopp. Dessa kan inte beloppsavstämmas.</p>}
    {extraRows&&<section><h4>{expanded==='unassigned'?'Underlag utan intäkts-KST':'Övriga överföringars underlag'}</h4><EvidenceRows key={expanded} rows={extraRows}/></section>}
    {expanded==='conflict'&&<section><h4>Motstridiga importer – samtliga varianter</h4><p>Olika belopp, mängder eller andra ekonomiska uppgifter behöver kontrolleras. Ingen variant väljs automatiskt.</p>{report.conflicts.map(c=><section key={c.sourceKey}><h5>Order {c.variants[0]?.order} · {c.variants[0]?.occurred_on}</h5><EvidenceRows rows={c.variants} conflict/></section>)}</section>}
   </section>
   <div className="actions"><button className="secondary" disabled={busy} onClick={()=>void download()}>{busy?'Exporterar…':'Exportera hela avstämningen till CSV (Excel)'}</button><small>Alla delar och granskningsrader följer med. Exporten ändrar ingen status.</small></div>
  </>}
  <InternalMaterialRefunds query={reportQuery}/>
  <details onToggle={e=>setPurchaseOpen(e.currentTarget.open)}><summary>Inköpspriser – fortsatt arbete med kvitton och prislistor</summary>{purchaseOpen&&<PurchaseEvidence query={reportQuery}/>}</details>
 </section>;
}
