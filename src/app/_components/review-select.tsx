'use client';
import {useEffect,useState} from 'react';
export type ReviewOption={value:string;label:string};
export type ReviewOptions={projects:ReviewOption[];vehicles:ReviewOption[]};
export function useReviewOptions(enabled:boolean) {
 const [options,setOptions]=useState<ReviewOptions>();const [error,setError]=useState('');
 useEffect(()=>{if(!enabled)return;const c=new AbortController();fetch('/api/kpi/review?options=1',{signal:c.signal}).then(async r=>{const d=await r.json();if(!r.ok)throw Error(d.error);setOptions(d)}).catch(e=>{if(e.name!=='AbortError')setError(e.message)});return()=>c.abort()},[enabled]);
 return {options,error};
}
export function ReviewSelect({label,value,options,onChange,disabled=false,required=false}:{label:string;value:string;options:ReviewOption[];onChange:(value:string)=>void;disabled?:boolean;required?:boolean}) {
 const [focused,setFocused]=useState(false);
 const current=options.find(o=>o.value===value);
 // Mount the registry only for the active control, rather than thousands of hidden options per table.
 return <select aria-label={label} value={value} disabled={disabled} required={required} onFocus={()=>setFocused(true)} onBlur={()=>setFocused(false)} onChange={e=>onChange(e.target.value)} style={{minWidth:180,maxWidth:320}}><option value="">Välj {label.toLocaleLowerCase('sv')}</option>{value&&(!focused||!current)&&<option value={value}>{current?.label??`${value} (befintligt värde)`}</option>}{focused&&options.map(o=><option key={o.value} value={o.value}>{o.label}</option>)}</select>;
}
export const reviewCostCenters:ReviewOption[]=Object.entries({'10':'Entreprenad och maskinuthyrning','20':'Sortergården','30':'Transport','40':'Verkstad','50':'Fastigheter','60':'Skåne','90':'Övrigt'}).map(([value,name])=>({value,label:`${value} – ${name}`}));
