/** Hub domain calculation. KPI filters and vehicle identities deliberately do not apply. */
export const departments = {'30':'Transport','20':'Sortergården'} as const;
export type Payment = {id:string; center:string; kind:'in'|'out'; date:string; amount:number; internal:boolean};
export type ForecastInput = {asOf:string; periodOffset?:number; ledger:Payment[]; history:Payment[]; historyFrom:string; historyTo:string;basis?:'payment'|'booked';inDays?:number;outDays?:number};
const day = 86400000;
export function dateValue(value:string) {
  if(!/^\d{4}-\d{2}-\d{2}$/.test(value)) throw Error('Datum måste vara ÅÅÅÅ-MM-DD');
  const n=Date.parse(value+'T00:00:00Z');
  if(!Number.isFinite(n)||new Date(n).toISOString().slice(0,10)!==value) throw Error('Ogiltigt datum');
  return n;
}
const iso=(n:number)=>new Date(n).toISOString().slice(0,10);
const money=(n:number)=>Math.round(n*100)/100;
function validate(rows:Payment[]) {
 const ids=new Set<string>();
 if(!Array.isArray(rows)||rows.length>50000) throw Error('Högst 50 000 rader per underlag');
 for(const r of rows){
  if(!r||typeof r.id!=='string'||!r.id.trim()||r.id.length>200||typeof r.center!=='string'||r.center.length>100||!['in','out'].includes(r.kind)||typeof r.amount!=='number'||!Number.isFinite(r.amount)||Math.abs(r.amount)>1e12||typeof r.internal!=='boolean') throw Error('Ogiltig betalningsrad');
  dateValue(r.date);
  // Each ID is a unique source line, not an invoice number repeated for split cost centers.
  if(ids.has(r.id)) throw Error('Dubblett av rad-ID: '+r.id);
  ids.add(r.id);
 }
}
export function paymentForecast(input:ForecastInput){
 const periodOffset=input.periodOffset??0;
 if(!Number.isInteger(periodOffset)||Math.abs(periodOffset)>104)throw Error('Ogiltig prognosperiod');
 const now=dateValue(input.asOf); validate(input.ledger); validate(input.history);
 const basis=input.basis??'payment',inDays=input.inDays??0,outDays=input.outDays??0;
 if(!['payment','booked'].includes(basis)||![inDays,outDays].every(n=>Number.isInteger(n)&&n>=0&&n<=180))throw Error('Ogiltig utfallsgrund eller betalningstid');
 const hf=input.historyFrom?dateValue(input.historyFrom):null,ht=input.historyTo?dateValue(input.historyTo):null;
 if((hf===null)!==(ht===null)||hf!==null&&ht!==null&&(hf>ht||ht>=now)) throw Error('Historikperioden ska vara avslutad före rapportdatum');
 if(hf!==null&&ht!==null&&input.history.some(r=>dateValue(r.date)<hf||dateValue(r.date)>ht)) throw Error('Historikrader ligger utanför angiven täckningsperiod');
 const monday=now-((new Date(now).getUTCDay()+6)%7)*day;
 const history=input.history.filter(r=>!r.internal);
 const ledger=input.ledger.filter(r=>!r.internal);
 const sum=(rows:Payment[],c:string,k:string,a:number,b:number)=>money(rows.filter(r=>r.center===c&&r.kind===k&&dateValue(r.date)>=a&&dateValue(r.date)<=b).reduce((s,r)=>s+r.amount,0));
 const covered=(a:number,b:number)=>hf!==null&&ht!==null&&hf<=a&&ht>=b;
 const recentStart=monday-91*day,recentEnd=monday-day;
 const trend=(c:string,k:string)=>{
  if(!covered(recentStart-364*day,recentEnd)||!covered(recentStart,recentEnd))return null;
  const previous=sum(history,c,k,recentStart-364*day,recentEnd-364*day);
  return previous>0?sum(history,c,k,recentStart,recentEnd)/previous:null;
 };
 const weeks=Array.from({length:4},(_,i)=>{
  const start=monday+(i+4+periodOffset)*7*day,end=start+6*day;
  const thursday=start+3*day, year=new Date(thursday).getUTCFullYear();
  const jan4=Date.UTC(year,0,4), firstMonday=jan4-((new Date(jan4).getUTCDay()+6)%7)*day;
  const number=Math.floor((start-firstMonday)/(7*day))+1;
  const parts=Object.entries(departments).map(([center,name])=>{
   const calc=(kind:'in'|'out')=>{
    const known=sum(ledger,center,kind,start,end),factor=trend(center,kind);
    const lag=basis==='booked'?(kind==='in'?inDays:outDays)*day:0;
    const baseline=covered(start-364*day-lag,end-364*day-lag)?sum(history,center,kind,start-364*day-lag,end-364*day-lag):null;
    const estimate=baseline!==null&&factor!==null?money(baseline*factor):null;
    const forecast=estimate!==null?money(Math.max(0,estimate-known)):null;
    return {known,forecast,total:forecast===null?null:money(known+forecast),baseline,factor};
   };
   const incoming=calc('in'),outgoing=calc('out');
   return {center,name,incoming,outgoing,internal:{incoming:sum(input.ledger.filter(r=>r.internal),center,'in',start,end),outgoing:sum(input.ledger.filter(r=>r.internal),center,'out',start,end)},net:incoming.total===null||outgoing.total===null?null:money(incoming.total-outgoing.total)};
  });
  const aggregate=(kind:'incoming'|'outgoing')=>({known:money(parts.reduce((s,p)=>s+p[kind].known,0)),forecast:parts.some(p=>p[kind].forecast===null)?null:money(parts.reduce((s,p)=>s+p[kind].forecast!,0)),total:parts.some(p=>p[kind].total===null)?null:money(parts.reduce((s,p)=>s+p[kind].total!,0))});
  const internalRows=input.ledger.filter(r=>r.internal);
  const internalFor=(kind:'in'|'out')=>money(Object.keys(departments).reduce((s,c)=>s+sum(internalRows,c,kind,start,end),0));
  return {from:iso(start),to:iso(end),year,number,parts,internal:{incoming:internalFor('in'),outgoing:internalFor('out')},total:{incoming:aggregate('incoming'),outgoing:aggregate('outgoing'),net:parts.some(p=>p.net===null)?null:money(parts.reduce((s,p)=>s+p.net!,0))}};
 });
 const internal={ledger:input.ledger.filter(r=>r.internal),history:input.history.filter(r=>r.internal)};
 return {asOf:input.asOf,weeks,internal,unknown:ledger.filter(r=>!Object.hasOwn(departments,r.center)),overdue:ledger.filter(r=>dateValue(r.date)<now),excludedInternal:internal.ledger.length+internal.history.length,historyCoverage:{from:input.historyFrom,to:input.historyTo},method:`${basis==='booked'?`Bokfört utfall med antagen betalningstid ${inDays} dagar kund / ${outDays} dagar leverantör`:'Betalningshistorik'} 52 veckor bakåt × trend för 13 avslutade veckor. Interna körningar och överföringar ingår varken i extern reskontra, historisk bas eller årets trend. Känd reskontra dras av från prognosen. Belopp inklusive moms; öppet restbelopp, kreditposter med minus. Förfallodatum är ett antagande om betalningsdag. Ingen banksaldoprognos.`};
}
export type PaymentForecast=ReturnType<typeof paymentForecast>;
