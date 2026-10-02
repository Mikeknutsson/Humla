"use client";
import {useOptimistic,useTransition} from 'react';
import {useRouter,useSearchParams} from 'next/navigation';
import styles from './kpi-cost-center-filter.module.css';
export function KpiMultiFilter({value,options,disabled=false,onChange,label,allLabel,param,showCodes=false}:{value:string;options:Array<{code:string;name:string}>;disabled?:boolean;onChange?:(value:string)=>void;label:string;allLabel:string;param:string;showCodes?:boolean}){
 const router=useRouter(),params=useSearchParams();const [pending,start]=useTransition();const [selected,setSelected]=useOptimistic(value);
 const codes=selected?selected.split(','):[];
 function change(next:string){start(()=>{setSelected(next);if(onChange)onChange(next);else{const p=new URLSearchParams(params);if(next)p.set(param,next);else p.delete(param);p.delete('page');router.push('/kpi?'+p);}})}
 const title=codes.length?codes.map(c=>options.find(o=>o.code===c)?.name??c).join(' + '):allLabel;
 return <details className={styles.selector}><summary aria-label={`Välj ${label.toLowerCase()}`}><span>{label}</span><strong>{title}</strong></summary><fieldset disabled={disabled||pending} aria-label={label}><label><input type="checkbox" checked={!codes.length} onChange={()=>change('')}/>{allLabel}</label>{options.map(o=><label key={o.code}><input type="checkbox" checked={codes.includes(o.code)} onChange={()=>change(options.filter(c=>c.code===o.code?!codes.includes(o.code):codes.includes(c.code)).map(c=>c.code).join(','))}/>{!showCodes||o.code==='unclassified'?o.name:`${o.code} – ${o.name}`}</label>)}<small>Välj ett eller flera. Urvalet gäller båda vyerna.</small></fieldset></details>;
}

export function KpiCostCenterFilter(props:{value:string;options:Array<{code:string;name:string}>;disabled?:boolean;onChange?:(value:string)=>void}) { return <KpiMultiFilter {...props} label="Kostnadsställen" allLabel="Alla kostnadsställen" param="cost_center" showCodes/>; }
export function KpiGroupFilter({value,groups,disabled,onChange}:{value:string;groups:string[];disabled?:boolean;onChange?:(value:string)=>void}) { return <KpiMultiFilter value={value} options={[...new Set([...groups,...value.split(",").filter(Boolean)])].map(name=>({code:name,name}))} disabled={disabled} onChange={onChange} label="Verksamhetsgrupper" allLabel="Alla verksamhetsgrupper" param="group"/>; }
