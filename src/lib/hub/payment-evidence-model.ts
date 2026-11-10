import {dateValue} from './payment-forecast';
import type {Outcome} from './payment-outcome-forecast';
export type PeriodReview={scope:'ordinary'|'stena';center:string;kind:'in'|'out';month:string;reviewed:boolean;sourceHash?:string;stale?:boolean;reviewedAt?:string;note?:string};
export type EvidenceRow=Outcome&{id:string;dateValue:number;paymentDate:string;stena:boolean};
const day=86400000;
export const roundPayment=(n:number)=>Math.round(n*100)/100;
export const paymentIso=(n:number)=>new Date(n).toISOString().slice(0,10);
export const monthDate=(s:string)=>s.slice(0,7)+'-01';
const shiftMonth=(s:string,n:number)=>{const d=new Date(dateValue(s));return paymentIso(Date.UTC(d.getUTCFullYear(),d.getUTCMonth()+n,1));};
export function reviewedTrend(rows:EvidenceRow[],reviews:PeriodReview[],asOf:string,scope:PeriodReview['scope'],center:string,kind:'in'|'out'){
 const latest=monthDate(asOf),complete=new Set(reviews.filter(r=>r.reviewed&&!r.stale&&r.scope===scope&&r.center===center&&r.kind===kind&&r.month<latest).map(r=>r.month));
 const months=Array.from({length:12},(_,i)=>shiftMonth(latest,-i-1)).filter(m=>complete.has(m)&&complete.has(shiftMonth(m,-12))).slice(0,6);
 const currentSet=new Set(months),priorSet=new Set(months.map(m=>shiftMonth(m,-12)));
 const currentRows=rows.filter(r=>currentSet.has(monthDate(r.date))),previousRows=rows.filter(r=>priorSet.has(monthDate(r.date)));
 const sum=(rs:EvidenceRow[])=>roundPayment(rs.filter(r=>!r.oneOff).reduce((s,r)=>s+r.amount,0));
 const current=sum(currentRows),previous=sum(previousRows);
 return {factor:months.length>=3&&previous>0?current/previous:null,months,current,previous,currentRows,previousRows};
}
export function broadWeeklyBaseline(rows:EvidenceRow[],weekFrom:string){
 const start=dateValue(weekFrom)-364*day-42*day,end=start+91*day-day;
 const paymentDates=rows.map(r=>dateValue(r.paymentDate));
 const covered=paymentDates.length>0&&Math.min(...paymentDates)<=start&&Math.max(...paymentDates)>=end;
 const samples=rows.filter(r=>dateValue(r.paymentDate)>=start&&dateValue(r.paymentDate)<=end);
 const sum=(rs:EvidenceRow[])=>rs.reduce((s,r)=>s+r.amount,0);
 return {amount:covered?roundPayment(sum(samples.filter(r=>!r.oneOff))/13):null,rows:samples,excluded:roundPayment(sum(samples.filter(r=>r.oneOff))/13),from:paymentIso(start),to:paymentIso(end)};
}
export function stenaPaymentDate(deliveryMonth:string){const d=new Date(dateValue(deliveryMonth));return paymentIso(Date.UTC(d.getUTCFullYear(),d.getUTCMonth()+1,0)+45*day);}
export type StenaMonth={center:string;deliveryMonth:string;paymentDate:string;settled:number;history:number;workify:number;registered:number;remaining:number|null;total:number|null;baseline:number|null;factor:number;reviewed:boolean;trendMonths:number;knownIds:string[];baselineIds:string[]};
export function stenaMonthlyEvidence(rows:EvidenceRow[],reviews:PeriodReview[],asOf:string,weeks:{from:string;to:string}[]):StenaMonth[]{
 const answer:StenaMonth[]=[];
 for(const center of [...new Set(rows.filter(r=>r.stena&&!r.internal).map(r=>r.center))]){
  const group=rows.filter(r=>r.stena&&!r.internal&&r.center===center),trend=reviewedTrend(group,reviews,asOf,'stena',center,'in');
  // Delivery month ends 45 days before the assumed payment date. Include boundary months.
  for(const week of weeks){
   const first=monthDate(paymentIso(dateValue(week.from)-80*day));
   for(let month=first;month<=monthDate(week.to);month=shiftMonth(month,1)){
    const pay=stenaPaymentDate(month);if(pay<week.from||pay>week.to)continue;
    const prior=shiftMonth(month,-12),priorEnd=shiftMonth(prior,1);
    const baselineRows=group.filter(r=>r.date>=prior&&r.date<priorEnd),known=group.filter(r=>monthDate(r.date)===month&&r.date<=asOf);
    // A customer seen only in unrelated old months is not a new monthly forecast stream.
    if(!baselineRows.length&&!known.length)continue;
    const dates=group.map(r=>r.dateValue),covered=dates.length>0&&Math.min(...dates)<=dateValue(prior)&&Math.max(...dates)>=dateValue(priorEnd)-day;
    const sum=(rs:EvidenceRow[])=>roundPayment(rs.reduce((s,r)=>s+r.amount,0));
    const baseline=covered?sum(baselineRows.filter(r=>!r.oneOff)):null,registered=sum(known),factor=trend.factor??1;
    const reviewed=reviews.some(r=>r.reviewed&&!r.stale&&r.scope==='stena'&&r.center===center&&r.kind==='in'&&r.month===month&&r.month<monthDate(asOf));
    const remaining=reviewed?0:baseline===null?null:roundPayment(Math.max(0,baseline*factor-registered));
    answer.push({center,deliveryMonth:month,paymentDate:pay,settled:sum(known.filter(r=>r.amountStatus==='settled')),history:sum(known.filter(r=>r.amountStatus==='history')),workify:sum(known.filter(r=>!r.amountStatus)),registered,remaining,total:remaining===null?null:roundPayment(registered+remaining),baseline,factor,reviewed,trendMonths:trend.months.length,knownIds:known.map(r=>r.id),baselineIds:baselineRows.map(r=>r.id)});
   }
  }
 }
 return answer;
}
