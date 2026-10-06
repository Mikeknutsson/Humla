'use client';
import {useEffect,useState} from 'react';
import dynamic from 'next/dynamic';
import {useRouter} from 'next/navigation';
import {ReviewEditor,type Row} from './import-review';
const Workbench=dynamic(()=>import('./kpi-unified-workbench').then(m=>m.KpiUnifiedWorkbench));
type EvidenceRow=Row&{kpi_import_batches:{file_name:string|null}|null};
type Queue={rows:EvidenceRow[];total:number;all:number;undated:number};
export function KpiReviewQueue({from,to,canManage}:{from:string;to:string;canManage:boolean}){
 const router=useRouter();
 const [scope,setScope]=useState('period'),[page,setPage]=useState(0),[revision,setRevision]=useState(0),[data,setData]=useState<Queue|null>(null),[error,setError]=useState(''),[loading,setLoading]=useState(true),[openWorkbench,setOpenWorkbench]=useState(false);
 useEffect(()=>{const c=new AbortController();setLoading(true);setData(null);setError('');const p=new URLSearchParams({scope,from,to,page:String(page)});fetch(`/api/kpi/review?${p}`,{cache:'no-store',signal:c.signal}).then(async r=>{const d=await r.json();if(!r.ok)throw Error(d.error);setData(d)}).catch(e=>{if(e.name!=='AbortError')setError(e.message)}).finally(()=>{if(!c.signal.aborted)setLoading(false)});return()=>c.abort()},[scope,from,to,page,revision]);
 function saved(){setPage(0);setRevision(v=>v+1);router.refresh();}
 return <section className="panel"><div className="panel-head"><div><span className="section-kicker">Importerat KPI-underlag</span><h2>Transaktioner som behöver granskas</h2></div><button className="secondary" disabled={loading} onClick={()=>setRevision(v=>v+1)}>Uppdatera granskningen</button></div>
 <p>Period: {from} – {to}. Rader utan giltigt datum visas också, eftersom de inte kan placeras i ett verksamhetsår. Dessa transaktioner ingår inte i KPI innan de är rättade och godkända.</p>
 <label>Visa<select value={scope} onChange={e=>{setScope(e.target.value);setPage(0)}}><option value="period">Periodens rader + rader utan datum</option><option value="undated">Enbart rader utan datum</option><option value="all">Alla verksamhetsår</option></select></label>
 {loading&&<p role="status">Hämtar KPI-rader som behöver granskas…</p>}{error&&<p role="alert">{error}</p>}
 {data&&<><p><strong>{data.total} rader i urvalet</strong> · {data.all} totalt i KPI-granskningen · {data.undated} saknar giltigt datum.</p>
 <div className="table-wrap"><table><thead><tr><th>Datum / import</th><th>Workify-order</th><th>Original / orsak</th><th>Åtgärd</th></tr></thead><tbody>{data.rows.map(row=><tr key={row.id}><td>{String(row.occurred_on??'Datum saknas')}<small>{row.kpi_import_batches?.file_name??'Import'} · rad {row.row_number}</small></td><td>{String(row.source_data.Ordernummer??'').trim()||'–'}</td><td><strong>{String(row.description??row.source_data.Artikelnamn??row.source_data.Artikelnummer??'Transaktion')}</strong><small>{row.validation_errors.join('; ')}</small><small>Projekt: {String(row.project_reference??'saknas')} · Fordon: {String(row.vehicle_registration??'saknas')}</small></td><td><details><summary>Öppna underlag och rätta</summary><details><summary>Originalvärden</summary><dl>{Object.entries(row.source_data).map(([k,v])=><div key={k}><dt>{k}</dt><dd>{String(v??'')}</dd></div>)}</dl></details>{canManage?<ReviewEditor row={row} onSaved={saved}/>:<p>Du behöver kpi.manage för att godkänna transaktionen.</p>}</details></td></tr>)}</tbody></table></div>
 {!data.total&&<p>Inga ogiltiga importrader finns i detta urval. Kopplingar och klassificeringar granskas separat nedan.</p>}
 <div className="actions"><button disabled={loading||page===0} onClick={()=>setPage(p=>p-1)}>Föregående</button><span>Sida {page+1} / {Math.max(1,Math.ceil(data.total/50))}</span><button disabled={loading||(page+1)*50>=data.total} onClick={()=>setPage(p=>p+1)}>Nästa</button></div></>}
 {canManage&&<details onToggle={e=>setOpenWorkbench(e.currentTarget.open)}><summary>Matcha kostnadsställen, kategorier och ekonomiska enheter</summary><p>Även giltiga transaktioner kan sakna ekonomisk klassificering. Välj vilken koppling som saknas i verktyget. Verifierade referenskopplingar sparas i Hubben med giltighet och historik; en rättning av en enskild transaktion ovan gäller endast den raden.</p>{openWorkbench&&<Workbench/>}</details>}
 </section>;
}
