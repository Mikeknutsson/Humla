import {fiscalMonths,parseMonthPeriod,stockholmToday,previousYearDate} from './period';

export type ManagementPeriod={from:string;to:string;fiscalYear:number;months:number[];month:number};
export function managementRange(from:string,to:string):ManagementPeriod {
 const valid=(s:string)=>/^\d{4}-\d{2}-\d{2}$/.test(s)&&Number.isFinite(Date.parse(s+'T00:00:00Z'))&&new Date(s+'T00:00:00Z').toISOString().slice(0,10)===s;
 if(!valid(from)||!valid(to)||from>to)throw Error('Välj ett giltigt datumintervall.');
 const start=new Date(from+'T00:00:00Z'),end=new Date(to+'T00:00:00Z');
 const fiscalYear=start.getUTCFullYear()-(start.getUTCMonth()<8?1:0);
 if(fiscalYear<2001||fiscalYear>2100||to>`${fiscalYear+1}-08-31`)throw Error('Välj en period inom ett och samma verksamhetsår (september–augusti).');
 const months:number[]=[];
 for(let d=new Date(Date.UTC(start.getUTCFullYear(),start.getUTCMonth(),1));d<=end;d=new Date(Date.UTC(d.getUTCFullYear(),d.getUTCMonth()+1,1)))months.push(d.getUTCMonth()+1);
 return {from,to,fiscalYear,months,month:end.getUTCMonth()+1};
}
export function managementPreset(preset:string,year:number,month:number,now=new Date()):ManagementPeriod {
 const today=stockholmToday(now),currentYear=today.month>=9?today.year:today.year-1;
 if(!Number.isInteger(year)||year<2001||year>2100||!fiscalMonths.includes(month))throw Error('Ogiltigt verksamhetsår eller månad.');
 if(preset==='ytd'){
  if(year>currentYear)throw Error('YTD kan inte väljas för ett framtida verksamhetsår.');
  const y=year+(today.month<9?1:0),day=Math.min(today.day,new Date(Date.UTC(y,today.month,0)).getUTCDate());
  return managementRange(`${year}-09-01`,`${y}-${String(today.month).padStart(2,'0')}-${String(day).padStart(2,'0')}`);
 }
 const quarter=/^q([1-4])$/.exec(preset);
 const months=preset==='year'?fiscalMonths:quarter?fiscalMonths.slice((Number(quarter[1])-1)*3,Number(quarter[1])*3):preset==='month'?[month]:null;
 if(!months)throw Error('Ogiltigt periodval.');
 const first=months[0],last=months.at(-1)!,endYear=year+(last<9?1:0);
 return managementRange(`${year+(first<9?1:0)}-${String(first).padStart(2,'0')}-01`,`${endYear}-${String(last).padStart(2,'0')}-${new Date(Date.UTC(endYear,last,0)).getUTCDate()}`);
}
export function managementPeriod(params:URLSearchParams,now=new Date()):ManagementPeriod {
 const from=params.get('report_from'),to=params.get('report_to');
 if(from!==null||to!==null)return managementRange(from??'',to??'');
 const p=parseMonthPeriod(params.get('fiscal_year')??undefined,params.get('report_month')??params.get('months')??undefined,now,params.get('period_mode')??undefined);
 if(p.mode==='ytd')return managementRange(`${p.fiscalYear}-09-01`,p.to!);
 if(p.months.length<12){
  const start=managementPreset('month',p.fiscalYear,p.months[0],now),end=managementPreset('month',p.fiscalYear,p.months.at(-1)!,now);
  const range=managementRange(start.from,end.to);
  if(range.months.length!==p.months.length)throw Error('Välj sammanhängande månader i månadsrapporten.');
  return range;
 }
 const today=stockholmToday(now),previous=today.month===1?12:today.month-1;
 return managementPreset('month',p.fiscalYear===p.currentYear&&today.month===9?p.fiscalYear-1:p.fiscalYear,p.fiscalYear===p.currentYear?previous:8,now);
}
export function previousManagementPeriod(p:ManagementPeriod){return managementRange(previousYearDate(p.from),previousYearDate(p.to));}
