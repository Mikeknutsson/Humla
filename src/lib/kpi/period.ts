export const fiscalMonths = [9,10,11,12,1,2,3,4,5,6,7,8];
export const monthLabels = ['Sep','Okt','Nov','Dec','Jan','Feb','Mar','Apr','Maj','Jun','Jul','Aug'];
export type MonthPeriod = { fiscalYear:number; months:number[]; currentYear:number; currentMonth:number };
export function stockholmToday(now=new Date()) {
 const parts=new Intl.DateTimeFormat('sv-SE',{timeZone:'Europe/Stockholm',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(now);
 return {year:Number(parts.find(p=>p.type==='year')!.value),month:Number(parts.find(p=>p.type==='month')!.value)};
}
export function parseMonthPeriod(year:string|undefined,months:string|undefined,now=new Date()):MonthPeriod {
 const today=stockholmToday(now);const currentYear=today.month>=9?today.year:today.year-1;
 const fiscalYear=year===undefined?currentYear:Number(year);
 if(!Number.isInteger(fiscalYear)||fiscalYear<2001||fiscalYear>2100)throw new Error('Ogiltigt verksamhetsår.');
 const selected=months===undefined?fiscalMonths:months.split(',').map(Number);
 if(!selected.length||selected.some(m=>!Number.isInteger(m)||m<1||m>12))throw new Error('Välj minst en giltig månad.');
 return {fiscalYear,months:fiscalMonths.filter(m=>selected.includes(m)),currentYear,currentMonth:today.month};
}
export function monthPeriodQuery(period:Pick<MonthPeriod,'fiscalYear'|'months'>) {
 return new URLSearchParams({from:`${period.fiscalYear}-09-01`,to:`${period.fiscalYear+1}-08-31`,fiscal_year:String(period.fiscalYear),months:period.months.join(',')}).toString();
}
