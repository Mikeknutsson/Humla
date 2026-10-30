import type {TransportScorecard} from '../kpi/transport-leader';

export type DailyRevenueTarget={days:number;actual:number|null;required:number|null;gap:number|null;reason:string|null};

/** Historical average, using the same authorized revenue, net cost and dated goal as the scorecard. */
export function dailyRevenueTarget(revenue:number|null,cost:number|null,margin:number|null,days:number):DailyRevenueTarget {
 const actual=days>0&&revenue!=null&&Number.isFinite(revenue)?revenue/days:null;
 const reason=days<=0?'Inga arbetsdagar i perioden':cost==null||!Number.isFinite(cost)?'Kostnadsunderlag saknas':margin==null||!Number.isFinite(margin)?'Mål saknas':margin>=100?'Målet måste vara under 100 %':cost<0?'Nettokostnaden är negativ':null;
 const required=reason===null?cost!/(1-margin!/100)/days:null;
 return {days,actual,required,gap:required!=null&&actual!=null?actual-required:null,reason};
}

/** Monday–Friday, inclusive. Includes days without transactions; no inferred operating days. */
export function weekdays(from:string,to:string):number {
 const start=Date.parse(from+'T00:00:00Z'),end=Date.parse(to+'T00:00:00Z');
 if(!Number.isFinite(start)||!Number.isFinite(end)||start>end||end-start>366*86400000)return 0;
 let count=0;for(let d=start;d<=end;d+=86400000){const day=new Date(d).getUTCDay();if(day!==0&&day!==6)count++;}return count;
}

/** Gregorian Easter; movable Swedish weekday holidays are offsets from Easter Sunday. */
function easterSunday(year:number):Date {
 const a=year%19,b=Math.floor(year/100),c=year%100,d=Math.floor(b/4),e=b%4;
 const f=Math.floor((b+8)/25),g=Math.floor((b-f+1)/3),h=(19*a+b-d-g+15)%30;
 const i=Math.floor(c/4),k=c%4,l=(32+2*e+2*i-h-k)%7,m=Math.floor((a+11*h+22*l)/451);
 const month=Math.floor((h+l-7*m+114)/31),day=(h+l-7*m+114)%31+1;
 return new Date(Date.UTC(year,month-1,day));
}

function nonWorkingDates(year:number):Set<string> {
 const iso=(date:Date)=>date.toISOString().slice(0,10);
 const fixed=['01-01','01-06','05-01','06-06','12-24','12-25','12-26','12-31'].map(day=>`${year}-${day}`);
 const easter=easterSunday(year).getTime();
 const movable=[-2,1,39].map(offset=>iso(new Date(easter+offset*86400000)));
 // Midsummer Eve is the Friday between June 19 and 25. Saturday holidays
 // and Easter/Pentecost Sundays are already excluded by the weekend check.
 const june19=new Date(Date.UTC(year,5,19));
 const midsummer=iso(new Date(june19.getTime()+(5-june19.getUTCDay()+7)%7*86400000));
 return new Set([...fixed,...movable,midsummer]);
}

function workingDates(from:string,to:string):string[] {
 const start=Date.parse(from+'T00:00:00Z'),end=Date.parse(to+'T00:00:00Z');
 if(!Number.isFinite(start)||!Number.isFinite(end)||start>end||end-start>366*86400000)return [];
 const holidays=new Map<number,Set<string>>(),dates:string[]=[];
 for(let t=start;t<=end;t+=86400000){
  const date=new Date(t),day=date.getUTCDay(),year=date.getUTCFullYear(),iso=date.toISOString().slice(0,10);
  if(!holidays.has(year))holidays.set(year,nonWorkingDates(year));
  if(day!==0&&day!==6&&!holidays.get(year)!.has(iso))dates.push(iso);
 }
 return dates;
}

/** 25 annual vacation days with the vehicle idle. Dates unknown: prorate over
 * each calendar year's eligible workdays, including fiscal periods crossing years.
 * Fractional days are a planning assumption, never claimed as observed operation. */
export function productiveDayBasis(from:string,to:string):{days:number;workdays:number;vacationDays:number} {
 const dates=workingDates(from,to),byYear=new Map<string,number>();
 for(const date of dates){const year=date.slice(0,4);byYear.set(year,(byYear.get(year)??0)+1);}
 let vacationDays=0;
 for(const [year,count] of byYear){const annual=workingDates(`${year}-01-01`,`${year}-12-31`).length;vacationDays+=count*Math.min(25,annual)/annual;}
 return {days:dates.length-vacationDays,workdays:dates.length,vacationDays};
}

export function unitDailyRevenueTargets(report:TransportScorecard):Record<string,DailyRevenueTarget> {
 const {days}=productiveDayBasis(report.from,report.to);
 return Object.fromEntries(report.units.filter(u=>u.unit_id).map(u=>[u.unit_id!,dailyRevenueTarget(u.revenue,u.cost,u.missing_targets>0?null:u.target_margin_percent,days)]));
}
