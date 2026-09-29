'use client';
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { DATA_KINDS, type DataKind } from '@/lib/kpi/schema';
type Row = {id:string;row_number:number;data_kind:DataKind;source_data:Record<string,unknown>;validation_errors:string[];[key:string]:unknown};
const numbers=new Set(['amount','quantity','available_hours','occupied_hours','paid_hours','billable_hours']);
function ReviewEditor({row,onSaved}: {row:Row;onSaved:()=>void}) {
 const [values,setValues]=useState<Record<string,string>>(()=>Object.fromEntries(DATA_KINDS[row.data_kind].fields.map(f=>[f.key,String(row[f.key]??'')])));
 const [target,setTarget]=useState(row.project_reference?'project':row.vehicle_registration?'vehicle':'');
 const [reason,setReason]=useState(''),[error,setError]=useState(''),[busy,setBusy]=useState(false);
 async function save(event:React.FormEvent) {
  event.preventDefault();setBusy(true);setError('');
  try {
   const payload:Record<string,unknown>={};
   for(const [key,value] of Object.entries(values)) {
    const text=value.trim();
    if(numbers.has(key)) {const n=Number(text.replace(/\s/g,'').replace(',','.'));if(text&&!Number.isFinite(n))throw new Error('Kontrollera talvärdena');payload[key]=text?n:null;}
    else payload[key]=text||null;
   }
   if(typeof payload.vehicle_registration==='string')payload.vehicle_registration=payload.vehicle_registration.toUpperCase().replace(/[\s-]/g,'');
   if(row.data_kind==='revenue')payload.review_target=target;
   const res=await fetch('/api/kpi/review',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:row.id,values:payload,reason}),signal:AbortSignal.timeout(30000)});
   const data=await res.json();if(!res.ok)throw new Error(data.error);onSaved();
  }catch(e){setError(e instanceof Error?e.message:'Kunde inte spara. Ladda om granskningen för att kontrollera status.');}finally{setBusy(false);}
 }
 return <form onSubmit={save}><p>Rätta denna transaktion. Originalet bevaras och ändringen loggas. Kopplingen gäller bara denna rad.</p>{row.data_kind==='revenue'&&<label>Intäkten tillhör <select required value={target} onChange={e=>setTarget(e.target.value)}><option value="">Välj fördelning</option><option value="project">Projekt</option><option value="vehicle">Utförande fordon</option></select></label>}<div className="mapping-grid">{DATA_KINDS[row.data_kind].fields.filter(f=>row.data_kind!=='revenue'||(f.key!=='employee_number'&&(target!=='project'||f.key!=='vehicle_registration')&&(target!=='vehicle'||f.key!=='project_reference'))).map(f=><label key={f.key}><span>{f.label}</span><input type={f.key==='occurred_on'?'date':'text'} inputMode={numbers.has(f.key)?'decimal':undefined} value={values[f.key]??''} required={f.required} onChange={e=>setValues({...values,[f.key]:e.target.value})}/></label>)}</div><label>Motivering<input required minLength={3} maxLength={1000} value={reason} onChange={e=>setReason(e.target.value)} placeholder="Vad har kontrollerats eller rättats?"/></label>{error&&<p role="alert">{error}</p>}<button className="primary" disabled={busy}>{busy?'Sparar…':'Spara och godkänn transaktionen'}</button></form>;
}
export function ImportReview({batchId,canManage=false}: {batchId:string;canManage?:boolean}) {
 const router=useRouter();
 const [history,setHistory]=useState<Array<{id:string;reason:string;created_at:string;actor:string;previous:Record<string,unknown>;current:Record<string,unknown>}>>([]),[historyPage,setHistoryPage]=useState(0),[historyTotal,setHistoryTotal]=useState(0),[historyOpen,setHistoryOpen]=useState(false);
 async function loadHistory(next:number){setBusy(true);setError('');try{const res=await fetch(`/api/kpi/review?batch=${batchId}&history=1&page=${next}`,{signal:AbortSignal.timeout(30000)});const data=await res.json();if(!res.ok)throw new Error(data.error);setHistory(data.rows);setHistoryTotal(data.total);setHistoryPage(next);setHistoryOpen(true);}catch(e){setError(e instanceof Error?e.message:'Historiken kunde inte hämtas');}finally{setBusy(false);}}

 const [rows,setRows]=useState<Row[]>([]),[page,setPage]=useState(0),[total,setTotal]=useState(0),[error,setError]=useState(''),[busy,setBusy]=useState(false),[open,setOpen]=useState(false),[message,setMessage]=useState('');
 async function load(next:number) {
  setBusy(true);setError('');
  try {const res=await fetch(`/api/kpi/review?batch=${batchId}&page=${next}`,{signal:AbortSignal.timeout(30000)});const data=await res.json();if(!res.ok)throw new Error(data.error);setRows(data.rows);setTotal(data.total);setPage(next);setOpen(true);}catch(e){setError(e instanceof Error?e.message:'Kunde inte hämta rader');}finally{setBusy(false);}
 }
 function saved(){setMessage('Transaktionen är godkänd. KPI räknas om; okända konton och osäkra enhetskopplingar är fortsatt spärrade.');void load(0);router.refresh();}
 return <div><button className="secondary" disabled={busy} onClick={()=>open?setOpen(false):load(0)}>{busy?'Hämtar…':open?'Stäng granskning':'Granska transaktioner'}</button>{error&&<p role="alert">{error}</p>}{message&&<p role="status">{message}</p>}<button className="secondary" disabled={busy} onClick={()=>historyOpen?setHistoryOpen(false):loadHistory(0)}>Ändringshistorik</button>{historyOpen&&<div><p>{historyTotal} ändringar</p>{history.map(event=><details key={event.id}><summary>{new Date(event.created_at).toLocaleString('sv-SE')} · Rad {String(event.current.row_number)} · {event.reason}</summary><p>Granskare: {event.actor}</p><table><thead><tr><th>Fält</th><th>Före</th><th>Efter</th></tr></thead><tbody>{Object.keys(event.current).filter(key=>JSON.stringify(event.previous[key])!==JSON.stringify(event.current[key])).map(key=><tr key={key}><td>{key}</td><td>{JSON.stringify(event.previous[key])}</td><td>{JSON.stringify(event.current[key])}</td></tr>)}</tbody></table></details>)}<button disabled={busy||historyPage===0} onClick={()=>loadHistory(historyPage-1)}>Föregående ändringar</button><button disabled={busy||(historyPage+1)*50>=historyTotal} onClick={()=>loadHistory(historyPage+1)}>Nästa ändringar</button></div>}{open&&<div><p>{total} transaktioner väntar på granskning och ingår inte i KPI. Giltiga rader från samma import räknas redan.</p>{rows.map(row=><details key={row.id}><summary>Datarad {row.row_number}: {row.validation_errors.join(', ')}</summary><details><summary>Visa originalvärden</summary><dl>{Object.entries(row.source_data).map(([key,value])=><div key={key}><dt>{key}</dt><dd>{String(value??'')}</dd></div>)}</dl></details>{canManage&&<ReviewEditor row={row} onSaved={saved}/>}</details>)}<button disabled={busy||page===0} onClick={()=>load(page-1)}>Föregående</button> <span>Sida {page+1}</span> <button disabled={busy||(page+1)*50>=total} onClick={()=>load(page+1)}>Nästa</button></div>}</div>;
}
