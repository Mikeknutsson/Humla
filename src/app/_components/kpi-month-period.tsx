"use client";
import {useEffect,useRef,useState,useTransition} from 'react';
import {useRouter,useSearchParams} from 'next/navigation';
import {fiscalMonths,monthLabels,monthPeriodQuery,type MonthPeriod} from '@/lib/kpi/period';
import {KpiCostCenterFilter,KpiGroupFilter} from './kpi-cost-center-filter';
export function KpiMonthPeriod({period,costCenter,costCenters,groups=[],unitName}:{period:MonthPeriod;costCenter:string;costCenters:Array<{code:string;name:string}>;groups?:string[];unitName?:string}) {
 const router=useRouter();const params=useSearchParams();const [pending,start]=useTransition();
 const [draft,setDraft]=useState({base:period,value:period});const [queueState,setQueued]=useState(false);
 const selected=draft.base===period?draft.value:period;const queued=draft.base===period&&queueState;
 function setSelected(value:MonthPeriod){setDraft({base:period,value});}
 const monthTimer=useRef<ReturnType<typeof setTimeout>|null>(null);
 useEffect(()=>()=>{if(monthTimer.current!==null)clearTimeout(monthTimer.current);},[period]);
 function change(year:number,months:number[],center=costCenter) {
  if(monthTimer.current!==null){clearTimeout(monthTimer.current);monthTimer.current=null;}
  setQueued(false);setSelected({...period,fiscalYear:year,months});
  const p=new URLSearchParams(params);p.delete('from');p.delete('to');p.delete('date_from');p.delete('date_to');
  for(const [k,v] of new URLSearchParams(monthPeriodQuery({fiscalYear:year,months})))p.set(k,v);
  if(center)p.set('cost_center',center);else p.delete('cost_center');
  start(()=>router.push('/kpi?'+p,{scroll:false}));
 }
 // Batch rapid month toggles before starting an expensive Hub report.
 // Once a request starts, lock the period controls to avoid concurrent queries.
 function toggleMonth(month:number) {
  const months=selected.months.includes(month)?selected.months.filter(x=>x!==month):fiscalMonths.filter(x=>selected.months.includes(x)||x===month);
  if(!months.length)return;
  setSelected({...selected,months});setQueued(true);
  if(monthTimer.current!==null)clearTimeout(monthTimer.current);
  monthTimer.current=setTimeout(()=>change(selected.fiscalYear,months),350);
 }
 const years=Array.from({length:Math.max(5,period.currentYear-selected.fiscalYear+2)},(_,i)=>Math.max(period.currentYear+1,selected.fiscalYear)-i);
 const ytd=selected.fiscalYear<period.currentYear?fiscalMonths:selected.fiscalYear===period.currentYear?fiscalMonths.slice(0,fiscalMonths.indexOf(period.currentMonth)+1):[];
 function groupChange(value:string){const p=new URLSearchParams(params);if(value)p.set('group',value);else p.delete('group');for(const k of ['unit','vehicle','project','page'])p.delete(k);start(()=>router.push('/kpi?'+p));}
 function clearObject(){const p=new URLSearchParams(params);for(const k of ['unit','vehicle','project','category','kind','source','date_from','date_to'])p.delete(k);start(()=>router.push('/kpi?'+p));}
 return <section className="fiscal-period panel" aria-label="Periodväljare" aria-busy={pending||queued}>
  <div className="fiscal-controls"><label>Verksamhetsår<select aria-label="Verksamhetsår" value={selected.fiscalYear} disabled={pending} onChange={e=>change(Number(e.target.value),selected.months)}>{years.map(y=><option key={y} value={y}>{y}/{y+1}</option>)}</select></label>
  <KpiCostCenterFilter value={costCenter} options={costCenters} disabled={pending||queued} onChange={center=>change(selected.fiscalYear,selected.months,center)}/>
  <KpiGroupFilter value={params.get('group')??''} groups={groups} disabled={pending||queued} onChange={groupChange}/>
  <div className="fiscal-shortcuts"><button disabled={pending} onClick={()=>change(selected.fiscalYear,fiscalMonths)}>Hela verksamhetsåret</button><button disabled={pending||!ytd.length} title="Från september till och med aktuell månad" onClick={()=>change(selected.fiscalYear,ytd)}>YTD</button><button disabled={pending} onClick={()=>change(selected.fiscalYear,[selected.months.length===1?selected.months[0]:period.currentMonth])}>En månad</button></div></div>
  <span className="section-kicker">Period · klicka för att välja eller ta bort månader</span>
  <div className="fiscal-months">{fiscalMonths.map((m,i)=><button key={m} aria-pressed={selected.months.includes(m)} disabled={pending||(selected.months.length===1&&selected.months.includes(m))} onClick={()=>toggleMonth(m)}>{monthLabels[i]} {selected.months.includes(m)?'✓':''}</button>)}</div>
  <p aria-live="polite">{pending?'Hämtar från Humla Hub…':queued?'Förbereder månadsurval…':`${selected.months.map(m=>monthLabels[fiscalMonths.indexOf(m)]).join(' + ')} · ${selected.fiscalYear}/${selected.fiscalYear+1}`} · YTD omfattar hela månader till och med aktuell månad.</p>
  {(params.has('unit')||params.has('vehicle')||params.has('project')||params.has('category')||params.has('source'))&&<p>Detaljurval: {['unit','vehicle','project','category','source'].filter(k=>params.has(k)).map(k=>k==='unit'?`Enhet: ${unitName??'Vald ekonomisk enhet'}`:`${({vehicle:'Fordon',project:'Projekt',category:'Kategori',source:'Källa'} as Record<string,string>)[k]}: ${params.get(k)}`).join(' · ')} <button className="secondary" disabled={pending||queued} onClick={clearObject}>Visa hela gruppen igen</button></p>}
 </section>;
}
