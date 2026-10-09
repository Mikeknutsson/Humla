import {monthPeriodFromDates,monthPeriodQuery,parseMonthPeriod,type MonthPeriod} from './period';

export type ProjectPeriod={period:MonthPeriod;from:string;to:string;months:number[]|null;custom:boolean};
const iso=(date:Date)=>date.toISOString().slice(0,10);
const validDate=(value:string)=>/^\d{4}-\d{2}-\d{2}$/.test(value)&&!Number.isNaN(Date.parse(value+'T00:00:00Z'))&&iso(new Date(value+'T00:00:00Z'))===value;

export function parseProjectPeriod(q:Record<string,string|undefined>,now=new Date()):ProjectPeriod {
 let period=parseMonthPeriod(q.fiscal_year,q.months,now);
 if(q.fiscal_year===undefined&&q.months===undefined&&(q.from||q.to)){
  const from=q.from??`${period.fiscalYear}-09-01`,to=q.to??`${period.fiscalYear+1}-08-31`;
  if(!validDate(from)||!validDate(to)||to<from||(Date.parse(to)-Date.parse(from))/86400000>1096)throw Error('Ogiltig period.');
  const inferred=monthPeriodFromDates(from,to,now);
  if(!inferred){
   const year=Number(from.slice(0,4))-(Number(from.slice(5,7))<9?1:0);
   return {period:parseMonthPeriod(String(year),undefined,now),from,to,months:null,custom:true};
  }
  period=inferred;
 }
 const first=period.months[0],last=period.months[period.months.length-1];
 const from=iso(new Date(Date.UTC(period.fiscalYear+(first<9?1:0),first-1,1)));
 const to=iso(new Date(Date.UTC(period.fiscalYear+(last<9?1:0),last,0)));
 return {period,from,to,months:period.months,custom:false};
}

export function projectPeriodParams(selection:ProjectPeriod){
 return selection.custom?new URLSearchParams({from:selection.from,to:selection.to}):new URLSearchParams(monthPeriodQuery(selection.period));
}

export function projectReportHref(query:URLSearchParams,changes:Record<string,string|null>){
 const p=new URLSearchParams(query);
 if('from' in changes||'to' in changes){p.delete('fiscal_year');p.delete('months');}
 for(const [key,value] of Object.entries(changes)){p.delete(key);if(value)p.set(key,value);}
 if(!('page' in changes))p.delete('page');
 return '/kpi/projekt?'+p;
}
