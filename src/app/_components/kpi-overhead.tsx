'use client';
import {useState} from 'react';
import type {OverheadKpi} from '@/lib/kpi/overhead';
import {parseMonthPeriod} from '@/lib/kpi/period';
const format=(v:number|null|undefined,unit:string)=>v==null?'Underlag saknas':new Intl.NumberFormat('sv-SE',{maximumFractionDigits:unit==='%'?1:2}).format(v)+' '+unit;
export function KpiOverhead({data,query,canManage=false}:{data?:OverheadKpi;query:string;canManage?:boolean}){
 const params=new URLSearchParams(query),period=parseMonthPeriod(params.get('fiscal_year')??undefined,params.get('months')??undefined);
 const center=params.get('cost_center')??'',m=period.months.length===1?period.months[0]:null;
 const month=m?`${m>=9?period.fiscalYear:period.fiscalYear+1}-${String(m).padStart(2,'0')}-01`:'';
 const scoped=['unit','group','vehicle','project'].some(k=>params.has(k));
 const [management,setManagement]=useState(''),[other,setOther]=useState(''),[evidence,setEvidence]=useState(''),[busy,setBusy]=useState(false),[message,setMessage]=useState('');
 async function save(e:React.FormEvent){e.preventDefault();setBusy(true);setMessage('');try{
  const response=await fetch('/api/kpi/overhead',{method:'POST',headers:{'Content-Type':'application/json'},signal:AbortSignal.timeout(20000),body:JSON.stringify({month,center,management:Number(management),other:Number(other),evidence})});
  const result=await response.json();if(!response.ok)throw Error(result.error);window.location.reload();
 }catch(e){setMessage(e instanceof Error?e.message:'Underlaget kunde inte sparas.');setBusy(false);}}
 return <section className="panel"><h2>Overhead och arbetsledning</h2><div className="metrics-grid">
 <div className="metric-card"><span>Overhead totalt</span><strong>{format(data?.total_overhead,'kr')}</strong><small>{format(data?.overhead_revenue_pct,'%')} av omsättningen</small></div>
 <div className="metric-card"><span>Arbetsledning</span><strong>{format(data?.management_cost,'kr')}</strong><small>{format(data?.management_revenue_pct,'%')} av omsättningen · {format(data?.management_overhead_pct,'%')} av overhead</small></div>
 <div className="metric-card"><span>Overhead / debiterbar timme</span><strong>{format(data?.overhead_per_billable_hour,'kr/h')}</strong><small>{format(data?.billable_hours,'h')} debiterbar tid · Arbetsledning {format(data?.management_per_billable_hour,'kr/h')}</small></div>
 </div><p>{data?.missing_reason}</p><details><summary>Definition och underlag</summary><p>{data?.basis??'Verifierat månadsunderlag behövs.'}</p><p>Övrig overhead: {format(data?.other_overhead,'kr')}. Kostnadsunderlag för {data?.covered_month_scopes??0} av {data?.expected_month_scopes??0} månad/kostnadsställe.</p></details>
 {canManage&&!scoped&&month&&center&&!center.includes(',')&&<details><summary>Lägg in verifierat månadsunderlag – KST {center}</summary><p>Arbetsledning anges inklusive lönebikostnader. Övrig overhead anges utan arbetsledning. Detta klassificeringsunderlag ändrar inte bokförda kostnader eller resultat.</p><form onSubmit={save} className="form-grid"><label>Arbetsledning, kr<input required type="number" min="0" step="0.01" value={management} onChange={e=>setManagement(e.target.value)}/></label><label>Övrig overhead, kr<input required type="number" min="0" step="0.01" value={other} onChange={e=>setOther(e.target.value)}/></label><label>Hänvisning till underlag<input required minLength={3} maxLength={1000} value={evidence} onChange={e=>setEvidence(e.target.value)} placeholder="Rapport, faktura eller löneunderlag"/></label><button disabled={busy}>{busy?'Sparar…':'Spara månadsunderlag'}</button></form><p role="status">{message}</p></details>}
 {canManage&&!month&&<p>Välj en månad och ett kostnadsställe för att lägga in kostnadsunderlaget.</p>}
 </section>;
}
