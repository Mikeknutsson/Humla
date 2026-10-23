'use client';
import {useEffect,useState} from 'react';

type ComparisonRow={id:string;previous:number|null;difference:number|null;change_pct:number|null;status:string};
type Loaded={query:string;rows:ComparisonRow[];error?:boolean};
const money=new Intl.NumberFormat('sv-SE',{style:'currency',currency:'SEK',maximumFractionDigits:0});
const percent=new Intl.NumberFormat('sv-SE',{maximumFractionDigits:1});
const signed=(value:number,format:(value:number)=>string)=>(value>0?'+':'')+format(value);

export function useInternalYearComparison(query:string,enabled:boolean){
 const [loaded,setLoaded]=useState<Loaded|null>(null);
 useEffect(()=>{
  if(!enabled)return;
  const controller=new AbortController();let active=true;
  fetch('/api/kpi/year-comparison?'+query+'&part=internal',{signal:AbortSignal.any([controller.signal,AbortSignal.timeout(55000)])})
   .then(async response=>{if(!response.ok)throw Error();const data=await response.json();if(active)setLoaded({query,rows:data.rows});})
   .catch(()=>{if(active)setLoaded({query,rows:[],error:true});});
  return()=>{active=false;controller.abort();};
 },[query,enabled]);
 return loaded?.query===query?loaded:null;
}

export function InternalYearChange({comparison,metric}:{comparison:Loaded|null;metric:string}){
 if(!comparison)return <small>Hämtar jämförelse med fg. år…</small>;
 if(comparison.error)return <small>Jämförelsen med fg. år kunde inte hämtas.</small>;
 const row=comparison.rows.find(value=>value.id==='Interna intäkter:'+metric);
 if(row?.previous==null)return <small>Fg. år: underlag saknas</small>;
 return <><small>Fg. år: {money.format(row.previous)}</small><small>{row.difference==null?'Ofullständig jämförelse':<>{signed(row.difference,money.format)}{row.change_pct==null?'':` (${signed(row.change_pct,percent.format)} %)`} mot fg. år</>}</small></>;
}
