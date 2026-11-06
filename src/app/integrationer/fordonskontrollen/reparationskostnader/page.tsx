"use client";
import {useEffect,useState} from "react";
type Row={financialScope?:{published:boolean;reason:string}|null;id:string;external_vehicle_id:string;vehicle?:{registration:string;name:string}|null;occurred_on:string;amount:number;account:string;description:string|null;status:string;external_reference:string;error_message:string|null};
export default function RepairOutbox(){
 const [rows,setRows]=useState<Row[]>([]),[picked,setPicked]=useState<string[]>([]),[error,setError]=useState(""),[busy,setBusy]=useState(false);
 async function load(){const r=await fetch("/api/integrationer/fordonskontrollen/reparationskostnader",{cache:"no-store"});const j=await r.json();if(!r.ok)throw Error(j.error);setRows(j.rows);}
 useEffect(()=>{let active=true;fetch("/api/integrationer/fordonskontrollen/reparationskostnader",{cache:"no-store"}).then(async response=>{const body=await response.json();if(!response.ok)throw Error(body.error);if(active)setRows(body.rows);}).catch(e=>{if(active)setError(e.message);});return()=>{active=false;};},[]);
 async function change(status:"approved"|"excluded"){
  if(!picked.length)return;
  setBusy(true);setError("");
  let updated=0;
  try{
   for(let i=0;i<picked.length;i+=100){
    const ids=picked.slice(i,i+100);
    const r=await fetch("/api/integrationer/fordonskontrollen/reparationskostnader",{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({ids,status})});
    const j=await r.json();
    if(!r.ok)throw new Error(j.error||"Kunde inte uppdatera");
    updated+=j.updated;
    setError(updated+" av "+picked.length+" rader behandlade.");
   }
   setPicked([]);
   await load();
   setError(updated+" rader uppdaterade. Godkännande skickar inte kostnader till Fordonskontrollen.");
  }catch(e){
   setError((e instanceof Error?e.message:"Kunde inte spara")+" · "+updated+" rader uppdaterades. Ladda om och kontrollera innan nytt försök.");
   await load().catch(()=>{});
  }finally{setBusy(false)}
 }
 return <main className="page" style={{padding:24}}><h1>Fordonskontrollen – reparationskostnader</h1><p>NEXT-kostnader med entydig fordonskoppling. Granska innan återföring. Skriv-API för kostnader är ännu inte verifierat; godkännande skickar inte data externt.</p><p>Historiska poster utan aktuell källkoppling kan inte godkännas eller exporteras. Här visas högst 500 transaktioner åt gången. Välj alla omfattar endast dessa visade rader.</p><p>{rows.filter(r=>r.status==="pending_review"&&r.financialScope?.published).length} väntar på granskning · {rows.filter(r=>r.status==="approved"&&r.financialScope?.published).length} godkända</p>{error&&<p role="status">{error}</p>}<p><a href="/api/integrationer/fordonskontrollen/reparationskostnader/export">Exportera godkända kostnader (CSV)</a></p><button disabled={busy||!rows.some(r=>r.status==="pending_review"&&r.financialScope?.published)} onClick={()=>setPicked(rows.filter(r=>r.status==="pending_review"&&r.financialScope?.published).map(r=>r.id))}>Välj alla väntande (visade)</button> <button disabled={!picked.length} onClick={()=>setPicked([])}>Avmarkera alla</button> <button disabled={busy||!picked.length||picked.some(id=>!rows.find(r=>r.id===id)?.financialScope?.published)} onClick={()=>change("approved")}>Godkänn markerade</button> <button disabled={busy||!picked.length} onClick={()=>change("excluded")}>Undanta markerade</button><div style={{overflowX:"auto"}}><table><thead><tr><th>Välj</th><th>Datum</th><th>Registreringsnummer</th><th>Fordonsbeskrivning</th><th>Fordonskontrollen-ID</th><th>Konto</th><th>Beskrivning</th><th>Belopp</th><th>Status</th></tr></thead><tbody>{rows.map(r=><tr key={r.id}><td><input type="checkbox" disabled={r.status!=="pending_review"} checked={picked.includes(r.id)} onChange={e=>setPicked(e.target.checked?[...picked,r.id]:picked.filter(x=>x!==r.id))}/></td><td>{r.occurred_on}</td><td>{r.vehicle?.registration||"–"}</td><td>{r.vehicle?.name||"–"}</td><td>{r.external_vehicle_id}</td><td>{r.account}</td><td>{r.description}</td><td>{Number(r.amount).toLocaleString("sv-SE")} kr</td><td>{r.financialScope?.published?r.status:"Historik · saknar aktuell källkoppling"}</td></tr>)}</tbody></table></div></main>;
}
