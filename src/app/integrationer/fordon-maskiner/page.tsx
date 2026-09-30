"use client";
import {useState} from "react";
import Link from "next/link";
export default function Page(){
 const [busy,setBusy]=useState(false),[result,setResult]=useState(""),[details,setDetails]=useState("");
 async function run(action:string){setBusy(true);setResult("");try{
 const r=await fetch("/api/integrationer/fordonskontrollen",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({action})});
 const j=await r.json();setDetails(JSON.stringify(j,null,2));setResult(r.ok?"Synkronisering utförd – kontrollera resultatet nedan.":j.error||"Synkronisering misslyckades");
 }catch(e){setResult(String(e));}finally{setBusy(false);}}
 return <><Link href="/integrationer" className="backlink">← Alla integrationsområden</Link>
 <header className="topbar"><div><span className="eyebrow">HUM LA HUB</span><h1>Fordonskontrollen</h1><p>Synkronisera fordon och fordonsnummer till gemensamma Humla-identiteter.</p></div></header>
 <section className="section"><h2>Identifieringsunderlag</h2><p>Hämta fordon först. Fordonskontrollens externa ID och registreringsnummer behålls som källidentiteter. NEXT-projektnummer kopplas till samma Humla-enhet när kopplingen är verifierad.</p>
 <button disabled={busy} onClick={()=>run("vehicles")}>{busy?"Synkroniserar...":"Hämta fordon från Fordonskontrollen"}</button>
 <p><Link href="/integrationer/fordonskontrollen/reparationskostnader">Granska reparationskostnader från NEXT →</Link></p>
 <button disabled={busy} onClick={()=>run("units")}>Hämta maskiner/enheter</button>
 {result&&<p role="status">{result}</p>}{details&&<pre style={{whiteSpace:"pre-wrap",overflowWrap:"anywhere"}}>{details}</pre>}</section></>;
}