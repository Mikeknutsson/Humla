"use client";
import {useEffect,useRef,useState} from 'react';
import {KpiApp,type KpiAppProps} from './kpi-app';
import type {loadKpiPeriod} from '@/lib/kpi/live-report';

export function KpiLiveReport(props:KpiAppProps) {
 const [report,setReport]=useState({base:props,value:props});
 const [error,setError]=useState('');
 const request=useRef<AbortController|null>(null);
 useEffect(()=>()=>request.current?.abort(),[]);
 const current=report.base===props?report.value:props;
 async function changePeriod(query:string) {
  setError('');
  request.current?.abort();
  const controller=new AbortController();request.current=controller;
  try{
   const response=await fetch('/api/kpi/report',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({query}),signal:AbortSignal.any([controller.signal,AbortSignal.timeout(60000)])});
   if(!response.ok)throw new Error('KPI report unavailable');
   const data:Awaited<ReturnType<typeof loadKpiPeriod>>=await response.json();
   if(controller.signal.aborted)throw new Error('Request canceled');
   setReport({base:props,value:{...current,...data}});
   // Keep links, exports and saved selection aligned only after verified data arrives.
   const next=new URLSearchParams(query);
   const view=new URLSearchParams(window.location.search).get('view');
   if(view==='kpi')next.set('view',view);else next.delete('view');
   window.history.replaceState(null,'','/kpi?'+next);
  }catch{
   setError('Rapporten kunde inte hämtas. Tidigare urval och belopp visas fortfarande. Försök igen.');
   throw new Error('KPI report unavailable');
  }
 }
 return <>{error&&<p role="alert" className="content">{error}</p>}<KpiApp {...current} onPeriodChange={changePeriod}/></>;
}
