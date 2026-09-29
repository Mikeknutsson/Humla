'use client';
import { useState } from 'react';
type Row = {id:string;row_number:number;source_data:Record<string,unknown>;validation_errors:string[]};
export function ImportReview({batchId}: {batchId:string}) {
 const [rows,setRows]=useState<Row[]>([]), [page,setPage]=useState(0), [total,setTotal]=useState(0), [error,setError]=useState(''), [busy,setBusy]=useState(false), [open,setOpen]=useState(false);
 async function load(next:number) {
  setBusy(true);setError('');
  try {const res=await fetch(`/api/kpi/review?batch=${batchId}&page=${next}`,{signal:AbortSignal.timeout(30000)});const data=await res.json();if(!res.ok)throw new Error(data.error);setRows(data.rows);setTotal(data.total);setPage(next);setOpen(true);}catch(e){setError(e instanceof Error?e.message:'Kunde inte hämta rader');}finally{setBusy(false);}
 }
 return <div><button className="secondary" disabled={busy} onClick={()=>open?setOpen(false):load(0)}>{busy?'Hämtar…':open?'Stäng granskning':'Granska transaktioner'}</button>{error&&<p role="alert">{error}</p>}{open&&<div><p>{total} transaktioner väntar på granskning och ingår inte i KPI. Giltiga rader från samma import räknas redan. Originalvärden visas nedan; ändring av sparade rader är ännu inte tillgänglig.</p>{rows.map(row=><details key={row.id}><summary>Datarad {row.row_number}: {row.validation_errors.join(', ')}</summary><dl>{Object.entries(row.source_data).map(([key,value])=><div key={key}><dt>{key}</dt><dd>{String(value??'')}</dd></div>)}</dl></details>)}<button disabled={busy||page===0} onClick={()=>load(page-1)}>Föregående</button> <span>Sida {page+1}</span> <button disabled={busy||(page+1)*50>=total} onClick={()=>load(page+1)}>Nästa</button></div>}</div>;
}
