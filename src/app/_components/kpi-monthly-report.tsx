'use client';
import {useEffect,useRef,useState} from 'react';
import Link from 'next/link';
import {parseMonthPeriod,stockholmToday} from '@/lib/kpi/period';
import {monthlyValue,monthlyReportMetrics,monthlyComparisonSections,monthlyUnitComparisons,type MonthlyComparisonRow,type MonthlyTransportReport} from '@/lib/kpi/monthly-report';
import styles from './kpi-monthly-report.module.css';
export function KpiMonthlyReport({query}:{query:string}){
 const initial=new URLSearchParams(query),period=parseMonthPeriod(initial.get('fiscal_year')??undefined,initial.get('months')??undefined,new Date(),initial.get('period_mode')??undefined);
 const today=stockholmToday(),previousMonth=today.month===1?12:today.month-1;
 const defaultMonth=period.mode==='ytd'?period.currentMonth:period.months.length===1?period.months[0]:period.fiscalYear===period.currentYear&&previousMonth!==8?previousMonth:8;
 const defaultYear=period.mode!=='ytd'&&period.months.length!==1&&period.fiscalYear===period.currentYear&&today.month===9?period.fiscalYear-1:period.fiscalYear;
 const year=defaultYear,month=defaultMonth,center=initial.get('cost_center')||'30';
 const [loaded,setLoaded]=useState<{query:string;data:MonthlyTransportReport}|null>(null),[error,setError]=useState(''),[busy,setBusy]=useState(false),[retry,setRetry]=useState(0);
 const cache=useRef(new Map<string,MonthlyTransportReport>());
 const scope=new URLSearchParams({fiscal_year:String(year),report_month:String(month),cost_center:center});
 if(period.mode==='ytd'){scope.set('period_mode','ytd');scope.set('as_of',period.to!);}
 for(const k of ['group','unit','vehicle','project']){const value=initial.get(k);if(value)scope.set(k,value);}
 const reportQuery=scope.toString();
 const report=loaded?.query===reportQuery?loaded.data:null;
 useEffect(()=>{
  const controller=new AbortController();let ignore=false;
  async function load(){await Promise.resolve();if(ignore)return;setError('');
  const cached=cache.current.get(reportQuery);if(cached){setLoaded({query:reportQuery,data:cached});setBusy(false);return;}
  setLoaded(null);setBusy(true);
  fetch('/api/kpi/monthly-report?'+reportQuery,{signal:AbortSignal.any([controller.signal,AbortSignal.timeout(35000)]),cache:'no-store'}).then(async response=>{const data=await response.json();if(!response.ok)throw Error(data.error);if(!ignore){if(cache.current.size>=24)cache.current.delete(cache.current.keys().next().value!);cache.current.set(reportQuery,data);setLoaded({query:reportQuery,data});}}).catch(e=>{if(!ignore)setError(e instanceof Error?e.message:'Rapporten kunde inte hämtas.');}).finally(()=>{if(!ignore)setBusy(false);});
  }
  void load();return()=>{ignore=true;controller.abort();};
 },[reportQuery,retry]);
 function table(title:string,rows:MonthlyComparisonRow[]){return <div className={styles.table}><table aria-label={title}><thead><tr><th>Nyckeltal</th><th>Månad</th><th>YTD</th><th>Månad fg. år</th><th>YTD fg. år</th></tr></thead><tbody>{rows.map(row=><tr key={row.label}><td>{row.label}</td>{row.values.map((v,i)=><td key={i}>{monthlyValue(v,row.unit)}</td>)}</tr>)}</tbody></table></div>;}
 return <section aria-busy={busy}>
 {error&&<p role="alert">{error} <button className="secondary" onClick={()=>{cache.current.delete(reportQuery);setRetry(v=>v+1);}}>Försök igen</button></p>}{busy&&<p role="status">Hämtar månadsrapport från Hubben…</p>}
 {report&&<>
 <p>{report.period.from} – {report.period.to} · YTD från {report.period.ytd_from}.{report.previous&&<> Jämförelse: {report.previous.period.from} – {report.previous.period.to}, YTD från {report.previous.period.ytd_from}.</>}</p>
 {!!report.excluded_projects?.length&&<p>Utanför uppföljningen: {report.excluded_projects.map(p=>p.name).join(', ')}.</p>}
 {!report.previous_available&&<p>Underlag för jämförelseåret kunde inte hämtas. Saknade värden visas som underlag saknas.</p>}
 {report.reconciliation?.status==='needs_review'&&<p role="status">Intäkt och resultat är preliminära. <Link prefetch={false} href={'/kpi/workify-avstamning?'+new URLSearchParams({from:report.period.from,to:report.period.to,cost_center:center})}>Visa Workify-avstämning →</Link></p>}
 {!!report.month.next_time?.workshop_hours_without_cost_reference&&<p role="status">{monthlyValue(report.month.next_time.workshop_hours_without_cost_reference,'h')} verkstadstid saknar kopplad NEXT-verkstadsdebitering i vald månad. {report.month.next_time.workshop_estimated_repair_cost?<>Preliminär reparationskostnad: {monthlyValue(report.month.next_time.workshop_estimated_repair_cost,'kr')}. Schablonen ersätts när verklig debitering finns.</>:'Kostnaden inväntar debiteringsunderlag.'}</p>}
 {monthlyComparisonSections(report).map(section=><section className="panel" key={section.key}><h2>{section.title}</h2>{table(section.title,section.rows)}</section>)}
 <details className="panel"><summary>Definitioner och källunderlag</summary><p>Varje kolumn använder samma kostnadsställe och övriga filter. YTD till idag och en pågående månadsrapport slutar på dagens datum i svensk tid. Föregående år slutar på motsvarande datum. Avslutade månadsrapporter omfattar hela månader.</p><p>Arbetad tid samlar TransPA och godkänd NEXT-projekttid efter överlappskontroll på person och dag. Fordonsbeläggning och aggregerade fordonsbelopp per timme omfattar bara fordon med positiva timmar i respektive period. Projekttid utan fordonskoppling ingår i arbetad tid, men inte i fordonsbeläggning. Verkstadstid redovisas separat som Rep.</p>{monthlyReportMetrics(report).map(m=><p key={m.key}><strong>{m.label}:</strong> {m.basis}</p>)}<p>{report.month.next_time?.basis}</p><p>{report.month.fuel_sources?.basis}</p><p>{report.indicators.definition}</p></details>
 <details className="panel"><summary>NEXT-verkstadstid och reparationskostnad – vald månad</summary><p>Debiteringen nedan ingår redan i Service &amp; reparation. Befintlig NEXT-debitering räknas en gång. Godkänd preliminär löneschablon visas separat för tid som saknar debitering och ersätts när verkligt underlag finns.</p><div className={styles.table}><table><thead><tr><th>Projekt</th><th>Verkstadstid</th><th>Befintlig reparationsdebitering</th><th>Preliminär Rep-schablon</th></tr></thead><tbody>{report.month.next_time?.workshop_cost_references.map(r=><tr key={r.month_start+':'+r.project}><td>{r.project_id?<Link prefetch={false} href={'/kpi/projekt?'+new URLSearchParams({from:report.period.from,to:report.period.to,project:r.project_id})}>{r.project}</Link>:r.project}</td><td>{monthlyValue(r.hours,'h')}</td><td>{monthlyValue(r.posted_repair_debit,'kr')}</td><td>{monthlyValue(r.estimated_repair_cost,'kr')}</td></tr>)}</tbody></table></div></details>
 <details className="panel"><summary>Bränsleunderlag – vald månad</summary><div className={styles.table}><table><thead><tr><th>Datum</th><th>Källa</th><th>Fordon</th><th>Produkt / konto</th><th>Liter</th><th>Kostnad</th></tr></thead><tbody>{report.month.fuel_sources?.transactions.map(t=><tr key={t.source+':'+t.id}><td>{t.dt}</td><td>{t.source}</td><td>{t.vehicle??'Ej kopplat'}</td><td>{t.product}</td><td>{monthlyValue(t.liters,'l')}</td><td>{monthlyValue(t.amount,'kr')}</td></tr>)}</tbody></table></div></details>
 <section className="panel"><h2>Ekonomiska enheter</h2><p>Samma enheter och urval som i Enhetsuppföljningen. Öppna en enhet för jämförelsen.</p>{monthlyUnitComparisons(report).map(u=><details key={u.key}><summary>{u.label}</summary>{table(u.label,u.rows)}<Link prefetch={false} href={'/kpi/analys?'+new URLSearchParams({from:report.period.from,to:report.period.to,fiscal_year:String(year),months:String(month),cost_center:center,unit:u.key,level:'transaction'})}>Visa underlag för vald månad →</Link></details>)}</section>
 </>}
 </section>;
}
