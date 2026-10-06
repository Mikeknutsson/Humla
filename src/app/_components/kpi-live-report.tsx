"use client";
import {memo,useCallback,useEffect,useRef,useState,useTransition} from 'react';
import {useSearchParams} from 'next/navigation';
import {KpiApp,type KpiAppProps} from './kpi-app';
import {KpiReportSelection} from './kpi-report-selection';
import {monthPeriodQuery} from '@/lib/kpi/period';
import {selectionFromQuery} from '@/lib/kpi/selection';
import type {loadKpiPeriod} from '@/lib/kpi/live-report';

type Data=Omit<Awaited<ReturnType<typeof loadKpiPeriod>>,'dashboard'>&{dashboard:KpiAppProps['dashboard']};
const ReportApp=memo(KpiApp);
function key(query:string){const p=selectionFromQuery(new URLSearchParams(query));if(p.has('fiscal_year')&&p.has('months')){p.delete('from');p.delete('to');}p.sort();return p.toString();}
export function KpiLiveReport(props:KpiAppProps) {
 const params=useSearchParams();
 const [report,setReport]=useState({base:props,value:props});
 const [draft,setDraft]=useState<{base:KpiAppProps;query:string}|null>(null);
 const [error,setError]=useState(''),[pending,setPending]=useState(false);const [renderPending,startReportTransition]=useTransition();
 const request=useRef<AbortController|null>(null),timer=useRef<ReturnType<typeof setTimeout>|null>(null),version=useRef(0);
 const cache=useRef(new Map<string,{data:Data;at:number}>());
 const current=report.base===props?report.value:props;
 const query=draft?.base===props?draft.query:params.toString();
 useEffect(()=>{const requests=version;cache.current.clear();if(props.monthPeriod){const query=new URLSearchParams(monthPeriodQuery(props.monthPeriod));for(const [k,v] of Object.entries(props.activeFilters))query.set(k,v);if(props.dashboard.cost_center_scope)query.set('cost_center',props.dashboard.cost_center_scope);cache.current.set(key(query.toString()),{data:{monthPeriod:props.monthPeriod,activeFilters:props.activeFilters,from:props.from,to:props.to,dashboard:props.dashboard,overviewMonthly:props.overviewMonthly,overviewPrevious:props.overviewPrevious,overviewPeriod:props.overviewPeriod,transpaVehicleTime:props.transpaVehicleTime,efficiency:props.efficiency,hiredCapacity:props.hiredCapacity,driverProductivity:props.driverProductivity},at:Date.now()});}return()=>{requests.current++;request.current?.abort();if(timer.current)clearTimeout(timer.current);};},[props]);
 const change=useCallback((nextQuery:string)=>{
  const id=++version.current;
  request.current?.abort();if(timer.current)clearTimeout(timer.current);
  setDraft({base:props,query:nextQuery});setError('');setPending(true);
  async function load(){
   const controller=new AbortController();request.current=controller;
   try{
    const cached=cache.current.get(key(nextQuery));
    let data:Data;
    if(cached&&Date.now()-cached.at<300000){
     data=cached.data;
     void fetch('/api/kpi/selection',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({query:nextQuery}),signal:controller.signal}).catch(()=>{});
    }
    else{
     const response=await fetch('/api/kpi/report',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({query:nextQuery}),signal:AbortSignal.any([controller.signal,AbortSignal.timeout(60000)])});
     if(!response.ok)throw new Error('KPI report unavailable');
     data=await response.json();
     if(id!==version.current)return;
     if(cache.current.size>=16)cache.current.delete(cache.current.keys().next().value!);
     cache.current.set(key(nextQuery),{data,at:Date.now()});
    }
    if(id!==version.current)return;
    startReportTransition(()=>{setReport(previous=>id===version.current?{base:props,value:{...(previous.base===props?previous.value:props),...data}}:previous);
    const next=new URLSearchParams(nextQuery),view=new URLSearchParams(window.location.search).get('view');
    if(view==='kpi')next.set('view',view);else next.delete('view');
    window.history.replaceState(null,'','/kpi?'+next);});
    setPending(false);
   }catch{
    if(id!==version.current)return;
    setDraft(null);setPending(false);setError('Rapporten kunde inte hämtas. Tidigare urval och belopp visas fortfarande. Försök igen.');
   }
  }
  // Repeat selections are immediate; rapid changes share one server request.
  if(cache.current.has(key(nextQuery)))void load();else timer.current=setTimeout(()=>void load(),250);
 },[props]);
 return <KpiReportSelection.Provider value={{query,pending:pending||renderPending,change}}>{error&&<p role="alert" className="content">{error}</p>}<ReportApp {...current}/></KpiReportSelection.Provider>;
}
