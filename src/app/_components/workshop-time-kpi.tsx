'use client';
import {useEffect,useState}from 'react';
type Person={name:string;work_hours:number;absence_hours:number;billable_hours:number;non_billable_hours:number;billing_rate:number|null};
type Report={available:boolean;work_hours:number;absence_hours:number;billable_hours:number;non_billable_hours:number;billing_rate:number|null;review_rows:number;duplicate_rows:number;people:Person[];centers:{code:string;name:string;hours:number}[]};
const n=(v:number)=>new Intl.NumberFormat('sv-SE',{maximumFractionDigits:1}).format(v);
export function WorkshopTimeKpi({query}:{query:string}){
 const[state,setState]=useState<{query:string;data:Report|null;error:boolean}>({query:'',data:null,error:false});
 useEffect(()=>{const controller=new AbortController();fetch(`/api/kpi/workshop-time?${query}`,{signal:controller.signal}).then(async r=>{if(!r.ok)throw new Error('Failed');const data:Report=await r.json();if(!controller.signal.aborted)setState({query,data,error:false});}).catch(()=>{if(!controller.signal.aborted)setState({query,data:null,error:true});});return()=>controller.abort();},[query]);
 const data=state.query===query?state.data:null;
 return <section className="panel"><h2>Verkstad – intern debiteringsgrad</h2>
 {state.query!==query?<p>Hämtar verkstadstid…</p>:state.error?<p role="alert">Verkstadstiden kunde inte hämtas.</p>:!data?.available?<p>Inget godkänt verkstadstidsunderlag i vald period.</p>:<>
 <div className="mini-kpi-grid"><div><span>Debiteringsgrad</span><strong>{data.billing_rate===null?'–':`${n(data.billing_rate)} %`}</strong></div><div><span>Internt debiterbar tid</span><strong>{n(data.billable_hours)} h</strong></div><div><span>Ej debiterbar – KST 40</span><strong>{n(data.non_billable_hours)} h</strong></div><div><span>Frånvaro, exkluderad</span><strong>{n(data.absence_hours)} h</strong></div></div>
 <p>Andra kostnadsställen räknas som internt debiterbara. Egen verkstad (40) är ej debiterbar. Debiteringsgrad = debiterbar tid / arbetstid exklusive frånvaro. Det är inte verifierad kundfakturering och ändrar inga kostnader. Visar godkända verkstadstidsimporter för perioden, oberoende av fordons- och verksamhetsgruppsfilter.</p>
 <div className="table-wrap"><table><thead><tr><th>Person i underlaget</th><th>Debiterbar tid</th><th>Egen verkstad</th><th>Frånvaro</th><th>Arbetstid</th><th>Debiteringsgrad</th></tr></thead><tbody>{data.people.map(p=><tr key={p.name}><td>{p.name}</td><td>{n(p.billable_hours)} h</td><td>{n(p.non_billable_hours)} h</td><td>{n(p.absence_hours)} h</td><td>{n(p.work_hours)} h</td><td>{p.billing_rate===null?'–':`${n(p.billing_rate)} %`}</td></tr>)}</tbody></table></div>
 <h3>Arbetstid per mottagande kostnadsställe</h3><table><thead><tr><th>Kostnadsställe</th><th>Timmar</th><th>Andel av arbetstiden</th></tr></thead><tbody>{Array.from(new Set(data.centers.map(c=>c.code))).sort().map(code=>{const hours=data.centers.filter(c=>c.code===code).reduce((s,c)=>s+Number(c.hours),0);return <tr key={code}><td>{code}{code==='40'?' – egen verkstad, ej debiterbar':''}</td><td>{n(hours)} h</td><td>{data.work_hours?`${n(100*hours/data.work_hours)} %`:'–'}</td></tr>;})}</tbody></table>
 {data.review_rows>0&&<p role="alert">{data.review_rows} rader behöver granskas och ingår inte i graden.</p>}
 {data.duplicate_rows>0&&<p>{data.duplicate_rows} identiska återimporterade radförekomster räknas endast en gång.</p>}
 </>}
 </section>;
}
