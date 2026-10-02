"use client";
import {useOptimistic,useTransition} from 'react';
import {useRouter,useSearchParams} from 'next/navigation';
import styles from './kpi-cost-center-filter.module.css';
export function KpiCostCenterFilter({value,options,disabled=false,onChange}:{value:string;options:Array<{code:string;name:string}>;disabled?:boolean;onChange?:(value:string)=>void}){
 const router=useRouter(),params=useSearchParams();const [pending,start]=useTransition();const [selected,setSelected]=useOptimistic(value);
 const codes=selected?selected.split(','):[];
 function change(next:string){start(()=>{setSelected(next);if(onChange)onChange(next);else{const p=new URLSearchParams(params);if(next)p.set('cost_center',next);else p.delete('cost_center');p.delete('page');router.push('/kpi?'+p);}})}
 const title=codes.length?codes.map(c=>options.find(o=>o.code===c)?.name??c).join(' + '):'Alla kostnadsställen';
 return <details className={styles.selector}><summary aria-label="Välj kostnadsställen"><span>Kostnadsställen</span><strong>{title}</strong></summary><fieldset disabled={disabled||pending} aria-label="Kostnadsställen"><label><input type="checkbox" checked={!codes.length} onChange={()=>change('')}/>Alla kostnadsställen</label>{options.map(o=><label key={o.code}><input type="checkbox" checked={codes.includes(o.code)} onChange={()=>change(options.filter(c=>c.code===o.code?!codes.includes(o.code):codes.includes(c.code)).map(c=>c.code).join(','))}/>{o.code==='unclassified'?o.name:`${o.code} – ${o.name}`}</label>)}<small>Välj ett eller flera. Urvalet gäller båda vyerna.</small></fieldset></details>;
}
