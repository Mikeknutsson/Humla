"use client";
import {useTransition,useOptimistic} from 'react';
import {useRouter,useSearchParams} from 'next/navigation';
import {fiscalMonths,monthLabels,monthPeriodQuery,type MonthPeriod} from '@/lib/kpi/period';
import {KpiCostCenterFilter,KpiGroupFilter} from './kpi-cost-center-filter';
export function KpiMonthPeriod({period,costCenter,costCenters,groups=[],unitName}:{period:MonthPeriod;costCenter:string;costCenters:Array<{code:string;name:string}>;groups?:string[];unitName?:string}) {
 const router=useRouter();const params=useSearchParams();const [pending,start]=useTransition();const [selected,setSelected]=useOptimistic(period);
 function change(year:number,months:number[],center=costCenter) {
  const p=new URLSearchParams(params);p.delete('from');p.delete('to');p.delete('date_from');p.delete('date_to');
  for(const [k,v] of new URLSearchParams(monthPeriodQuery({fiscalYear:year,months})))p.set(k,v);
  if(center)p.set('cost_center',center);else p.delete('cost_center');
  start(()=>{setSelected({...period,fiscalYear:year,months});router.push('/kpi?'+p);});
 }
 const years=Array.from({length:Math.max(5,period.currentYear-selected.fiscalYear+2)},(_,i)=>Math.max(period.currentYear+1,selected.fiscalYear)-i);
 const ytd=selected.fiscalYear<period.currentYear?fiscalMonths:selected.fiscalYear===period.currentYear?fiscalMonths.slice(0,fiscalMonths.indexOf(period.currentMonth)+1):[];
 function groupChange(value:string){const p=new URLSearchParams(params);if(value)p.set('group',value);else p.delete('group');for(const k of ['unit','vehicle','project','page'])p.delete(k);start(()=>router.push('/kpi?'+p));}
 function clearObject(){const p=new URLSearchParams(params);for(const k of ['unit','vehicle','project','category','kind','source','date_from','date_to'])p.delete(k);start(()=>router.push('/kpi?'+p));}
 return <section className="fiscal-period panel" aria-label="Periodväljare" aria-busy={pending}>
  <div className="fiscal-controls"><label>Verksamhetsår<select aria-label="Verksamhetsår" value={selected.fiscalYear} disabled={pending} onChange={e=>change(Number(e.target.value),selected.months)}>{years.map(y=><option key={y} value={y}>{y}/{y+1}</option>)}</select></label>
  <KpiCostCenterFilter value={costCenter} options={costCenters} disabled={pending} onChange={center=>change(selected.fiscalYear,selected.months,center)}/>
  <KpiGroupFilter value={params.get('group')??''} groups={groups} disabled={pending} onChange={groupChange}/>
  <div className="fiscal-shortcuts"><button onClick={()=>change(selected.fiscalYear,fiscalMonths)}>Hela verksamhetsåret</button><button disabled={!ytd.length} title="Från september till och med aktuell månad" onClick={()=>change(selected.fiscalYear,ytd)}>YTD</button><button onClick={()=>change(selected.fiscalYear,[selected.months.length===1?selected.months[0]:period.currentMonth])}>En månad</button></div></div>
  <span className="section-kicker">Period · klicka för att välja eller ta bort månader</span>
  <div className="fiscal-months">{fiscalMonths.map((m,i)=><button key={m} aria-pressed={selected.months.includes(m)} disabled={selected.months.length===1&&selected.months.includes(m)} onClick={()=>change(selected.fiscalYear,selected.months.includes(m)?selected.months.filter(x=>x!==m):fiscalMonths.filter(x=>selected.months.includes(x)||x===m))}>{monthLabels[i]} {selected.months.includes(m)?'✓':''}</button>)}</div>
  <p aria-live="polite">{pending?'Hämtar från Humla Hub…':`${selected.months.map(m=>monthLabels[fiscalMonths.indexOf(m)]).join(' + ')} · ${selected.fiscalYear}/${selected.fiscalYear+1}`} · YTD omfattar hela månader till och med aktuell månad.</p>
  {(params.has('unit')||params.has('vehicle')||params.has('project')||params.has('category')||params.has('source'))&&<p>Detaljurval: {['unit','vehicle','project','category','source'].filter(k=>params.has(k)).map(k=>k==='unit'?`Enhet: ${unitName??'Vald ekonomisk enhet'}`:`${({vehicle:'Fordon',project:'Projekt',category:'Kategori',source:'Källa'} as Record<string,string>)[k]}: ${params.get(k)}`).join(' · ')} <button className="secondary" onClick={clearObject}>Visa hela gruppen igen</button></p>}
 </section>;
}
