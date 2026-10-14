'use client';
import {useEffect,useState} from 'react';
type Summary={status?:string;total_percent:number|null;material_percent:number|null;tipp_deponi_percent:number|null;revenue_basis:number|null;total:number|null;material:number|null;tipp_deponi:number|null;transport:number|null;rows:number;review_rows:number;review_amount:number;review_included?:boolean;pending_rows?:number;pending_amount?:number;basis:string};
export function useKpiInternalSummary(initial:Summary|undefined,query:string,enabled:boolean){
 const [loaded,setLoaded]=useState<{query:string;data:Summary}|null>(null);
 useEffect(()=>{if(!enabled||initial?.status!=='deferred')return;const controller=new AbortController();let active=true;
 fetch('/api/kpi/internal-summary?'+query,{signal:AbortSignal.any([controller.signal,AbortSignal.timeout(35000)])}).then(async r=>{if(!r.ok)throw Error();const data=await r.json();if(active)setLoaded({query,data});}).catch(()=>{if(active)setLoaded({query,data:{...initial,basis:'Internt underlag kunde inte hämtas. Övriga KPI visas; öppna internöverföringar för detaljer.'}});});
 return()=>{active=false;controller.abort();};},[initial,query,enabled]);
 return initial?.status==='deferred'&&loaded?.query===query?loaded.data:initial;
}
