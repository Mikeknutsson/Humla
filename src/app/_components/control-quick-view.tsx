"use client";
import {useEffect,useState} from "react";
export function ControlQuickView(){
 const [d,setD]=useState<any>(null),[error,setError]=useState("");
 useEffect(()=>{let active=true;fetch("/api/kpi/hub-fuel",{cache:"no-store"}).then(async r=>{const j=await r.json();if(!r.ok)throw Error(j.error||"Kunde inte läsa status");if(active)setD(j)}).catch(e=>{if(active)setError(e.message)});return()=>{active=false}},[]);
 return <section className="panel"><div className="panel-head"><div><span className="section-kicker">Datakvalitet · snabbvy</span><h2>Kontrollpanel</h2></div><a className="btn primary" href="/kpi/kontrollpanel">Öppna kontrollpanel →</a></div>
 <div className="mini-kpi-grid">
 <a href="/kpi/kontrollpanel"><span>B.Smart · prisavvikelser</span><strong>{d?.manualReviewCount??"–"}</strong><small>Spärrade transaktioner att granska</small></a>
 <a href="/kpi/kontrollpanel"><span>Spärrade belopp</span><strong>{d?.excludedSuspiciousCostSek==null?"–":Math.round(d.excludedSuspiciousCostSek).toLocaleString("sv-SE")+" kr"}</strong><small>Räknas inte in i KPI</small></a>
 <a href="/kpi/kontrollpanel"><span>B.Smart · synkstatus</span><strong>{d?.live?"Aktuell":d?"Kontrollera":"–"}</strong><small>{d?.lastConnectorSuccess?"Senast "+new Date(d.lastConnectorSuccess).toLocaleString("sv-SE"):"Inväntar anslutningsstatus"}</small></a>
 </div>
 {error&&<p className="muted">Status kunde inte läsas: {error}</p>}
 <p className="muted">Övriga importavvikelser hanteras under <a href="/kpi?view=review">Granskning & mappning</a>. Alla korrigeringar av B.Smart sker i kontrollpanelen.</p>
 </section>;
}