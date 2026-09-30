"use client";
import {useEffect,useState} from "react";
export default function FuelReview(){
 const [data,setData]=useState<any>(null),[selected,setSelected]=useState<any>(null),[amount,setAmount]=useState(""),[note,setNote]=useState(""),[message,setMessage]=useState("");
 async function load(){const r=await fetch("/api/kpi/hub-fuel",{cache:"no-store"});const j=await r.json();if(!r.ok)throw Error(j.error);setData(j);}
 useEffect(()=>{load().catch(e=>setMessage(e.message));},[]);
 async function save(status:string){
 if(!selected)return;setMessage("Sparar");
 const r=await fetch("/api/kpi/hub-fuel/review",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({id:selected.id,status,note,correctedCost:amount?Number(amount):null})});
 const j=await r.json();if(!r.ok){setMessage(j.error);return;}setSelected(null);setNote("");setAmount("");setMessage("Sparat");await load();
 }
 const rows=data?.transactions?.filter((x:any)=>x.costStatus==="manual_review")||[];
 return <main className="page"><header className="pagehead"><div><div className="eyebrow">HUMLA HUB</div><h1>Kontrollpanel</h1><p>Avvikelser från B.Smart. Originalbelopp ändras aldrig.</p></div></header>
 <section className="metrics"><div className="metric"><span>Att granska</span><strong>{data?.manualReviewCount??"–"}</strong></div><div className="metric"><span>Spärrade belopp</span><strong>{data?.excludedSuspiciousCostSek?.toLocaleString("sv-SE")??"–"} kr</strong></div></section>
 <div className="panel"><h2>B.Smart – prisavvikelser</h2><div className="tablewrap"><table><thead><tr><th>Datum</th><th>Fordon</th><th>Liter</th><th>Originalbelopp</th><th>Orsak</th><th></th></tr></thead><tbody>{rows.map((x:any)=><tr key={x.id}><td>{x.occurredAt}</td><td>{x.registration}</td><td>{x.liters}</td><td>{x.rawCostSek}</td><td>{x.reviewReason}</td><td><button className="btn" onClick={()=>{setSelected(x);setAmount("");setNote("");}}>Granska</button></td></tr>)}</tbody></table></div></div>
 {selected&&<section className="panel"><h2>Granska tankning</h2><p>{selected.registration} · {selected.liters} liter · original {selected.rawCostSek} kr</p><label>Korrigerad totalkostnad (kr) <input type="number" min="0.01" step="0.01" value={amount} onChange={e=>setAmount(e.target.value)}/></label><label>Motivering <textarea value={note} onChange={e=>setNote(e.target.value)}/></label><div><button className="btn primary" disabled={!amount||note.trim().length<3} onClick={()=>save("approved")}>Godkänn korrigerat pris</button><button className="btn" disabled={note.trim().length<3} onClick={()=>save("rejected")}>Exkludera</button><button className="btn" onClick={()=>setSelected(null)}>Avbryt</button></div></section>}
 <p role="status">{message}</p></main>;
}