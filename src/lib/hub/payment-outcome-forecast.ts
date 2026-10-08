import {dateValue,departments,paymentForecast,type Payment,type PaymentForecast} from './payment-forecast';
export type Outcome={center:string;kind:'in'|'out';date:string;amount:number;party:string;invoiceDate:string|null;internal:boolean};
export type OutcomeSource={synced_at:string;rows:Outcome[];review_rows:number;review_amount:number};
const day=86400000,iso=(n:number)=>new Date(n).toISOString().slice(0,10),round=(n:number)=>Math.round(n*100)/100;
const name=(s:string)=>s.toLocaleLowerCase('sv-SE').normalize('NFKC').replace(/[^\p{L}\p{N}]+/gu,' ').trim();
/** Source customer names are adapted to payment policies only; no persistent identity guesses. */
export function customerTerm(party:string){
 const n=name(party);
 if(n==='elleholms maskin stena'||/^stena(?:\s|$)/.test(n))return {code:'stena_month_end',days:45};
 if(['linnestofta maskin','linnestofta maskin ab','thomas håkansson entreprenad','thomas håkansson entreprenad ab'].includes(n))return {code:'invoice_45',days:45};
 return {code:'invoice_30',days:30};
}
export function expectedPaymentDate(row:Outcome,supplierDays=30){
 const term=customerTerm(row.party),delivery=dateValue(row.date);
 if(row.kind==='in'&&term.code==='stena_month_end'){
  const d=new Date(delivery),last=Date.UTC(d.getUTCFullYear(),d.getUTCMonth()+1,0);
  return iso(last+45*day);
 }
 const anchor=row.kind==='in'&&row.invoiceDate?dateValue(row.invoiceDate):delivery;
 return iso(anchor+(row.kind==='in'?term.days:supplierDays)*day);
}
export type AutomaticForecast=PaymentForecast&{automatic:{syncedAt:string;trendFrom:string;trendTo:string;warnings:string[];reviewRows:number;reviewAmount:number;supplierDays:number}};
export function outcomeForecast(source:OutcomeSource,asOf:string,supplierDays=30,periodOffset=0):AutomaticForecast{
 const now=dateValue(asOf);if(!Number.isInteger(supplierDays)||supplierDays<0||supplierDays>180)throw Error('Leverantörstid måste vara 0–180 dagar');
 const monthStart=Date.UTC(new Date(now).getUTCFullYear(),new Date(now).getUTCMonth(),1),trendEnd=monthStart-day;
 const endDate=new Date(trendEnd),fyYear=endDate.getUTCMonth()>=8?endDate.getUTCFullYear():endDate.getUTCFullYear()-1;
 const trendStart=Date.UTC(fyYear,8,1),previous=(n:number)=>{const d=new Date(n);return Date.UTC(d.getUTCFullYear()-1,d.getUTCMonth(),d.getUTCDate())};
 const warnings=['Beloppen är enligt Workify/NeXT-underlaget, exklusive moms. Ingen verifierad reskontra eller faktisk betalningsstatus.','NeXT-kostnader flyttas med antagen betalningstid; detta är inte verifierade leverantörsförfallodatum.'];
 const rows=source.rows.map((r,i)=>({...r,id:'outcome:'+i,dateValue:dateValue(r.date),paymentDate:expectedPaymentDate(r,supplierDays)}));
 const external=rows.filter(r=>!r.internal);
 const toPayment=(r:typeof rows[number]):Payment=>({id:r.id,center:r.center,kind:r.kind,date:r.paymentDate,amount:Number(r.amount),internal:r.internal});
 const result=paymentForecast({asOf,periodOffset,ledger:[],history:[],historyFrom:'',historyTo:''});
 const sum=(rs:typeof rows,a:number,b:number)=>round(rs.filter(r=>r.dateValue>=a&&r.dateValue<=b).reduce((s,r)=>s+Number(r.amount),0));
 for(const w of result.weeks){
  const start=dateValue(w.from),end=dateValue(w.to);
  for(const p of w.parts)for(const internalScope of [false,true])for(const [key,kind] of [['incoming','in'],['outgoing','out']] as const){
   const group=rows.filter(r=>r.internal===internalScope&&r.center===p.center&&r.kind===kind);
   const dates=group.map(r=>r.dateValue),min=dates.length?Math.min(...dates):Infinity,max=dates.length?Math.max(...dates):-Infinity;
   const before=sum(group,previous(trendStart),previous(trendEnd)),current=sum(group,trendStart,trendEnd);
   const enough=group.length>0&&min<=previous(trendStart)&&max>=trendEnd;
   const factor=enough&&before>0?current/before:null;
   const baselineRows=group.filter(r=>{const n=dateValue(r.paymentDate);return n>=start-364*day&&n<=end-364*day});
   // Earliest source coverage must reach the source months that can feed this payment week.
   const paymentDates=group.map(r=>dateValue(r.paymentDate));
   // Internal rows have their own actual assumed payment-date coverage, not the
   // external Stena/customer lag envelope. Missing history is never treated as zero.
   const baselineCovered=internalScope
    ?paymentDates.length>0&&Math.min(...paymentDates)<=start-364*day&&Math.max(...paymentDates)>=end-364*day
    :min<=start-364*day-(kind==='in'?80:supplierDays)*day&&max>=end-364*day;
   const baseline=baselineCovered?round(baselineRows.reduce((s,r)=>s+Number(r.amount),0)):null;
   const registered=group.filter(r=>r.dateValue<=now&&dateValue(r.paymentDate)>=start&&dateValue(r.paymentDate)<=end);
   const known=round(registered.reduce((s,r)=>s+Number(r.amount),0));
   const forecast=baseline!==null&&factor!==null?round(Math.max(0,baseline*factor-known)):null;
   const total=forecast===null?null:round(known+forecast);
   if(internalScope)p.internal[key]=total;
   else p[key]={known,forecast,total,baseline,factor};
  }
  for(const k of ['incoming','outgoing'] as const)w.internal[k]=w.parts.some(p=>p.internal[k]===null)?null:round(w.parts.reduce((s,p)=>s+p.internal[k]!,0));
  for(const p of w.parts)p.net=p.incoming.total===null||p.outgoing.total===null?null:round(p.incoming.total-p.outgoing.total);
  for(const k of ['incoming','outgoing'] as const)w.total[k]={known:round(w.parts.reduce((s,p)=>s+p[k].known,0)),forecast:w.parts.some(p=>p[k].forecast===null)?null:round(w.parts.reduce((s,p)=>s+p[k].forecast!,0)),total:w.parts.some(p=>p[k].total===null)?null:round(w.parts.reduce((s,p)=>s+p[k].total!,0))};
  w.total.net=w.parts.some(p=>p.net===null)?null:round(w.parts.reduce((s,p)=>s+p.net!,0));
 }
 result.internal={ledger:[],history:rows.filter(r=>r.internal).map(toPayment)};
 result.excludedInternal=result.internal.history.length;
 result.unknown=external.filter(r=>!Object.hasOwn(departments,r.center)).map(toPayment);result.overdue=[];
 result.historyCoverage={from:source.rows.length?source.rows.reduce((a,r)=>a<r.date?a:r.date,source.rows[0].date):'',to:source.rows.length?source.rows.reduce((a,r)=>a>r.date?a:r.date,source.rows[0].date):''};
 result.method=`Workify-intäkter och NeXT-kostnader, exklusive moms. Föregående års beräknade betalningsvecka × årets verksamhetsårstrend ${iso(trendStart)}–${iso(trendEnd)} jämfört med samma datum förra året. Registrerade externa rader räknas av från prognosen. Standard kund 30 dagar, Linnestofta Maskin och Thomas Håkansson Entreprenad 45 dagar från fakturadatum (annars leveransdatum som antagande). Stena: 45 kalenderdagar från sista dagen i leveransmånaden. Leverantörer: ${supplierDays} dagar som antagande. Interna körningar prognostiseras separat med sin egen historik och trend och ingår inte i externa belopp eller netto. Banksaldo och momsprognos ingår inte.`;
 if(result.weeks.some(w=>w.parts.some(p=>p.net===null)))warnings.push('En eller flera avdelningar saknar tillräckligt jämförbart underlag. Totalsiffror visas inte som kompletta när någon del saknas.');
 for(const p of result.weeks[0].parts)for(const [key,kind] of [['incoming','in'],['outgoing','out']] as const){if(p[key].factor===null){const subset=external.filter(r=>r.center===p.center&&r.kind===kind),latest=subset.length?subset.reduce((a,r)=>a>r.date?a:r.date,subset[0].date):null;warnings.push(`${p.center} ${p.name}: ${kind==='in'?'intäkts':'kostnads'}trend saknar tillräckligt periodunderlag${latest?`; senaste registrerade datum ${latest}`:'. Inga externa rader finns'}.`);}}
 if(source.review_rows)warnings.push(`${source.review_rows} importrader för granskning ingår inte; belopp ${round(source.review_amount)} kr.`);
 return {...result,automatic:{syncedAt:source.synced_at,trendFrom:iso(trendStart),trendTo:iso(trendEnd),warnings,reviewRows:source.review_rows,reviewAmount:source.review_amount,supplierDays}};
}
