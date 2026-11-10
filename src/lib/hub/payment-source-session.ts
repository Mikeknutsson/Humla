import type {OutcomeSource} from './payment-outcome-forecast';
import type {PayrollSource} from './payment-payroll-forecast';

type Snapshot={source:OutcomeSource;payroll:PayrollSource;fetchedAt:string};
const snapshots=new Map<string,{expires:number;value:Snapshot}>();
const ttl=5*60*1000;

/** Explicit period navigation may reuse the same authorized source snapshot.
 * A normal calculation, import review or correction always fetches fresh data.
 * This is an optional process-local optimization; a cache miss loads normally.
 */
export async function paymentSourceSession(key:string,reuse:boolean,load:()=>Promise<Omit<Snapshot,'fetchedAt'>>){
 const cached=snapshots.get(key);
 if(reuse&&cached&&cached.expires>Date.now())return {...cached.value,reused:true};
 snapshots.delete(key);
 const data=await load();
 const value={...data,fetchedAt:new Date().toISOString()};
 for(const [id,entry]of snapshots)if(entry.expires<=Date.now())snapshots.delete(id);
 if(snapshots.size>=8)snapshots.delete(snapshots.keys().next().value!);
 snapshots.set(key,{expires:Date.now()+ttl,value});
 return {...value,reused:false};
}

export function invalidatePaymentSourceSessions(tenant:string){
 for(const key of snapshots.keys())if(key.startsWith(tenant+':'))snapshots.delete(key);
}
