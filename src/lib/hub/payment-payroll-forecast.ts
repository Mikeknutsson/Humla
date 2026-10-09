import {dateValue,departments} from './payment-forecast';
export type PayrollMonth={center:string;month:string;gross:number;days:number;reports:number;firstDate:string;lastDate:string};
export type PayrollSource={synced_at:string;settings_match:boolean;rows:PayrollMonth[];reason?:string;settings?:{monthly_salary:number;weekly_hours:number;overtime_multiplier:number;removed_load:number}};
export type PayrollEstimate={center:string;payDate:string;workMonth:string;amount:number|null;method:'registered'|'historical_trend'|'latest_month'|'missing';sourceMonth:string|null;baseline:number|null;factor:number|null};
const day=86400000,iso=(n:number)=>new Date(n).toISOString().slice(0,10),round=(n:number)=>Math.round(n*100)/100;
const month=(n:number)=>{const d=new Date(n);return Date.UTC(d.getUTCFullYear(),d.getUTCMonth(),1)};
const shift=(n:number,m:number)=>{const d=new Date(n);return Date.UTC(d.getUTCFullYear(),d.getUTCMonth()+m,1)};
export function payrollForecast(source:PayrollSource,asOf:string,weeks:{from:string;to:string}[]){
 const now=dateValue(asOf),currentMonth=month(now),trendTo=currentMonth-day;
 const d=new Date(trendTo),trendFrom=Date.UTC(d.getUTCMonth()>=8?d.getUTCFullYear():d.getUTCFullYear()-1,8,1);
 const valid=(r:PayrollMonth)=>Number.isFinite(r.gross)&&r.gross>=0&&Number.isInteger(r.days)&&r.days>=0&&Number.isInteger(r.reports)&&r.reports>=r.days;
 if(!Array.isArray(source.rows)||source.rows.some(r=>!valid(r)))throw Error('Ogiltigt TransPA-löneunderlag');
 const keys=new Set<string>();for(const r of source.rows){dateValue(r.month);dateValue(r.firstDate);dateValue(r.lastDate);const key=r.center+':'+r.month;if(keys.has(key))throw Error('Dubblett i TransPA-lönemånad');keys.add(key);}
 const adequateDays=(r:PayrollMonth|undefined)=>{
  if(!r||!source.settings_match)return false;
  const start=dateValue(r.month),end=shift(start,1)-day;
  if(start!==month(start)||end>=currentMonth)return false;
  let weekdays=0;for(let n=start;n<=end;n+=day)if(![0,6].includes(new Date(n).getUTCDay()))weekdays++;
  // Availability gate, not certification of a complete payroll export.
  return r.days>=Math.ceil(weekdays*0.6);
 };
 const complete=(r:PayrollMonth|undefined)=>{
  if(!adequateDays(r)||!r)return false;
  const latest=source.rows.filter(s=>s.center===r.center&&adequateDays(s)).sort((a,b)=>b.month.localeCompare(a.month))[0];
  // Single-person historical imports cannot stand in for a whole department.
  return r.reports>=Math.ceil((latest?.reports??r.reports)*0.25);
 };
 const find=(center:string,n:number)=>source.rows.find(r=>r.center===center&&r.month===iso(n));
 const estimate=(center:string,payMonth:number):PayrollEstimate=>{
  const payDate=iso(payMonth+24*day),work=shift(payMonth,-1),workMonth=iso(work);
  const base:PayrollEstimate={center,payDate,workMonth,amount:null,method:'missing',sourceMonth:null,baseline:null,factor:null};
  if(!source.settings_match)return base;
  if(work<currentMonth){const recorded=find(center,work);return complete(recorded)?{...base,amount:round(recorded!.gross),method:'registered',sourceMonth:workMonth}:base;}
  const prior=find(center,shift(work,-12));let old=0,recent=0,hasTrend=true;
  for(let n=trendFrom;n<currentMonth;n=shift(n,1)){
   const a=find(center,n),b=find(center,shift(n,-12));
   if(!complete(a)||!complete(b)){hasTrend=false;break;}
   recent+=a!.gross;old+=b!.gross;
  }
  if(complete(prior)&&hasTrend&&old>0){const factor=recent/old;return {...base,amount:round(prior!.gross*factor),method:'historical_trend',sourceMonth:prior!.month,baseline:prior!.gross,factor};}
  // Sparse historical imports must not create huge year-on-year factors.
  const latest=source.rows.filter(r=>r.center===center&&complete(r)).sort((a,b)=>b.month.localeCompare(a.month))[0];
  // A stale month is not a suitable fallback for current/future staffing.
  if(latest&&dateValue(latest.month)>=shift(currentMonth,-2))return {...base,amount:round(latest.gross),method:'latest_month',sourceMonth:latest.month,baseline:latest.gross,factor:1};
  return base;
 };
 const details:PayrollEstimate[]=[];
 const result=weeks.map(w=>{
  const start=dateValue(w.from),end=dateValue(w.to);
  const parts=Object.keys(departments).map(center=>{
   let amount:number|null=0;
   for(let n=month(start);n<=month(end);n=shift(n,1)){
    const pay=n+24*day;if(pay<start||pay>end)continue;
    const e=estimate(center,n);details.push(e);amount=e.amount;
   }
   return {center,amount};
  });
  return {from:w.from,parts,total:parts.some(p=>p.amount===null)?null:round(parts.reduce((s,p)=>s+p.amount!,0))};
 });
 const warnings=['Löner är uppskattad bruttolön från TransPA, inte verifierad nettoutbetalning. PO-pålägg, arbetsgivaravgifter, pension, skatt, semesterlön och OB räknas inte som verifierade utbetalningar här. Den 25:e används som kalenderdatum utan automatisk helgjustering.'];
 warnings.push('Löneprognosen särredovisas och ingår inte i Kostnader — prognos eller Netto.');
 if(details.some(d=>d.method==='latest_month'))warnings.push('Jämförbar lönehistorik/trend saknas: senaste tillräckligt rapporterade avslutade månad används som reservprognos.');
 if(details.some(d=>d.method==='missing'))warnings.push('En avdelning saknar tillräckligt löneunderlag. Dess lönerad visas ofullständig; kostnader och netto påverkas inte av saknat löneunderlag.');
 if(!source.settings_match)warnings.push(source.reason||'Löneinställningar och Hub-underlag är inte synkroniserade.');
 const unassignedGross=round(source.rows.filter(r=>!Object.hasOwn(departments,r.center)).reduce((s,r)=>s+r.gross,0));
 if(unassignedGross)warnings.push('TransPA-belopp utan bekräftat kostnadsställe undantas och behöver fördelas i Hubben.');
 return {weeks:result,details,warnings,unassignedGross,settings:source.settings,syncedAt:source.synced_at};
}
