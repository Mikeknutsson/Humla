"use client";
import {useEffect,useState} from 'react';
import {DatedRuleManager,type RuleData,type RuleKind} from './dated-rule-manager';
import dynamic from 'next/dynamic';
const ExistingUnitEditor=dynamic(()=>import('./existing-unit-editor').then(m=>m.ExistingUnitEditor));
const CompoundUnitBuilder=dynamic(()=>import('./compound-unit-builder').then(m=>m.CompoundUnitBuilder));
const LegacyControlPanel=dynamic(()=>import('./kpi-legacy-control-panel'),{loading:()=> <p role="status">Öppnar granskning…</p>});
const UnifiedWorkbench=dynamic(()=>import('./kpi-unified-workbench').then(m=>m.KpiUnifiedWorkbench),{loading:()=> <p role="status">Öppnar gemensam arbetsyta…</p>});
const MatchWorkbench=dynamic(()=>import('./kpi-match-workbench').then(m=>m.KpiMatchWorkbench),{loading:()=> <p role="status">Öppnar matchningskö…</p>});
const sections=[
 {key:'matching',title:'Matcha & fördela',description:'Sök, kryssa eller dra ofördelade poster. Fördela gemensamma kostnadsprojekt jämnt mellan enheter.'},
 {key:'project_vehicle',title:'Projekt → fordon',description:'Koppla NEXT-projektnummer till rätt registreringsnummer.'},
 {key:'units',title:'Ekonomiska enheter',description:'Samla bil, släp, projekt och person. Välj grupp för hela enheten.'},
 {key:'project_group',title:'Verksamhetsgrupper',description:'Placera projekt i Stena, Kranbilar, Fjärr och övriga grupper.'},
 {key:'cost',title:'Konton & kostnader',description:'Välj kategori och om kostnaden ska ingå i fordonsresultatet.'},
 {key:'article',title:'Workify-intäkter',description:'Styr artikelns intäkt till projekt eller utförande fordon.'},
 {key:'depreciation',title:'Avskrivningar',description:'Registrera månadskostnad och giltighetsperiod.'},
 {key:'review',title:'Granskning & integrationer',description:'Hantera NEXT, bränsleavvikelser och se integrationsstatus.'}
] as const;
export type Section=typeof sections[number]['key'];
type Status={reviews:Array<{id:string}>;connections:Array<{connector_type:string;status:string;last_success_at:string|null;last_error_at:string|null}>};
export function KpiControlWorkspace({rules,candidates,initialSection='matching'}:{rules:RuleData;candidates:Array<{id:string;name:string;registration:string|null;projects:string[]}>;initialSection?:Section}){
 const [section,setSection]=useState<Section|null>(initialSection),[status,setStatus]=useState<Status|null>(null),[error,setError]=useState(''),[legacyOpen,setLegacyOpen]=useState(false),[dirty,setDirty]=useState(false);
 useEffect(()=>{const controller=new AbortController();fetch('/api/kpi/control-panel',{cache:'no-store',signal:controller.signal}).then(async r=>{const j=await r.json();if(!r.ok)throw Error(j.error);setStatus(j)}).catch(e=>{if(e.name!=='AbortError')setError(e.message)});return()=>controller.abort()},[]);
 return <div className="kpi-app control-workspace"><header className="control-header"><a className="brand" href="/kpi">Humla <small>Dashboard</small></a><nav aria-label="Dashboard"><a href="/kpi?view=kpi">KPI</a><a href="/kpi?view=import">Dataimport</a><a href="/kpi?view=review">Granskning</a></nav></header><main className="control-content" style={{maxWidth:'none'}}><div className="eyebrow">INSTÄLLNINGAR & KOPPLINGAR</div><h1>Kontrollpanel</h1><p>Arbeta här i Dashboard. Kopplingar och regler sparas i Humla Hub och används från det datum du väljer.</p>
 <section className="control-guide"><strong>Välj vad du vill koppla → sök objektet → ange giltig från → spara.</strong><span>Osäkra kopplingar lämnas för granskning. Historiska regelperioder finns kvar.</span></section>
 <details open={section!=='matching'}><summary>Befintliga specialverktyg och granskning</summary><div className="control-grid">{sections.map(s=><button key={s.key} className={'control-card'+(section===s.key?' selected':'')} aria-pressed={section===s.key} disabled={dirty} onClick={()=>{setSection(s.key);const url=new URL(window.location.href);url.searchParams.set("section",s.key);window.history.replaceState(null,"",url);}}><strong>{s.title}</strong><span>{s.description}</span><b>{s.key==='review'?(status?`${status.reviews.length} öppna ärenden (högst 500)`:'Öppna granskning'):s.key==='units'?'Skapa och hantera enheter':'Hantera kopplingar'} →</b></button>)}</div></details>
 {section&&<section className="control-editor" aria-label={sections.find(s=>s.key===section)?.title}><div className="control-section-head"><h2>{sections.find(s=>s.key===section)?.title}</h2><button className="secondary" disabled={dirty} onClick={()=>setSection(null)}>Stäng</button></div>
 {section==='matching'?<><UnifiedWorkbench onDirtyChange={setDirty}/><details onToggle={e=>setLegacyOpen(e.currentTarget.open)}><summary>Öppna tidigare matchningsverktyg</summary>{legacyOpen&&<MatchWorkbench/>}</details></>:section==='units'?<><ExistingUnitEditor/><CompoundUnitBuilder from={new Date().toLocaleDateString('sv-SE',{timeZone:'Europe/Stockholm'})}/><a className="secondary" href="/kpi?view=units">Visa enheternas uppföljning →</a></>:section==='review'?<LegacyControlPanel/>:<DatedRuleManager key={section} data={rules} candidates={candidates} initialKind={section as RuleKind}/>}
 </section>}
 <section className="panel"><h2>Anslutningar i Humla Hub</h2><p>Senaste lyckade hämtning är en tidsstämpel, inte en garanti för komplett data.</p>{error&&<p role="alert">Status kunde inte hämtas: {error}</p>}{!status&&!error&&<p role="status">Hämtar integrationsstatus…</p>}{status&&<div className="table-wrap"><table><thead><tr><th>Källa</th><th>Status</th><th>Senast lyckad hämtning</th><th>Senaste fel</th></tr></thead><tbody>{status.connections.map((c,i)=><tr key={c.connector_type+':'+i}><td>{c.connector_type}</td><td>{c.status}</td><td>{c.last_success_at?new Date(c.last_success_at).toLocaleString('sv-SE',{timeZone:'Europe/Stockholm'}):'Ingen verifierad hämtning'}</td><td>{c.last_error_at?new Date(c.last_error_at).toLocaleString('sv-SE',{timeZone:'Europe/Stockholm'}):'–'}</td></tr>)}</tbody></table></div>}</section></main></div>
}
