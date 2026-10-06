'use client';
import {useEffect,useRef,useState} from 'react';
import Link from 'next/link';
import {fiscalMonths,monthLabels,parseMonthPeriod,stockholmToday} from '@/lib/kpi/period';
import {metricStatus,monthlyValue,type MonthlyTransportReport} from '@/lib/kpi/monthly-report';
import styles from './kpi-monthly-report.module.css';
export function KpiMonthlyReport({query}:{query:string}){
 const initial=new URLSearchParams(query),period=parseMonthPeriod(initial.get('fiscal_year')??undefined,initial.get('months')??undefined);
 const today=stockholmToday(),previousMonth=today.month===1?12:today.month-1;
 const defaultMonth=period.months.length===1?period.months[0]:period.fiscalYear===period.currentYear&&previousMonth!==8?previousMonth:8;
 const defaultYear=period.months.length!==1&&period.fiscalYear===period.currentYear&&today.month===9?period.fiscalYear-1:period.fiscalYear;
 const [year,setYear]=useState(defaultYear),[month,setMonth]=useState(defaultMonth),[center,setCenter]=useState(initial.get('cost_center')||'30');
 const [loaded,setLoaded]=useState<{query:string;data:MonthlyTransportReport}|null>(null),[error,setError]=useState(''),[busy,setBusy]=useState(false),[exporting,setExporting]=useState(false),[retry,setRetry]=useState(0);
 const cache=useRef(new Map<string,MonthlyTransportReport>());
 const scope=new URLSearchParams({fiscal_year:String(year),report_month:String(month),cost_center:center});
 for(const k of ['group','unit','vehicle','project']){const value=initial.get(k);if(value)scope.set(k,value);}
 const reportQuery=scope.toString();
 const report=loaded?.query===reportQuery?loaded.data:null;
 useEffect(()=>{
  const controller=new AbortController();let ignore=false;
  async function load(){await Promise.resolve();if(ignore)return;setError('');
  const cached=cache.current.get(reportQuery);if(cached){setLoaded({query:reportQuery,data:cached});setBusy(false);return;}
  setLoaded(null);setBusy(true);
  fetch('/api/kpi/monthly-report?'+reportQuery,{signal:controller.signal,cache:'no-store'}).then(async response=>{const data=await response.json();if(!response.ok)throw Error(data.error);if(!ignore){if(cache.current.size>=24)cache.current.delete(cache.current.keys().next().value!);cache.current.set(reportQuery,data);setLoaded({query:reportQuery,data});}}).catch(e=>{if(!ignore)setError(e instanceof Error?e.message:'Rapporten kunde inte hämtas.');}).finally(()=>{if(!ignore)setBusy(false);});
  }
  void load();return()=>{ignore=true;controller.abort();};
 },[reportQuery,retry]);
 async function download(format:'pdf'|'xlsx'){
  setExporting(true);setError('');try{const response=await fetch('/api/kpi/monthly-report?'+reportQuery+'&format='+format);if(!response.ok){const data=await response.json();throw Error(data.error);}
  const url=URL.createObjectURL(await response.blob()),a=document.createElement('a');a.href=url;a.download=`humla-nyckeltal-transport-${report!.period.from.slice(0,7)}.${format}`;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
  }catch(e){setError(e instanceof Error?e.message:'Exporten misslyckades.');}finally{setExporting(false);}
 }
 function change(nextYear:number,nextMonth:number,nextCenter:string){setYear(nextYear);setMonth(nextMonth);setCenter(nextCenter);const p=new URLSearchParams(query);p.set('view','monthly');p.set('fiscal_year',String(nextYear));p.set('months',String(nextMonth));p.set('cost_center',nextCenter);p.delete('from');p.delete('to');window.history.replaceState(null,'','/kpi?'+p);void fetch('/api/kpi/selection',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({query:p.toString()})}).catch(()=>{});}
 const centers=report?.cost_centers?.length?report.cost_centers:[{code:'10',name:'Entreprenad'},{code:'20',name:'Sortergården'},{code:'30',name:'Transport'},{code:'40',name:'Verkstad'},{code:'50',name:'Fastigheter'},{code:'60',name:'Skåne'},{code:'90',name:'Övrigt'}];
 const years=Array.from(new Set([year,period.currentYear,...Array.from({length:6},(_,i)=>period.currentYear-i)])).sort((a,b)=>b-a);
 return <section aria-busy={busy}>
 <span className="section-kicker">Månadsleverans enligt Nyckeltal Transport</span><h2>Välj månad och hämta rapporten</h2><p>Sex nyckeltal från presentationen, tillsammans med verksamhetsårets YTD och fordonsunderlag. Rapporten använder Hubben senast synkade data.</p>
 <div className={styles.toolbar}><label>Verksamhetsår<select value={year} onChange={e=>change(Number(e.target.value),month,center)}>{years.map(y=><option key={y} value={y}>{y}/{y+1}</option>)}</select></label><label>Månad<select value={month} onChange={e=>change(year,Number(e.target.value),center)}>{fiscalMonths.map((m,i)=><option value={m} key={m}>{monthLabels[i]} {m>=9?year:year+1}</option>)}</select></label><label>Kostnadsställe<select value={center} onChange={e=>change(year,month,e.target.value)}>{!centers.some(c=>c.code===center)&&<option value={center}>{center} (samlat urval)</option>}{centers.map(c=><option key={c.code} value={c.code}>{c.code} – {c.name}</option>)}</select></label><button className="secondary" onClick={()=>{cache.current.delete(reportQuery);setRetry(v=>v+1);}}>Hämta underlag igen</button></div>
 <div className={styles.actions}><button className="primary" disabled={!report||busy||exporting} onClick={()=>download('pdf')}>{exporting?'Skapar rapport…':'Hämta månadsrapport (PDF)'}</button><button className="secondary" disabled={!report||busy||exporting} onClick={()=>download('xlsx')}>Hämta Excel med underlag</button></div>
 {error&&<p role="alert">{error}</p>}{busy&&<p role="status">Hämtar månadsrapport från Hubben…</p>}
 {report&&<><p>{report.tenant} · {report.period.from} – {report.period.to} · YTD {report.period.ytd_from} – {report.period.to}<br/><small>Underlag synkat {new Date(report.synced_at).toLocaleString('sv-SE',{timeZone:'Europe/Stockholm'})}. Urval: {Object.entries(report.scope).map(([k,v])=>`${k}: ${v}`).join(' · ')}</small></p>
 <div className={styles.notice}>Alla registrerade intäkter räknas som fakturerade enligt din rapportregel. Originalstatusen ändras inte. Omsättningen följer artikeldatum och samma intäktsurval som KPI-vyn. Resultatet är preliminärt med NEXT-kostnader och TransPA-personalschablon. Saknad debiterbar tid och osäker dieselavgränsning visas som saknat underlag.</div>
 <div className={styles.grid}>{report.month.metrics.map((metric,i)=><article className={styles.card} key={metric.key}><h3>{metric.label}</h3><div className={styles.values}><div>Månad<strong>{monthlyValue(metric.value,metric.unit)}</strong><small>{metricStatus[metric.status]}</small></div><div>YTD<strong>{monthlyValue(report.ytd.metrics[i].value,metric.unit)}</strong><small>{metricStatus[report.ytd.metrics[i].status]}</small></div></div><p>{metric.basis}</p></article>)}</div>
 <section className="panel"><h3>Kompletterande underlag – månad</h3><p>Registrerade intäkter: {monthlyValue(report.month.recorded_revenue,'kr')} · Utanför rapportens faktureringsregel: {monthlyValue(report.month.uninvoiced_revenue,'kr')}<br/>Bränsle totalt: {monthlyValue(report.month.fuel,'kr')} · Bränsleandel: {monthlyValue(report.month.fuel_share,'%')}<br/>Aktiva egna fordonsenheter: {report.month.active_vehicle_count} · Rapporterad TransPA-tid / kapacitet: {monthlyValue(report.indicators.reported_vehicle_utilization,'%')}</p><small>{report.indicators.definition}</small></section>
 <section className="panel"><h3>Fordonsenheter – månad</h3><p>Kostnader följer befintliga Hub-kopplingar. Fordonskostnader kan därför saknas även när intäkter finns. Excel innehåller även YTD per fordonsenhet.</p><div className={styles.table}><table><thead><tr><th>Enhet</th><th>Fakturerad omsättning</th><th>Registrerade intäkter</th><th>Kostnad</th><th>Bränsle</th><th>Underlag</th></tr></thead><tbody>{report.month.vehicles.map(v=><tr key={v.key}><td>{v.label}{v.hired?' (inhyrdas samlingsenhet)':''}</td><td>{monthlyValue(v.invoiced_revenue,'kr')}</td><td>{monthlyValue(v.recorded_revenue,'kr')}</td><td>{monthlyValue(v.cost,'kr')}</td><td>{monthlyValue(v.fuel,'kr')}</td><td><Link prefetch={false} href={'/kpi/analys?'+new URLSearchParams({fiscal_year:String(year),months:String(month),cost_center:center,...Object.fromEntries(Object.entries(report.scope).filter(([k])=>k!=='cost_center'&&k!=='vehicle')),vehicle:v.vehicle,level:'transaction',grain:'month'})}>Visa underlag</Link></td></tr>)}</tbody></table></div></section>
 </>}
 </section>;
}
