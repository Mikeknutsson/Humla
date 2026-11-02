import {createHash} from 'node:crypto';
import {customerTerm,type Outcome} from './payment-outcome-forecast';
import {monthDate,type PeriodReview} from './payment-evidence-model';
export const reviewKey=(scope:string,center:string,kind:string,month:string)=>[scope,center,kind,month].join('|');
/** Fingerprints the normalized source, not the current file order or global import timestamp. */
export function periodFingerprints(rows:Outcome[]){
 const groups=new Map<string,string[]>();
 for(const r of rows){const scope=r.kind==='in'&&!r.internal&&customerTerm(r.party).code==='stena_month_end'?'stena':'ordinary';const key=reviewKey(scope,r.center,r.kind,monthDate(r.date));const lines=groups.get(key)??[];
  lines.push(JSON.stringify([r.id??'',r.date,Number(r.amount),r.party,r.invoiceDate,r.internal,r.oneOff??false,r.amountStatus??null,r.reference??'']));groups.set(key,lines);
 }
 const hashes=new Map<string,string>();for(const [key,lines]of groups)hashes.set(key,createHash('sha256').update('evidence-v2|'+key+'|'+lines.sort().join('\n')).digest('hex'));
 return (scope:string,center:string,kind:string,month:string)=>{const key=reviewKey(scope,center,kind,month);return hashes.get(key)??createHash('sha256').update('evidence-v2|'+key+'|').digest('hex');};
}
export function validatePeriodReviews(rows:Outcome[],reviews:PeriodReview[]){const fingerprint=periodFingerprints(rows);return reviews.map(r=>({...r,stale:r.reviewed&&r.sourceHash!==fingerprint(r.scope,r.center,r.kind,r.month)}));}
/** Bind user confirmation to the displayed snapshot, including explicitly empty source months. */
export function periodReviewBasis(rows:Outcome[],asOf:string){
 const fingerprint=periodFingerprints(rows),basis:Record<string,string>={},d=new Date(asOf+'T00:00:00Z');
 for(let i=1;i<=24;i++){const month=new Date(Date.UTC(d.getUTCFullYear(),d.getUTCMonth()-i,1)).toISOString().slice(0,10);
  for(const center of['20','30','40'])for(const kind of['in','out']){
   if(center==='40'&&kind==='in')continue;
   basis[reviewKey('ordinary',center,kind,month)]=fingerprint('ordinary',center,kind,month);
   if(kind==='in')basis[reviewKey('stena',center,kind,month)]=fingerprint('stena',center,kind,month);
  }
 }
 return basis;
}
