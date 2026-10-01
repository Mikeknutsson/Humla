"use client";
import {useEffect,useState} from 'react';
import {DatedRuleManager,type RuleData,type RuleKind} from './dated-rule-manager';
import {ExistingUnitEditor} from './existing-unit-editor';
import {CompoundUnitBuilder} from './compound-unit-builder';
import dynamic from 'next/dynamic';
const LegacyControlPanel=dynamic(()=>import('./kpi-legacy-control-panel'),{loading:()=> <p role="status">Öppnar granskning…</p>});
const sections=[
 {key:'project_vehicle',title:'Projekt → fordon',description:'Koppla NEXT-projektnummer till rätt registreringsnummer.'},
 {key:'units',title:'Ekonomiska enheter',description:'Samla huvudfordon, släp, projekt och personreferenser.'},
 {key:'project_group',title:'Verksamhetsgrupper',description:'Placera projekt i Stena, Kranbilar, Fjärr och övriga grupper.'},
 {key:'cost',title:'Konton & kostnader',description:'Välj kategori och om kostnaden ska ingå i fordonsresultatet.'},
 {key:'article',title:'Workify-intäkter',description:'Styr artikelns intäkt till projekt eller utförande fordon.'},
 {key:'depreciation',title:'Avskrivningar',description:'Registrera månadskostnad och giltighetsperiod.'},
 {key:'review',title:'Granskning & integrationer',description:'Hantera NEXT, bränsleavvikelser och se integrationsstatus.'}
] as const;
type Section=typeof sections[number]['key'];
type Status={reviews:Array<{id:string}>;connections:Array<{connector_type:string;status:string;last_success_at:string|null;last_error_at:string|null}>};
export function KpiControlWorkspace({rules,candidates}:{rules:RuleData;candidates:Array<{id:string;name:string;registration:string|null;projects:string[]}>}){
 const [section,setSection]=useState<Section|null>(null),[status,setStatus]=useState<Status|null>(null),[error,setError]=useState('');
 useEffect(()=>{const controller=new AbortController();fetch('/api/kpi/control-panel',{cache:'no-store',signal:controller.signal}).then(async r=>{const j=await r.json();if(!r.ok)throw Error(j.error);setStatus(j)}).catch(e=>{if(e.name!=='AbortError')setError(e.message)});return()=>controller.abort()},[]);
 return <div className="kpi-app control-workspace"><header className="control-header"><a className="brand" href="/kpi">Humla <small>Dashboard</small></a><nav aria-label="Dashboard"><a href="/kpi?view=kpi">KPI</a><a href="/kpi?view=import">Dataimport</a><a href="/kpi?view=review">Granskning</a></nav></header><main className="control-content"><div className="eyebrow">INSTÄLLNINGAR & KOPPLINGAR</div><h1>Kontrollpanel</h1><p>Arbeta här i Dashboard. Kopplingar och regler sparas i Humla Hub och används från det datum du väljer.</p>
 <section className="control-guide"><strong>Välj vad du vill koppla → sök objektet → ange giltig från → spara.</strong><span>Osäkra kopplingar lämnas för granskning. Historiska regelperioder finns kvar.</span></section>
 <div className="control-grid">{sections.map(s=><button key={s.key} className={'control-card'+(section===s.key?' selected':'')} aria-pressed={section===s.key} onClick={()=>setSection(s.key)}><strong>{s.title}</strong><span>{s.description}</span><b>{s.key==='review'?(status?`${status.reviews.length} öppna ärenden (högst 500)`:'Öppna granskning'):s.key==='units'?'Skapa och hantera enheter':'Hantera kopplingar'} →</b></button>)}</div>
 {section&&<section className="control-editor" aria-label={sections.find(s=>s.key===section)?.title}><div className="control-section-head"><h2>{sections.find(s=>s.key===section)?.title}</h2><button className="secondary" onClick={()=>setSection(null)}>Stäng</button></div>
 {section==='units'?<><ExistingUnitEditor/><CompoundUnitBuilder from={new Date().toLocaleDateString('sv-SE',{timeZone:'Europe/Stockholm'})}/><a className="secondary" href="/kpi?view=units">Visa befintliga enheter och redigera kopplingar →</a></>:section==='review'?<LegacyControlPanel/>:<DatedRuleManager key={section} data={rules} candidates={candidates} initialKind={section as RuleKind}/>}
 </section>}
 <section className="panel"><h2>Anslutningar i Humla Hub</h2><p>Senaste lyckade hämtning är en tidsstämpel, inte en garanti för komplett data.</p>{error&&<p role="alert">Status kunde inte hämtas: {error}</p>}{!status&&!error&&<p role="status">Hämtar integrationsstatus…</p>}{status&&<div className="table-wrap"><table><thead><tr><th>Källa</th><th>Status</th><th>Senast lyckad hämtning</th><th>Senaste fel</th></tr></thead><tbody>{status.connections.map((c,i)=><tr key={c.connector_type+':'+i}><td>{c.connector_type}</td><td>{c.status}</td><td>{c.last_success_at?new Date(c.last_success_at).toLocaleString('sv-SE',{timeZone:'Europe/Stockholm'}):'Ingen verifierad hämtning'}</td><td>{c.last_error_at?new Date(c.last_error_at).toLocaleString('sv-SE',{timeZone:'Europe/Stockholm'}):'–'}</td></tr>)}</tbody></table></div>}</section></main></div>
}
