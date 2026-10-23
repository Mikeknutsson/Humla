export const fiscalMonths = [9,10,11,12,1,2,3,4,5,6,7,8];
export const monthLabels = ['Sep','Okt','Nov','Dec','Jan','Feb','Mar','Apr','Maj','Jun','Jul','Aug'];
export type MonthPeriod = { fiscalYear:number; months:number[]; currentYear:number; currentMonth:number; mode?:'ytd'; to?:string };
export function stockholmToday(now=new Date()) {
 const parts=new Intl.DateTimeFormat('sv-SE',{timeZone:'Europe/Stockholm',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(now);
 return {year:Number(parts.find(p=>p.type==='year')!.value),month:Number(parts.find(p=>p.type==='month')!.value),day:Number(parts.find(p=>p.type==='day')!.value)};
}
export function parseMonthPeriod(year:string|undefined,months:string|undefined,now=new Date(),mode?:string):MonthPeriod {
 const today=stockholmToday(now);const currentYear=today.month>=9?today.year:today.year-1;
 const fiscalYear=year===undefined?currentYear:Number(year);
 if(!Number.isInteger(fiscalYear)||fiscalYear<2001||fiscalYear>2100)throw new Error('Ogiltigt verksamhetsår.');
 if(mode!==undefined&&mode!=='ytd')throw new Error('Ogiltigt periodläge.');
 if(mode==='ytd'){
  if(fiscalYear>currentYear)throw new Error('YTD kan inte väljas för ett framtida verksamhetsår.');
  const endYear=fiscalYear+(today.month<9?1:0);
  const day=Math.min(today.day,new Date(Date.UTC(endYear,today.month,0)).getUTCDate());
  return {fiscalYear,months:fiscalMonths.slice(0,fiscalMonths.indexOf(today.month)+1),currentYear,currentMonth:today.month,mode:'ytd',to:`${endYear}-${String(today.month).padStart(2,'0')}-${String(day).padStart(2,'0')}`};
 }
 const selected=months===undefined?fiscalMonths:months.split(',').map(Number);
 if(!selected.length||selected.some(m=>!Number.isInteger(m)||m<1||m>12))throw new Error('Välj minst en giltig månad.');
 return {fiscalYear,months:fiscalMonths.filter(m=>selected.includes(m)),currentYear,currentMonth:today.month};
}
export function monthPeriodQuery(period:Pick<MonthPeriod,'fiscalYear'|'months'|'mode'|'to'>) {
 const p=new URLSearchParams({from:`${period.fiscalYear}-09-01`,to:period.to??`${period.fiscalYear+1}-08-31`,fiscal_year:String(period.fiscalYear),months:period.months.join(',')});
 if(period.mode==='ytd'){p.set('period_mode','ytd');p.set('date_from',p.get('from')!);p.set('date_to',period.to!);}
 return p.toString();
}

export function periodFilters(period:MonthPeriod,filters:Record<string,string>){
 if(period.mode!=='ytd')return filters;
 const from=`${period.fiscalYear}-09-01`,to=period.to!;
 return {...filters,period_mode:'ytd',date_from:filters.date_from&&filters.date_from>from?filters.date_from:from,date_to:filters.date_to&&filters.date_to<to?filters.date_to:to};
}

export function previousYearDate(value:string){
 const [year,month,day]=value.split('-').map(Number);
 return `${year-1}-${String(month).padStart(2,'0')}-${String(Math.min(day,new Date(Date.UTC(year-1,month,0)).getUTCDate())).padStart(2,'0')}`;
}

// Keep bookmarked complete-month date ranges aligned between Overview and KPI.
export function monthPeriodFromDates(from:string|undefined,to:string|undefined,now=new Date()):MonthPeriod|undefined {
 if(!from||!to||!/^\d{4}-\d{2}-\d{2}$/.test(from)||!/^\d{4}-\d{2}-\d{2}$/.test(to))return undefined;
 const start=new Date(from+'T00:00:00Z'),end=new Date(to+'T00:00:00Z');
 if(Number.isNaN(start.getTime())||Number.isNaN(end.getTime())||start.toISOString().slice(0,10)!==from||end.toISOString().slice(0,10)!==to||start>end||start.getUTCDate()!==1)return undefined;
 if(new Date(Date.UTC(end.getUTCFullYear(),end.getUTCMonth()+1,0)).getUTCDate()!==end.getUTCDate())return undefined;
 const year=start.getUTCMonth()>=8?start.getUTCFullYear():start.getUTCFullYear()-1;
 if(end.getUTCFullYear()!==year+(end.getUTCMonth()<8?1:0))return undefined;
 const months:number[]=[];
 for(let date=new Date(start);date<=end;date=new Date(Date.UTC(date.getUTCFullYear(),date.getUTCMonth()+1,1)))months.push(date.getUTCMonth()+1);
 return parseMonthPeriod(String(year),months.join(','),now);
}
