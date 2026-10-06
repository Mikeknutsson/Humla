'use client';
import {useEffect,useState} from 'react';
import dynamic from 'next/dynamic';
import {useRouter} from 'next/navigation';
import {ReviewEditor,type Row,type ReviewResult} from './import-review';
import {ReviewSelect,reviewCostCenters,useReviewOptions} from './review-select';
import {assignedWorkifyName,changeReviewRouting,reviewKey,reviewValues,vehicleSelection,type ReviewDraft} from '@/lib/kpi/review-drafts';
const Workbench=dynamic(()=>import('./kpi-unified-workbench').then(m=>m.KpiUnifiedWorkbench));
type EvidenceRow=Row&{kpi_import_batches:{file_name:string|null}|null};
type Queue={rows:EvidenceRow[];total:number;all:number;undated:number};
export function KpiReviewQueue({from,to,canManage}:{from:string;to:string;canManage:boolean}){
 const router=useRouter();
 const {options,error:optionError}=useReviewOptions(canManage);
 const [message,setMessage]=useState(''),[drafts,setDrafts]=useState<Record<string,ReviewDraft>>({}),[reason,setReason]=useState(''),[saving,setSaving]=useState(false);
 const [scope,setScope]=useState('period'),[page,setPage]=useState(0),[revision,setRevision]=useState(0),[data,setData]=useState<Queue|null>(null),[error,setError]=useState(''),[loading,setLoading]=useState(true),[openWorkbench,setOpenWorkbench]=useState(false);
 const pending=Object.keys(drafts).length;
 useEffect(()=>{const c=new AbortController();setLoading(true);setData(null);setError('');const p=new URLSearchParams({scope,from,to,page:String(page)});fetch(`/api/kpi/review?${p}`,{cache:'no-store',signal:c.signal}).then(async r=>{const d=await r.json();if(!r.ok)throw Error(d.error);setData(d)}).catch(e=>{if(e.name!=='AbortError')setError(e.message)}).finally(()=>{if(!c.signal.aborted)setLoading(false)});return()=>c.abort()},[scope,from,to,page,revision]);
 useEffect(()=>{if(!pending)return;const guard=(e:BeforeUnloadEvent)=>{e.preventDefault();e.returnValue='';};window.addEventListener('beforeunload',guard);return()=>window.removeEventListener('beforeunload',guard)},[pending]);
 function refresh(){setPage(0);setRevision(v=>v+1);router.refresh();}
 function saved(result:ReviewResult){setMessage(result.order_number?`Order ${result.order_number}: kopplingen sparades på ${result.affected} rader.`:'Transaktionen är godkänd.');refresh();}
 function change(row:Row,field:string,value:string){setDrafts(current=>({...current,[reviewKey(row)]:changeReviewRouting(row,current[reviewKey(row)],field,value)}));setMessage('');}
 function stage(row:Row,values:Record<string,unknown>,rowReason:string){setDrafts(current=>({...current,[reviewKey(row)]:{row,values,reason:rowReason}}));setMessage('Ändringen är tillagd. Tryck Spara alla ändringar när du är klar.');}
 async function saveAll(event:React.FormEvent){
  event.preventDefault();if(saving||!pending)return;setSaving(true);setError('');setMessage('');
  const entries=Object.entries(drafts);const successes:string[]=[];const failures:string[]=[];let cursor=0;let affected=0;let stillPending=0;
  async function worker(){while(cursor<entries.length){const [key,draft]=entries[cursor++];try{
   const response=await fetch('/api/kpi/review',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:draft.row.id,values:draft.values,reason:draft.reason?.trim()||reason.trim()}),signal:AbortSignal.timeout(60000)});
   const result=await response.json();if(!response.ok)throw Error(result.error);successes.push(key);affected+=result.affected??1;stillPending+=result.pending??0;
  }catch(e){failures.push(`${key.startsWith('workify:')?'Order '+key.slice(8):'Rad '+draft.row.row_number}: ${e instanceof Error?e.message:'Kunde inte spara'}`);}}}
  try{await Promise.all([worker(),worker()]);setDrafts(current=>Object.fromEntries(Object.entries(current).filter(([key])=>!successes.includes(key))));
   setMessage(`${successes.length} ändringar sparade på ${affected} transaktionsrader.${stillPending?` ${stillPending} rader behöver fortfarande datum eller belopp.`:''}`);
   if(failures.length)setError(failures.join(' · '));if(successes.length)refresh();
  }finally{setSaving(false)}
 }
 return <section className="panel"><div className="panel-head"><div><span className="section-kicker">Importerat KPI-underlag</span><h2>Transaktioner som behöver granskas</h2></div><button className="secondary" disabled={loading||saving} onClick={()=>setRevision(v=>v+1)}>Uppdatera granskningen</button></div>
 <p>Välj projekt eller fordon direkt i tabellen. Du kan ändra flera order innan du sparar. Workify-kopplingar gäller hela ordern, även rader utanför denna sida. Belopp och datum behålls per rad.</p>
 <p>Period: {from} – {to}. Rader utan giltigt datum visas också. Dessa transaktioner ingår inte i KPI innan de är rättade och godkända.</p>
 <label>Visa<select disabled={saving} value={scope} onChange={e=>{setScope(e.target.value);setPage(0)}}><option value="period">Periodens rader + rader utan datum</option><option value="undated">Enbart rader utan datum</option><option value="all">Alla verksamhetsår</option></select></label>
 {canManage&&<form onSubmit={saveAll} className="review-batch-actions"><strong>{pending} osparade ändringar</strong><label>Gemensam motivering<input value={reason} disabled={saving} required={pending>0&&Object.values(drafts).some(d=>!d.reason?.trim())} minLength={3} maxLength={1000} onChange={e=>setReason(e.target.value)} placeholder="Vad har kontrollerats?"/></label><div className="actions"><button className="primary" disabled={saving||!pending}>{saving?'Sparar ändringarna…':`Spara alla ändringar (${pending})`}</button><button type="button" disabled={saving||!pending} onClick={()=>{setDrafts({});setMessage('Osparade ändringar återställda.')}}>Återställ osparade</button></div>{pending>0&&<small>Valen sparas först när du trycker Spara alla ändringar. Du kan byta sida i tabellen utan att tappa dem.</small>}</form>}
 {optionError&&<p role="alert">{optionError}</p>}{message&&<p role="status">{message}</p>}{loading&&<p role="status">Hämtar KPI-rader som behöver granskas…</p>}{error&&<p role="alert">{error}</p>}
 {data&&<><p><strong>{data.total} rader i urvalet</strong> · {data.all} totalt i KPI-granskningen · {data.undated} saknar giltigt datum.</p>
 <div className="table-wrap"><table><thead><tr><th>Datum / import</th><th>Workify-order</th><th>Tilldelad</th><th>Original / orsak</th>{canManage&&<><th>Projekt</th><th>Fordon / regnummer</th><th>Kostnadsställe</th></>}<th>Underlag / rätta rad</th></tr></thead><tbody>{data.rows.map(row=>{
  const key=reviewKey(row),draft=drafts[key],values=draft?.values??reviewValues(row);
  const editorRow={...row,...(draft?.row.id===row.id?draft.values:draft?{project_reference:values.project_reference,vehicle_registration:values.vehicle_registration,cost_center:values.cost_center}:{})};
  return <tr key={row.id}><td>{String(row.occurred_on??'Datum saknas')}<small>{row.kpi_import_batches?.file_name??'Import'} · rad {row.row_number}</small></td><td>{String(row.source_data.Ordernummer??'').trim()||'–'}{draft&&<small>Osparad ändring</small>}</td><td>{assignedWorkifyName(row)}</td><td><strong>{String(row.description??row.source_data.Artikelnamn??row.source_data.Artikelnummer??'Transaktion')}</strong><small>{row.validation_errors.join('; ')}</small><small>Projekt: {String(row.project_reference??'saknas')} · Fordon: {String(row.vehicle_registration??'saknas')}</small></td>
  {canManage&&<><td><ReviewSelect label={`Projekt för rad ${row.row_number}`} value={String(values.project_reference??'')} options={options?.projects??[]} disabled={saving||!options} onChange={value=>change(row,'project_reference',value)}/></td><td><ReviewSelect label={`Fordon för rad ${row.row_number}`} value={vehicleSelection(values.vehicle_registration)} options={options?.vehicles??[]} disabled={saving||!options} onChange={value=>change(row,'vehicle_registration',value)}/></td><td><ReviewSelect label={`Kostnadsställe för rad ${row.row_number}`} value={String(values.cost_center??'')} options={reviewCostCenters} disabled={saving} onChange={value=>change(row,'cost_center',value)}/></td></>}
  <td><details><summary>Öppna underlag och rätta</summary><details><summary>Originalvärden</summary><dl>{Object.entries(row.source_data).map(([k,v])=><div key={k}><dt>{k}</dt><dd>{String(v??'')}</dd></div>)}</dl></details>{canManage?<ReviewEditor key={JSON.stringify([values.project_reference,values.vehicle_registration,values.cost_center])} row={editorRow} options={options} onSaved={saved} disabled={saving} onStaged={(payload,rowReason)=>stage(row,payload,rowReason)}/>:<p>Du behöver kpi.manage för att godkänna transaktionen.</p>}</details></td></tr>;
 })}</tbody></table></div>
 {!data.total&&<p>Inga ogiltiga importrader finns i detta urval. Kopplingar och klassificeringar granskas separat nedan.</p>}
 <div className="actions"><button disabled={loading||saving||page===0} onClick={()=>setPage(p=>p-1)}>Föregående</button><span>Sida {page+1} / {Math.max(1,Math.ceil(data.total/50))}</span><button disabled={loading||saving||(page+1)*50>=data.total} onClick={()=>setPage(p=>p+1)}>Nästa</button></div></>}
 {canManage&&<details onToggle={e=>setOpenWorkbench(e.currentTarget.open)}><summary>Matcha kostnadsställen, kategorier och ekonomiska enheter</summary><p>Även giltiga transaktioner kan sakna ekonomisk klassificering. Verifierade referenskopplingar sparas i Hubben med giltighet och historik. Workify-rättningar ovan kopplar hela ordern till samma projekt, fordon och kostnadsställe.</p>{openWorkbench&&<Workbench/>}</details>}
 </section>;
}
