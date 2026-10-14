'use client';
import {useEffect,useState} from 'react';
import {parseMonthPeriod,fiscalMonths,monthLabels} from '@/lib/kpi/period';
type Row={id:string;label:string;section:string;unit:string;current:number|null;previous:number|null;difference:number|null;change_pct:number|null;status:string;reason:string|null};
type Report={rows:Row[];year:number;previous_year:number;months:number[]};
const number=new Intl.NumberFormat('sv-SE',{maximumFractionDigits:1});
const money=new Intl.NumberFormat('sv-SE',{maximumFractionDigits:0});
function format(v:number|null,unit:string){return v==null?'Underlag saknas':(unit==='kr'?money:number).format(v)+(unit?' '+unit:'');}
function change(r:Row){if(r.difference==null)return r.reason??'Jämförelse saknas';const delta=(r.difference>0?'+':'')+format(r.difference,r.unit==='%'?'procentenheter':r.unit);return delta+(r.unit!=='%'&&r.change_pct!=null?` (${r.change_pct>0?'+':''}${number.format(r.change_pct)} %)`:'');}
export function KpiYearComparison({query}:{query:string}){
 const [search,setSearch]=useState('');
 const [section,setSection]=useState('Ekonomi'),[attempt,setAttempt]=useState(0);
 const [reports,setReports]=useState<{query:string;parts:Record<string,Report>}>({query:'',parts:{}});
 const [error,setError]=useState<{query:string;part:string}|null>(null);
 const part=section==='Interna intäkter'?'internal':section==='Faktureringsbalans'?'billing':section==='Verkstad'?'workshop':'overview';
 const current=reports.query===query?reports.parts:{};
 const data=current[part];
 useEffect(()=>{if(data)return;const controller=new AbortController();let active=true;
  const signal=AbortSignal.any([controller.signal,AbortSignal.timeout(55000)]);
  async function load(){
   let r=await fetch('/api/kpi/year-comparison?'+query+'&part='+part,{signal});
   if([503,504].includes(r.status))r=await fetch('/api/kpi/year-comparison?'+query+'&part='+part,{signal});
   if(!r.ok)throw Error();return await r.json() as Report;
  }
  load().then(result=>{if(active){setReports(old=>({query,parts:{...(old.query===query?old.parts:{}),[part]:result}}));setError(null);}})
   .catch(()=>{if(active)setError({query,part});});
  return()=>{active=false;controller.abort();};
 },[query,part,data,attempt]);
 const p=new URLSearchParams(query),period=parseMonthPeriod(p.get('fiscal_year')??undefined,p.get('months')??undefined);
 const label=period.months.map(m=>monthLabels[fiscalMonths.indexOf(m)]).join(', ');
 const sections=['Ekonomi','Kostnader','Drift & personal','Overhead','Ekonomiska enheter','Verksamhetsgrupper','Månader','Underlag','Interna intäkter','Faktureringsbalans',...(p.get('cost_center')==='40'&&!['group','unit','vehicle','project','category','kind','source','date_from','date_to'].some(k=>p.has(k))?['Verkstad']:[])];
 const rows=data?.rows.filter(r=>r.section===section&&r.label.toLocaleLowerCase('sv').includes(search.toLocaleLowerCase('sv')))??[];
 return <section className="panel year-comparison" aria-labelledby="year-comparison-title">
  <div className="panel-head"><div><span className="section-kicker">{label} · samma månader och filter</span><h2 id="year-comparison-title">Samma period föregående år</h2></div><label>Jämför <select value={section} onChange={e=>{setSection(e.target.value);setSearch('');}}>{sections.map(s=><option key={s}>{s}</option>)}</select></label></div>
  {section==='Ekonomiska enheter'&&<label>Sök enhet eller nyckeltal <input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Till exempel Trading eller timmar"/></label>}
  <p>{period.fiscalYear}/{period.fiscalYear+1} jämförs med {period.fiscalYear-1}/{period.fiscalYear}. Belopp visas exklusive moms. Procenttal jämförs i procentenheter.</p>
  {!data?(error?.query===query&&error.part===part?<p role="alert">Jämförelsen kunde inte hämtas. <button className="secondary" onClick={()=>{setError(null);setAttempt(v=>v+1);}}>Försök igen</button></p>:<p role="status">Hämtar samma period föregående år…</p>):<div className="table-wrap"><table><thead><tr><th>Nyckeltal</th><th>Vald period</th><th>Föregående år</th><th>Förändring</th></tr></thead><tbody>{rows.map(r=><tr key={r.id}><th scope="row">{r.label}</th><td>{format(r.current,r.unit)}</td><td>{format(r.previous,r.unit)}</td><td>{change(r)}{r.status==='zero_base'&&<small>Procentuell förändring saknar bas när fjolåret är 0.</small>}</td></tr>)}{!rows.length&&<tr><td colSpan={4}>Inga jämförbara objekt i detta urval.</td></tr>}</tbody></table></div>}
  {section==='Faktureringsbalans'&&<p>Faktureringsbalansen följer månader, kostnadsställe, grupp, ekonomisk enhet, fordon och projekt. Den visar registrerat faktureringsförsprång, inte betalningsdagar.</p>}
  <p className="muted-line">Saknad historik visas som ”Underlag saknas”. Ofullständiga månader eller tidsunderlag ger ingen säker förändringsprocent. Interna intäkter ingår redan i KPI-omsättningen.</p>
  <style jsx>{`.year-comparison .panel-head{flex-wrap:wrap}.year-comparison label{display:flex;gap:8px;align-items:center;font-size:13px}.year-comparison input{padding:8px;border:1px solid #d1d5db;border-radius:6px;min-width:240px}.year-comparison select{padding:8px;border:1px solid #d1d5db;border-radius:6px;max-width:100%;background:white}.year-comparison th,.year-comparison td{vertical-align:top}.year-comparison td{font-variant-numeric:tabular-nums}.year-comparison td small{display:block;color:#64748b;font-size:11px;max-width:240px}.year-comparison .table-wrap{max-height:560px;overflow:auto}.year-comparison thead{position:sticky;top:0;background:white;z-index:1}`}</style>
 </section>;
}
