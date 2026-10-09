'use client';
import {useEffect,useState} from 'react';
import dynamic from 'next/dynamic';
import type {InternalCenterSummary} from '@/lib/kpi/internal-center-summary';
const PurchaseEvidence=dynamic(()=>import('./internal-purchase-evidence').then(m=>m.InternalPurchaseEvidence),{loading:()=> <p>Laddar inköpsunderlag…</p>});
const money=new Intl.NumberFormat('sv-SE',{style:'currency',currency:'SEK'});
const statusLabel={new:'Nytt underlag',review:'Behöver granskas',changed:'Ändrat efter export',exported:'Exporterat',posted:'Omfört'};
export function InternalTransfers({query}:{query:string;canManage:boolean}){
 const [report,setReport]=useState<InternalCenterSummary|null>(null),[error,setError]=useState(''),[busy,setBusy]=useState(false),[refresh,setRefresh]=useState(0),[expanded,setExpanded]=useState<string|null>(null),[page,setPage]=useState(0);
 const [purchaseOpen,setPurchaseOpen]=useState(false);
 // Inherit only period: always show both requested transfers.
 const original=new URLSearchParams(query),params=new URLSearchParams({view:'summary'});
 for(const key of ['from','to','months'])if(original.has(key))params.set(key,original.get(key)!);
 const reportQuery=params.toString();
 useEffect(()=>{
  const controller=new AbortController();setReport(null);setError('');setExpanded(null);setPage(0);
  fetch(`/api/kpi/internal-transfers?${reportQuery}`,{cache:'no-store',signal:controller.signal}).then(async r=>{const d=await r.json();if(!r.ok)throw Error(d.error||'Underlaget kunde inte läsas');if(!controller.signal.aborted)setReport(d);}).catch(e=>{if(!controller.signal.aborted)setError(e instanceof Error?e.message:'Underlaget kunde inte läsas');});
  return()=>controller.abort();
 },[reportQuery,refresh]);
 async function download(){setBusy(true);setError('');try{
  const p=new URLSearchParams(reportQuery);p.set('download','summary');
  const r=await fetch(`/api/kpi/internal-transfers?${p}`,{cache:'no-store'});if(!r.ok){const d=await r.json();throw Error(d.error||'Exporten misslyckades');}
  const url=URL.createObjectURL(await r.blob()),a=document.createElement('a');a.href=url;a.download=`humla-interna-kst-${p.get('from')}-${p.get('to')}.csv`;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
 }catch(e){setError(e instanceof Error?e.message:'Exporten misslyckades');}finally{setBusy(false);}}
 const selected=report?.transfers.find(t=>t.toCenter===expanded);
 return <section className="panel">
  <div className="panel-head"><div><span className="section-kicker">Överföringar mellan kostnadsställen</span><h2>Interna körningar</h2></div><button className="secondary" disabled={busy||(!report&&!error)} onClick={()=>setRefresh(n=>n+1)}>Uppdatera underlag</button></div>
  <p>En summa per överföring för vald period. Entreprenad (KST 10) bär kostnaden, Transport (KST 30) eller Sortergården (KST 20) får internintäkten. Ingen uppdelning på fordon, projekt eller inköpspriser.</p>
  <p>Fakturerade och granskade Workify-rader för Elleholms Maskin AB. STENA räknas som extern kund och ingår inte. Beloppen är omföringsunderlag, inte kundinbetalningar. Ingen bokföring eller ändring av exportstatus sker här.</p>
  {error&&<p role="alert">{error}</p>}{!report&&!error&&<p role="status">Hämtar interna körningar…</p>}
  {report&&<>
   <div className="table-wrap"><table><thead><tr><th>Överföring</th><th>Från KST – kostnad</th><th>Till KST – intäkt</th><th>Summa</th></tr></thead><tbody>{report.transfers.map(t=><tr key={t.toCenter}><td>{t.fromName} → {t.toName}</td><td>{t.fromCenter}</td><td>{t.toCenter}</td><td><button aria-expanded={expanded===t.toCenter} onClick={()=>{setExpanded(expanded===t.toCenter?null:t.toCenter);setPage(0);}}><strong>{money.format(t.amount)}</strong></button><small>{t.rows.length} orderrader · klicka för underlag</small>{t.excludedRows>0&&<small>{t.excludedRows} ej färdiga/ändrade rader ({money.format(t.excludedAmount)}) ingår inte.</small>}</td></tr>)}</tbody><tfoot><tr><th colSpan={3}>Sammanlagt – de två överföringarna</th><td><strong>{money.format(report.total)}</strong></td></tr></tfoot></table></div>
   {report.unassignedRows>0&&<p role="status">{report.unassignedRows} rader för Entreprenad saknar intäkts-KST och ingår inte. Kopplingarna hanteras i Kontrollpanelen.</p>}
   <div className="actions"><button className="secondary" disabled={busy} onClick={()=>void download()}>{busy?'Exporterar…':'Exportera summor och underlag till CSV (Excel)'}</button><small>Rapportexporten ändrar ingen status.</small></div>
   {selected&&<section aria-label="Överföringens underlag"><h3>Underlag: {selected.fromName} → {selected.toName}</h3><p>{selected.rows.length} orderrader · {money.format(selected.amount)}. Redan exporterade och omförda rader ingår i periodens summa, men rapportexporten är inte ett nytt bokföringsuppdrag.</p><div className="table-wrap"><table><thead><tr><th>Datum</th><th>Order</th><th>Littra</th><th>Belopp</th><th>Status</th></tr></thead><tbody>{selected.rows.slice(page*100,(page+1)*100).map(r=><tr key={r.row_id}><td>{r.occurred_on}</td><td>{r.order}</td><td>{r.littra||'—'}</td><td>{money.format(r.amount!)}</td><td>{statusLabel[r.status]}</td></tr>)}</tbody></table></div><div className="actions"><button disabled={page===0} onClick={()=>setPage(n=>n-1)}>Föregående</button><span>Sida {page+1} / {Math.max(1,Math.ceil(selected.rows.length/100))}</span><button disabled={(page+1)*100>=selected.rows.length} onClick={()=>setPage(n=>n+1)}>Nästa</button></div></section>}
  </>}
  <details onToggle={e=>setPurchaseOpen(e.currentTarget.open)}><summary>Inköpspriser – fortsatt arbete med kvitton och prislistor</summary>{purchaseOpen&&<PurchaseEvidence query={reportQuery}/>}</details>
 </section>;
}
