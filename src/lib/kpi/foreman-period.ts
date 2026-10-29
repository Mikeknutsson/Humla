export type ForemanPeriodMode='ytd'|'revenue'|'year'|'month';
export type ForemanPeriod={fiscalYear:number;currentFiscalYear:number;mode:ForemanPeriodMode;month:number;from:string;to:string|null;revenueThrough:string|null};
const iso=(y:number,m:number,d:number)=>`${y}-${String(m).padStart(2,'0')}-${String(d).padStart(2,'0')}`;
const validDate=(s:string)=>/^\d{4}-\d{2}-\d{2}$/.test(s)&&!Number.isNaN(Date.parse(s))&&new Date(s+'T00:00:00Z').toISOString().slice(0,10)===s;

export function foremanFiscalYear(value:string|undefined,today:{year:number;month:number}) {
 const year=value===undefined?(today.month>=9?today.year:today.year-1):Number(value);
 if(!Number.isInteger(year)||year<2001||year>2100)throw new Error('Ogiltigt verksamhetsår.');
 return year;
}

/** Both revenue and cost queries receive the same resolved inclusive date range. */
export function resolveForemanPeriod(q:Record<string,string|undefined>,revenueThrough:string|null,today:{year:number;month:number;day:number}):ForemanPeriod {
 const fiscalYear=foremanFiscalYear(q.fiscal_year,today),currentFiscalYear=foremanFiscalYear(undefined,today);
 const mode=q.period_mode??'ytd';
 if(!['ytd','revenue','year','month'].includes(mode))throw new Error('Ogiltigt periodval.');
 const month=q.month===undefined?today.month:Number(q.month);
 if(!Number.isInteger(month)||month<1||month>12)throw new Error('Ogiltig månad.');
 let from=iso(fiscalYear,9,1),to:string|null=iso(fiscalYear+1,8,31);
 const yearEnd=to;
 if(revenueThrough!=null&&(!validDate(revenueThrough)||revenueThrough<from||revenueThrough>yearEnd))throw new Error('Ogiltigt intäktsdatum.');
 if(mode==='ytd'){
  if(fiscalYear>currentFiscalYear)throw new Error('YTD kan inte väljas för ett framtida verksamhetsår.');
  const endYear=fiscalYear+(today.month<9?1:0);
  to=iso(endYear,today.month,Math.min(today.day,new Date(Date.UTC(endYear,today.month,0)).getUTCDate()));
 }else if(mode==='revenue'){
  to=revenueThrough==null?null:(revenueThrough>iso(today.year,today.month,today.day)?iso(today.year,today.month,today.day):revenueThrough);
 }else if(mode==='month'){
  const year=fiscalYear+(month<9?1:0);from=iso(year,month,1);to=iso(year,month,new Date(Date.UTC(year,month,0)).getUTCDate());
 }
 return {fiscalYear,currentFiscalYear,mode:mode as ForemanPeriodMode,month,from,to,revenueThrough};
}

export function foremanPeriodQuery(p:Pick<ForemanPeriod,'fiscalYear'|'mode'|'month'>,userId?:string|null) {
 const q=new URLSearchParams({fiscal_year:String(p.fiscalYear),period_mode:p.mode});
 if(p.mode==='month')q.set('month',String(p.month));
 if(userId)q.set('user_id',userId);
 return q;
}
