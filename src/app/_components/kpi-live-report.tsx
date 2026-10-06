"use client";
import {useState} from 'react';
import {KpiApp,type KpiAppProps} from './kpi-app';
import type {loadKpiPeriod} from '@/lib/kpi/live-report';

export function KpiLiveReport(props:KpiAppProps) {
 const [report,setReport]=useState({base:props,value:props});
 const [error,setError]=useState('');
 const current=report.base===props?report.value:props;
 async function changePeriod(query:string) {
  setError('');
  try{
   const response=await fetch('/api/kpi/report',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({query}),signal:AbortSignal.timeout(60000)});
   if(!response.ok)throw new Error('KPI report unavailable');
   const data:Awaited<ReturnType<typeof loadKpiPeriod>>=await response.json();
   setReport({base:props,value:{...current,...data}});
   // Keep links, exports and saved selection aligned only after verified data arrives.
   window.history.replaceState(null,'','/kpi?'+query);
  }catch{
   setError('Rapporten kunde inte hämtas. Tidigare urval och belopp visas fortfarande. Försök igen.');
   throw new Error('KPI report unavailable');
  }
 }
 return <>{error&&<p role="alert" className="content">{error}</p>}<KpiApp {...current} onPeriodChange={changePeriod}/></>;
}
