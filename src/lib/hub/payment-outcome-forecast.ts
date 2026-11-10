import {dateValue,departments,costOnly,emptyIncoming,availableForecast,paymentForecast,type Payment,type PaymentForecast} from './payment-forecast';
import {payrollForecast,type PayrollSource} from './payment-payroll-forecast';
import {reviewedTrend,broadWeeklyBaseline,stenaMonthlyEvidence,monthDate,type EvidenceRow,type PeriodReview,type StenaMonth} from './payment-evidence-model';
export type Outcome={center:string;kind:'in'|'out';date:string;amount:number;party:string;invoiceDate:string|null;internal:boolean;oneOff?:boolean;id?:string;rowId?:string|null;reference?:string;description?:string;account?:string;project?:string;paymentDate?:string;source?:string;amountStatus?:'history'|'settled'|null};
export type ForecastBreakdown={weekFrom:string;center:string;kind:'in'|'out';internal:boolean;baseline:number|null;factor:number|null;known:number;forecast:number|null;total:number|null;trendPrevious:number;trendCurrent:number;excludedBaseline:number;baselineRows:string[];knownRows:string[];trendPreviousRows:string[];trendCurrentRows:string[];spike:boolean;scope:'ordinary'|'stena';method:'weekly_average_13'|'stena_month';baselineFrom:string;baselineTo:string;reviewedTrendMonths:string[];trendStatus:'reviewed'|'historical_only';periodReviewed?:boolean};
export type OutcomeSource={synced_at:string;rows:Outcome[];review_rows:number;review_amount:number;generation?:string;periodReviews?:PeriodReview[];reviewBasis?:Record<string,string>;controls?:{scope:string;from:string;to:string;supplierRows:number;supplierAmount:number;excludedNonPayments:{reason:string;rows:number;amount:number}[];stena?:{rows:number;settledRows:number;settledAmount:number;historyRows:number;historyAmount:number;unresolvedRows:number;replacedWorkifyRows:number}}};
const day=86400000,iso=(n:number)=>new Date(n).toISOString().slice(0,10),round=(n:number)=>Math.round(n*100)/100;
const name=(s:string)=>s.toLocaleLowerCase('sv-SE').normalize('NFKC').replace(/[^\p{L}\p{N}]+/gu,' ').trim();
const calendarMonth=(n:number)=>{const d=new Date(n);return Date.UTC(d.getUTCFullYear(),d.getUTCMonth(),1)};
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
export type AutomaticForecast=PaymentForecast&{automatic:{sourceFetchedAt?:string;sourceReused?:boolean;syncedAt:string;trendFrom:string;trendTo:string;warnings:string[];reviewRows:number;reviewAmount:number;supplierDays:number;breakdown:ForecastBreakdown[];auditRows:Outcome[];controls?:OutcomeSource['controls'];periodReviews:PeriodReview[];reviewBasis:Record<string,string>;stenaMonths:StenaMonth[];transfer:TransferSummary;model:'evidence-v2';payroll?:ReturnType<typeof payrollForecast>}};
export type TransferSummary={from:string;to:string;incoming:number|null;outgoing:number|null;net:number|null;registeredIncoming:number;registeredOutgoing:number;estimatedIncoming:number|null;estimatedOutgoing:number|null;registeredIncomingShare:number|null;registeredOutgoingShare:number|null;missing:{weekFrom:string;center:string;kind:'in'|'out'}[];currency:'SEK';vatBasis:'excluding_vat'};
/** Expected activity-based payments; no ledger, bank balance or verified payment status is inferred. */
export function outcomeForecast(source:OutcomeSource,asOf:string,supplierDays=30,periodOffset=0,payrollSource?:PayrollSource):AutomaticForecast{
 const now=dateValue(asOf);if(!Number.isInteger(supplierDays)||supplierDays<0||supplierDays>180)throw Error('Leverantörstid måste vara 0–180 dagar');
 const reviews=source.periodReviews??[],warnings=[
  'Beloppen är exklusive moms och bygger på Workify/Stena/NeXT. Betalningsdagar är antaganden; ingen öppen reskontra eller faktisk betalningsstatus har verifierats.',
  'Netto är före löner och moms. Löner särredovisas; beloppet är ingen banksaldoprognos.',
  'Vanliga betalningar använder snittet av 13 jämförbara historiska veckor. En ändrad veckobas flyttar aldrig redan registrerade belopp.',
 ];
 const rows:EvidenceRow[]=source.rows.map((r,i)=>({...r,amount:Number(r.amount),id:'outcome:'+i,dateValue:dateValue(r.date),paymentDate:expectedPaymentDate(r,supplierDays),stena:r.kind==='in'&&!r.internal&&customerTerm(r.party).code==='stena_month_end'})).filter(r=>r.dateValue<=now);
 if(rows.some(r=>!Number.isFinite(r.amount)))throw Error('Ogiltigt belopp i prognosunderlaget');
 const result=paymentForecast({asOf,periodOffset,ledger:[],history:[],historyFrom:'',historyTo:''});
 const payroll=payrollSource?payrollForecast(payrollSource,asOf,result.weeks):undefined;
 const stenaMonths=stenaMonthlyEvidence(rows,reviews,asOf,result.weeks).filter(s=>Object.hasOwn(departments,s.center)&&!costOnly(s.center));
 const audit=new Map<string,Outcome>(),lookup=new Map(rows.map(r=>[r.id,r]));
 const record=(r:EvidenceRow)=>{const {dateValue:_,stena:__,...value}=r;audit.set(r.id,value);return r.id;};
 const recordIds=(ids:string[])=>ids.map(id=>{const r=lookup.get(id);if(r)record(r);return id;});
 const breakdown:ForecastBreakdown[]=[];
 const sum=(rs:EvidenceRow[])=>round(rs.reduce((s,r)=>s+r.amount,0));
 for(const week of result.weeks){
  for(const part of week.parts)for(const internal of [false,true])for(const [key,kind]of[['incoming','in'],['outgoing','out']]as const){
   if(costOnly(part.center)&&kind==='in'){if(internal)part.internal.incoming=0;else part.incoming=emptyIncoming();continue;}
   const ordinary=rows.filter(r=>r.center===part.center&&r.kind===kind&&r.internal===internal&&!r.stena);
   const base=broadWeeklyBaseline(ordinary,week.from),trend=reviewedTrend(ordinary,reviews,asOf,'ordinary',part.center,kind);
   const factor=trend.factor??1;
   const knownRows=ordinary.filter(r=>r.paymentDate>=week.from&&r.paymentDate<=week.to),known=sum(knownRows);
   const remaining=base.amount===null?null:round(Math.max(0,base.amount*factor-known));
   const parties=new Map<string,number>();for(const r of base.rows.filter(r=>!r.oneOff))parties.set(r.party,(parties.get(r.party)??0)+Math.abs(r.amount));
   const absolute=Array.from(parties.values()).reduce((s,n)=>s+n,0);
   const entry:ForecastBreakdown={weekFrom:week.from,center:part.center,kind,internal,baseline:base.amount,factor:base.amount===null?null:factor,known,forecast:remaining,total:remaining===null?null:round(known+remaining),trendPrevious:trend.previous,trendCurrent:trend.current,excludedBaseline:base.excluded,baselineRows:base.rows.map(record),knownRows:knownRows.map(record),trendPreviousRows:trend.previousRows.map(record),trendCurrentRows:trend.currentRows.map(record),spike:kind==='out'&&absolute/13>=50000&&Array.from(parties.values()).some(n=>n>=absolute/2),scope:'ordinary',method:'weekly_average_13',baselineFrom:base.from,baselineTo:base.to,reviewedTrendMonths:trend.months,trendStatus:trend.factor===null?'historical_only':'reviewed'};
   const entries=[entry];breakdown.push(entry);
   if(!internal&&kind==='in')for(const cohort of stenaMonths.filter(s=>s.center===part.center&&s.paymentDate>=week.from&&s.paymentDate<=week.to)){
    const stenaRows=rows.filter(r=>r.stena&&r.center===part.center),stenaTrend=reviewedTrend(stenaRows,reviews,asOf,'stena',part.center,'in');
    const priorYear=Number(cohort.deliveryMonth.slice(0,4))-1,priorMonth=`${priorYear}${cohort.deliveryMonth.slice(4)}`;
    const priorEnd=new Date(dateValue(priorMonth));priorEnd.setUTCMonth(priorEnd.getUTCMonth()+1);priorEnd.setUTCDate(0);
    const stenaEntry:ForecastBreakdown={...entry,scope:'stena',method:'stena_month',baseline:cohort.baseline,factor:cohort.factor,known:cohort.registered,forecast:cohort.remaining,total:cohort.total,trendPrevious:stenaTrend.previous,trendCurrent:stenaTrend.current,excludedBaseline:0,baselineRows:recordIds(cohort.baselineIds),knownRows:recordIds(cohort.knownIds),trendPreviousRows:stenaTrend.previousRows.map(record),trendCurrentRows:stenaTrend.currentRows.map(record),baselineFrom:priorMonth,baselineTo:priorEnd.toISOString().slice(0,10),reviewedTrendMonths:stenaTrend.months,trendStatus:stenaTrend.factor===null?'historical_only':'reviewed',periodReviewed:cohort.reviewed,spike:false};
    entries.push(stenaEntry);breakdown.push(stenaEntry);
   }
   const totalFor=(field:'forecast'|'total'|'baseline')=>entries.some(e=>e[field]===null)?null:round(entries.reduce((s,e)=>s+e[field]!,0));
   if(internal)part.internal[key]=totalFor('total');
   else part[key]={known:round(entries.reduce((s,e)=>s+e.known,0)),forecast:totalFor('forecast'),total:totalFor('total'),baseline:totalFor('baseline'),factor:entries.length===1?entry.factor:null};
  }
  for(const key of['incoming','outgoing']as const)week.internal[key]=week.parts.some(p=>p.internal[key]===null)?null:round(week.parts.reduce((s,p)=>s+p.internal[key]!,0));
  if(payroll){const salary=payroll.weeks.find(s=>s.from===week.from)!;week.total.payroll=salary.total;for(const p of week.parts)p.payroll=salary.parts.find(s=>s.center===p.center)?.amount??null;}
  for(const p of week.parts)p.net=p.incoming.total===null||p.outgoing.total===null?null:round(p.incoming.total-p.outgoing.total);
  for(const key of['incoming','outgoing']as const)week.total[key]={known:round(week.parts.reduce((s,p)=>s+p[key].known,0)),forecast:week.parts.some(p=>p[key].forecast===null)?null:round(week.parts.reduce((s,p)=>s+p[key].forecast!,0)),total:week.parts.some(p=>p[key].total===null)?null:round(week.parts.reduce((s,p)=>s+p[key].total!,0))};
  week.total.net=week.parts.some(p=>p.net===null)?null:round(week.parts.reduce((s,p)=>s+p.net!,0));week.available=availableForecast(week.parts);
 }
 const aggregate=(key:'incoming'|'outgoing',field:'forecast'|'total')=>result.weeks.some(w=>w.total[key][field]===null)?null:round(result.weeks.reduce((s,w)=>s+w.total[key][field]!,0));
 const incoming=aggregate('incoming','total'),outgoing=aggregate('outgoing','total');
 const registeredIncoming=round(result.weeks.reduce((s,w)=>s+w.total.incoming.known,0)),registeredOutgoing=round(result.weeks.reduce((s,w)=>s+w.total.outgoing.known,0));
 const share=(known:number,total:number|null)=>total!==null&&total>0?round(Math.min(100,Math.max(0,known/total*100))):null;
 const transfer:TransferSummary={from:result.weeks[0].from,to:result.weeks.at(-1)!.to,incoming,outgoing,net:incoming===null||outgoing===null?null:round(incoming-outgoing),registeredIncoming,registeredOutgoing,estimatedIncoming:aggregate('incoming','forecast'),estimatedOutgoing:aggregate('outgoing','forecast'),registeredIncomingShare:share(registeredIncoming,incoming),registeredOutgoingShare:share(registeredOutgoing,outgoing),missing:breakdown.filter(d=>!d.internal&&d.total===null).map(d=>({weekFrom:d.weekFrom,center:d.center,kind:d.kind})),currency:'SEK',vatBasis:'excluding_vat'};
 const toPayment=(r:EvidenceRow):Payment=>({id:r.id,center:r.center,kind:r.kind,date:r.paymentDate,amount:r.amount,internal:r.internal});
 result.internal={ledger:[],history:rows.filter(r=>r.internal).map(toPayment)};result.excludedInternal=result.internal.history.length;
 result.unknown=rows.filter(r=>!r.internal&&(!Object.hasOwn(departments,r.center)||(costOnly(r.center)&&r.kind==='in'))).map(toPayment);result.overdue=[];
 result.historyCoverage={from:rows.length?rows.reduce((v,r)=>v<r.date?v:r.date,rows[0].date):'',to:rows.length?rows.reduce((v,r)=>v>r.date?v:r.date,rows[0].date):''};
 if(breakdown.some(d=>!d.internal&&d.trendStatus==='historical_only'&&d.forecast!==null))warnings.push('Historikreserv används utan tillväxtpåslag där färre än tre avstämda månadspar finns. Varken kalenderns månadsskifte eller ett nytt verksamhetsår skapar automatiskt en ny trend.');
 if(transfer.missing.length)warnings.push('Komplett total saknas för delar av perioden. Registrerade belopp och delprognoser visas; inget ofullständigt nettobelopp får föras över som komplett prognos.');
 if(source.synced_at&&now-dateValue(source.synced_at.slice(0,10))>2*day)warnings.push(`Underlaget uppdaterades senast ${source.synced_at.slice(0,10)}. Nyare importer kan saknas.`);
 if(reviews.some(r=>r.reviewed&&r.stale))warnings.push('Underlag har ändrats efter en månadsavstämning. Den månaden används inte som avstämd förrän den har kontrollerats igen.');
 if(source.review_rows)warnings.push(`${source.review_rows} rader väntar på granskning och ingår inte.`);
 if(payroll)warnings.push(...payroll.warnings);
 if(stenaMonths.length)warnings.push('Stena följs per leveransmånad med betalning 45 dagar efter månadens slut. Avräknat är en beloppsgrund, inte bevis på betalning. En uttryckligen avstämd leveransmånad får ingen extra historikreserv.');
 result.method='Registrerat + återstående uppskattning. Ordinarie betalningar: snitt av 13 jämförbara veckor 52 veckor bakåt. Trend: högst sex par av uttryckligen avstämda månader inom senaste året; minst tre par krävs. Annars används historik utan tillväxtpåslag. Stena: egen leveransmånad och samma månad föregående år, separat trend; avstämd månad använder endast registrerat belopp. Registrerat räknas av en gång inom respektive del. Alla betalningsdatum är antagna. Exklusive moms; löner särredovisas utanför kostnader och netto.';
 const trendEnd=new Date(Date.UTC(new Date(now).getUTCFullYear(),new Date(now).getUTCMonth(),0)).toISOString().slice(0,10),trendFrom=new Date(Date.UTC(new Date(now).getUTCFullYear(),new Date(now).getUTCMonth()-12,1)).toISOString().slice(0,10);
 return {...result,automatic:{model:'evidence-v2',syncedAt:source.synced_at,trendFrom,trendTo:trendEnd,warnings,reviewRows:source.review_rows,reviewAmount:source.review_amount,supplierDays,breakdown,auditRows:Array.from(audit.values()),controls:source.controls,payroll,periodReviews:reviews,reviewBasis:source.reviewBasis??{},stenaMonths,transfer}};
}
