'use client';
import {useState} from 'react';
import {parseMonthPeriod} from '@/lib/kpi/period';
type Item={row_id:string;canonical_key:string;kind:string;occurred_on:string|null;amount:number|null;currency:string;project:string|null;vehicle:string|null;cost_center:string|null;allocation_status:string;economic_status:string;file_name:string;row_number:number;source_data:unknown};
type Total={source_family:string;kind:string;economic_status:string;currency:string;rows:number;amount:number};
type Report={items:Item[];totals:Total[];includedRows:number;selectedRows:number;unallocatedRows:number;unknownIdentityRows:number;invalidAmountRows:number};
type Candidate={vehicleObjectId:string;registration:string;score:number;decision:string;evidence:unknown};
type Proposal={row_id:string;canonical_key:string;kind:string;occurred_on:string;amount:number;candidates:Candidate[]};
const labels:Record<string,string>={included:'Unik ekonomisk rad',excluded_duplicate:'Överlappande kopia',excluded_withdrawn:'Återtagen import',excluded_accounted_elsewhere:'Redan bokfört underlag',invalid_economic_data:'Ekonomiska uppgifter behöver granskas'};
const money=(n:number|null,currency='SEK')=>n===null?'Belopp saknas':n.toLocaleString('sv-SE',{style:'currency',currency});
export function HubEconomicReview({initialPeriod}:{initialPeriod?:{from:string;to:string}}){
 const year=parseMonthPeriod(undefined,undefined).fiscalYear;
 const [from,setFrom]=useState(initialPeriod?.from??`${year}-09-01`),[to,setTo]=useState(initialPeriod?.to??`${year+1}-08-31`),[status,setStatus]=useState('included');
 const [report,setReport]=useState<Report|null>(null),[proposals,setProposals]=useState<Proposal[]|null>(null),[page,setPage]=useState(0);
 const [busy,setBusy]=useState(false),[error,setError]=useState(''),[message,setMessage]=useState(''),[reason,setReason]=useState('');
 const clear=()=>{setReport(null);setProposals(null);setPage(0);setMessage('');};
 async function load(nextPage=0,candidates=false){
  setBusy(true);setError('');setMessage('');
  try{const query=new URLSearchParams({from,to,status,page:String(nextPage),view:candidates?'candidates':'ledger'});
   const response=await fetch(`/api/hub/economic-reconciliation?${query}`,{cache:'no-store'});const data=await response.json();
   if(!response.ok)throw Error(data.error??'Hubbens avstämning kunde inte hämtas.');
   setPage(nextPage);setReport(candidates?null:data);setProposals(candidates?data.items:null);
  }catch(e){setReport(null);setProposals(null);setError(e instanceof Error?e.message:'Underlaget kunde inte hämtas.');}finally{setBusy(false);}
 }
 async function confirm(row:Proposal,candidate:Candidate){
  if(reason.trim().length<3||!row.occurred_on)return;
  setBusy(true);setError('');
  try{const response=await fetch('/api/hub/allocation-rules',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({
   dimension:'vehicle',evidenceType:'fact',evidenceValue:row.canonical_key,targetObjectId:candidate.vehicleObjectId,
   kind:row.kind,from:row.occurred_on,to:row.occurred_on,reason:reason.trim()})});
   const data=await response.json();if(!response.ok)throw Error(data.error??'Bekräftelsen kunde inte sparas.');
   setProposals(current=>current?.filter(r=>r.row_id!==row.row_id)??null);setMessage('Bekräftelsen är sparad i Hubben för samma ekonomiska transaktion.');
  }catch(e){setError(e instanceof Error?e.message:'Bekräftelsen kunde inte sparas.');}finally{setBusy(false);}
 }
 return <section className="panel"><h3>Importavstämning och matchningssäkerhet</h3>
  <p>Jämförelseläge. Hubben tar med unika ekonomiska rader även när fördelning saknas. De ordinarie KPI-totalerna är ännu inte omkopplade.</p>
  <p>Detta är importerade källbelopp, inte företagets resultat. Interna elimineringar, beräknad lön och Piusi-fördelning ingår inte i denna avstämning.</p>
  <div className="filters"><label>Från<input type="date" value={from} disabled={busy} onChange={e=>{setFrom(e.target.value);clear();}}/></label>
   <label>Till<input type="date" value={to} disabled={busy} onChange={e=>{setTo(e.target.value);clear();}}/></label>
   <label>Underlag<select value={status} disabled={busy} onChange={e=>{setStatus(e.target.value);clear();}}><option value="all">Alla rader</option>{Object.entries(labels).map(([key,label])=><option value={key} key={key}>{label}</option>)}</select></label>
   <button type="button" disabled={busy} onClick={()=>load()}>Hämta avstämning</button><button type="button" disabled={busy} onClick={()=>load(0,true)}>Fordonsförslag</button></div>
  {busy&&<p role="status">Hämtar Hub-underlag…</p>}{error&&<p role="alert">{error}</p>}{message&&<p role="status">{message}</p>}
  {report&&<><p>{report.includedRows} unika rader ingår. {report.unallocatedRows} saknar säker fordonsfördelning. {report.unknownIdentityRows} saknar säker historisk källidentitet.</p>
   {report.invalidAmountRows>0&&<p role="alert">{report.invalidAmountRows} oläsbara belopp kan inte visas som noll.</p>}
   <div className="table-wrap"><table><thead><tr><th>Källa</th><th>Typ</th><th>Status</th><th>Rader</th><th>Belopp</th></tr></thead><tbody>{report.totals.map((t,i)=><tr key={i}><td>{t.source_family}</td><td>{t.kind==='cost'?'Kostnad':'Intäkt'}</td><td>{labels[t.economic_status]}</td><td>{t.rows}</td><td>{money(t.amount,t.currency)}</td></tr>)}</tbody></table></div>
   <h4>Originalunderlag — {report.selectedRows} rader i urvalet</h4><div className="table-wrap"><table><thead><tr><th>Datum / fil</th><th>Belopp</th><th>Fördelning</th><th>Originalrad</th></tr></thead><tbody>{report.items.map(r=><tr key={r.row_id}><td>{r.occurred_on??'Datum saknas'}<br/>{r.file_name} · rad {r.row_number}</td><td>{money(r.amount,r.currency)}</td><td>{r.project??'Projekt ofördelat'}<br/>{r.vehicle??'Fordon ofördelat'}<br/>KST {r.cost_center??'ofördelat'}<br/>{r.allocation_status}</td><td>{labels[r.economic_status]}<details><summary>Visa original och nyckel</summary><code>{r.canonical_key}</code><pre style={{whiteSpace:'pre-wrap',maxWidth:600}}>{JSON.stringify(r.source_data,null,2)}</pre></details></td></tr>)}</tbody></table></div>
   <nav aria-label="Avstämningssidor"><button type="button" disabled={busy||page===0} onClick={()=>load(page-1)}>Föregående</button> Sida {page+1} <button type="button" disabled={busy||(page+1)*100>=report.selectedRows} onClick={()=>load(page+1)}>Nästa</button></nav></>}
  {proposals&&<><p>Poäng är evidensstyrka, inte kalibrerad statistisk sannolikhet. Inga gissningar sparas permanent automatiskt.</p><label>Motivering till bekräftelse<input value={reason} maxLength={1000} disabled={busy} onChange={e=>setReason(e.target.value)}/></label>
   <div className="table-wrap"><table><thead><tr><th>Transaktion</th><th>Fordonsförslag</th></tr></thead><tbody>{proposals.map(r=><tr key={r.row_id}><td>{r.occurred_on}<br/>{money(r.amount)}<br/><code>{r.canonical_key}</code></td><td>{r.candidates.length===0?'Inga tillräckliga signaler':r.candidates.map(c=><div key={c.vehicleObjectId}>{c.registration} · {c.score}/100 · {c.decision}<details><summary>Evidens</summary><pre style={{whiteSpace:'pre-wrap'}}>{JSON.stringify(c.evidence,null,2)}</pre></details><button type="button" disabled={busy||reason.trim().length<3} onClick={()=>confirm(r,c)}>Bekräfta endast denna transaktion</button></div>)}</td></tr>)}</tbody></table></div>
   <nav aria-label="Förslagssidor"><button type="button" disabled={busy||page===0} onClick={()=>load(page-1,true)}>Föregående</button> Sida {page+1} <button type="button" disabled={busy||proposals.length<100} onClick={()=>load(page+1,true)}>Nästa</button></nav></>}
 </section>;
}
