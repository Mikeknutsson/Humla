import Link from 'next/link';
import {assignPersonVehicle} from './person-vehicle-action';
import {costColumns,costShare,costShade} from '@/app/_components/kpi-cost-palette';
import unitStyles from '@/app/_components/kpi-economic-units.module.css';
import {ForemanPeriodPicker} from '@/app/_components/foreman-period-picker';
import {foremanFiscalYear,foremanPeriodQuery,resolveForemanPeriod} from '@/lib/kpi/foreman-period';
import {stockholmToday} from '@/lib/kpi/period';
import styles from '@/app/_components/kpi-margin-gauge.module.css';
import trendStyles from '@/app/_components/foreman-result-trend.module.css';
import {KpiTableFrame} from '@/app/_components/kpi-table-frame';
import {KpiDetailShell} from '@/app/_components/kpi-detail-shell';
import {reviewAccess} from '@/lib/hub/review-access';
import {nextResourceBatches,loadNextResourceFile} from '@/lib/kpi/next-resource-source';
import {readNextArticleFile} from '@/lib/kpi/next-article-file';
import {validTransportDate} from '@/lib/kpi/transport-leader';

export const dynamic='force-dynamic';
const base='/kpi/maskiner';
const imported=new Intl.DateTimeFormat('sv-SE',{dateStyle:'short',timeStyle:'short',timeZone:'Europe/Stockholm'});
const currency=new Intl.NumberFormat('sv-SE',{style:'currency',currency:'SEK',maximumFractionDigits:2});
const quantity=new Intl.NumberFormat('sv-SE',{maximumFractionDigits:3});
const money=(value:number|null)=>value===null?'–':currency.format(value);
const number=(value:number|null)=>value===null?'–':quantity.format(value);
const percent=new Intl.NumberFormat('sv-SE',{style:'percent',maximumFractionDigits:1});
function utilization(metrics:MachinePerformance){
 return metrics.available_hours&&metrics.hours!==null?percent.format(metrics.hours/metrics.available_hours):'–';
}
const marginText=(value:number|null|undefined)=>value==null?'–':percent.format(value/100);

function ResultCells({result,margin_pct}:MachineProfit) {
 const tone=result==null?undefined:result<0?unitStyles.negative:unitStyles.positive;
 return <>
  <td className={tone}><strong>{money(result??null)}</strong>{result!=null&&<small>{result<0?'Förlust':result>0?'Överskott':'I balans'}</small>}</td>
  <td className={tone}><strong>{marginText(margin_pct)}</strong></td>
 </>;
}

function costPerBilledHour(metrics:MachinePerformance){
 return metrics.billed_hours&&metrics.billed_hours>0&&metrics.total_cost!=null?money(metrics.total_cost/metrics.billed_hours):'–';
}
const text=(value:unknown)=>typeof value==='string'?value.trim().slice(0,250):'';
type Metrics={rows:number;hours:number|null;value:number|null;value_per_hour:number|null};
function sumPresent(values:(number|null)[]){
 const present=values.filter((value):value is number=>value!==null);
 return present.length?present.reduce((sum,value)=>sum+value,0):null;
}

const usageLabels=['Extern uthyrning','Intern entreprenad','Ej klassificerat'] as const;
type Usage=typeof usageLabels[number];
type UsageTotals={rows:number;hours:number|null;value:number|null};
type MachineProfit={result?:number|null; margin_pct?:number|null};
type MachinePerformance=MachineProfit & {hours:number|null; billed_hours?:number|null; available_hours?:number|null; days?:number|null; total_cost?:number|null};
type MachineCosts={
 booked_cost:number|null; personnel_cost:number|null; personnel_hours:number|null; total_cost:number|null;
 operator_hours?:number|null; operator_cost?:number|null; groundworker_hours?:number|null; groundworker_cost?:number|null;
 categories?:Record<string,number>|null; internal_ao?:number|null;
};
// Labels are for display grouping. They do not affect identities, costs or resource rows.
const machineTypes = [
 {title:'Hjulgrävare', match:/hjulgräv|\b(?:EWR?|PW|DX)\s*\d+[A-Z0-9-]*W\b|\b(?:EWR?|PW)[ -]?\d+|\b(?:170|160)W\b/i},
 {title:'Bandgrävare och minigrävare', match:/bandgräv|minigräv|\bgrävmaskin|\b(?:EC|SK|DX|R)\s*[- ]?\d{2,}|\bCAT\s*(?:3\d{2}|301\.8)/i},
 {title:'Grävare med okänd undervagn', match:/\bLiebherr\s+9\d{2}/i},
 {title:'Hjullastare och kompaktlastare', match:/lastare|\bL\s*\d{2,3}H?\b|\b(?:Ljungby|Kramer|Avant|Manitou\s+MLA|Bobcat\s+T76)\b/i},
 {title:'Dumpers', match:/dumper|\bTA[ -]?230\b/i},
 {title:'Vältar', match:/vält|\b(?:Dynapac|Bomag)\b/i},
];
const otherMachineType = 'Övriga maskiner';
const machineCostColumns=[
 ...costColumns,{key:'transport',label:'Transport och maskinflytt',color:'148,105,69'},
];
function costLabel(category:string){
 return machineCostColumns.find(item=>item.key===category)?.label??(category==='internal_ao'?'Interna AO-överföringar':category);
}
function machineCost(machine:MachineCosts,category:string){
 return sumPresent([machine.categories?.[category]??null,category==='personnel'?machine.personnel_cost:null]);
}
function MachineCostCell({machine,category,color,href}:{machine:Machine;category:string;color:string;href:string}){
 const amount=machineCost(machine,category);
 const share=costShare(amount,machine.value??0);
 return <div className={unitStyles.costCell} style={{background:costShade(color,share)}} title={money(amount)}>
  {amount===null?'–':<Link href={href} prefetch={false}><strong>{share===null?'–':percent.format(share/100)}</strong><small>{money(amount)}</small></Link>}
 </div>;
}
type Machine=Metrics & MachineCosts & MachinePerformance & {machine_id:string;name:string;codes:string[];machine_reference?:string|null;order_count?:number;order_refs?:string[];usage?:Partial<Record<Usage,UsageTotals>>};
type Job={project:string;work_order:string;project_name:string;order_name:string;rows:number;hours:number|null;value:number|null;drivers?:string[];usage?:Usage;personnel_hours?:number|null;personnel_cost?:number|null};
type Other={category:string;code:string;article:string;unit:string;rows:number;quantity:number|null;value:number|null};
type PersonUnit=MachineProfit & {
 person:string|null; name:string|null; hours:number; operator_hours:number|null; groundworker_hours:number|null;
 personnel_cost:number; value:number|null; vehicles:string[]; vehicle_cost:number|null; total_cost:number;
};
const vehicleLinkStatus:Record<string,string>={
 saved:'Bilkopplingen sparades.',missing:'Registreringsnumret hittades inte i Humla.',
 overlap:'Personen eller bilen har redan en koppling som överlappar perioden.',
 invalid:'Kontrollera registreringsnummer och från-datum.',failed:'Bilkopplingen kunde inte sparas.',
};
type Report={
 labor_rates?:Record<'operator'|'groundworker',{rate:number;source:string}>;
 person_units?:PersonUnit[];
 machine_period?:{from:string;to:string}|null;
 machines:Machine[];
 drivers?:{name:string;hours:number|null;rows:number;orders:number}[];
 months:(Metrics & MachinePerformance & {month_key:string})[];
 cost_accounts?:{category:string;account:string|null;source:string;asset_reference?:string|null;asset_source?:string|null;amount:number;row_count:number}[];
 jobs:Job[];
 others:Other[];
 details:{sheet:string;source_row:number;performed_on:string|null;code:string;article:string;unit?:string;quantity:number|null;value:number|null;driver_name?:string;usage?:Usage}[];
};

function MachineReference({machine}:{machine:Machine}){
 const refs=machine.order_refs??[];
 return <>
  <small>{machine.machine_reference?`Maskinprojekt ${machine.machine_reference} · `:''}Artikel {machine.codes.join(', ')}</small>
  <p>{refs.length?`Arbetsorder i urvalet: ${refs.join(', ')}${(machine.order_count??0)>refs.length?` + ${machine.order_count!-refs.length} till`:''}`:'Arbetsorder saknas i urvalet.'}</p>
 </>;
}

function MachineMonthlyTrend({months}:{months:Report['months']}){
 const values=months.flatMap(month=>month.value===null?[]:[month.value]);
 if(!values.length)return null;
 const max=Math.max(0,...values),min=Math.min(0,...values),width=Math.max(480,months.length*62+16);
 const y=(value:number)=>16+108*(max-value)/(max-min||1);
 const barWidth=Math.min(44,(width-16)/months.length*.65);
 return <div className={trendStyles.scroll}>
  <svg className={trendStyles.chart} viewBox={`0 0 ${width} 154`} role="img" aria-label="Upparbetat värde per månad. Värdena anges i tabellen.">
   <line x1="8" x2={width-8} y1={y(0)} y2={y(0)} stroke="#96a4b3"/>
   {months.map(({month_key:month,value},index)=>{
    const x=8+(index+.5)*(width-16)/months.length;
    return <g key={month}>
     {value!==null&&<rect x={x-barWidth/2} y={Math.min(y(0),y(value))} width={barWidth} height={Math.max(1,Math.abs(y(0)-y(value)))} fill="#1769aa"><title>{`${month} · ${money(value)}`}</title></rect>}
     <text x={x} y="146" textAnchor="middle" className={trendStyles.axis}>{month}</text>
    </g>;
   })}
  </svg>
 </div>;
}

export default async function MachineFollowup({searchParams}:{searchParams:Promise<Record<string,string|undefined>>}){
 const access=await reviewAccess();
 if(!access)return <main className="content"><h1>Du saknar åtkomst till maskinuppföljningen.</h1></main>;
 const raw=await searchParams;
 const selected=text(raw.batch);
 const machine=/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(text(raw.machine))?text(raw.machine):null;
 const drilling=Boolean(machine)&&typeof raw.project==='string'&&typeof raw.ao==='string';
 const project=drilling?text(raw.project):null,order=drilling?text(raw.ao):null;
 const requestedFrom=text(raw.from),requestedTo=text(raw.to);
 const explicitDates=Boolean(requestedFrom||requestedTo)&&!raw.period_mode;
 const today=stockholmToday();
 let period=resolveForemanPeriod({},null,today);
 let invalidPeriod=false;
 try{
  if(explicitDates){
   if((requestedFrom&&!validTransportDate(requestedFrom))||(requestedTo&&!validTransportDate(requestedTo))
    ||(requestedFrom&&requestedTo&&requestedFrom>requestedTo))throw Error('Invalid dates');
   const anchor=requestedFrom||requestedTo;
   const fiscalYear=foremanFiscalYear(undefined,{year:Number(anchor.slice(0,4)),month:Number(anchor.slice(5,7))});
   period={...period,fiscalYear,from:requestedFrom||period.from,to:requestedTo||period.to};
  }else {
   period=resolveForemanPeriod(raw,null,today);
   if(!period.to)throw Error('Invalid period');
  }
 }catch{invalidPeriod=true;}
 const from=explicitDates?(requestedFrom||null):period.from;
 const to=explicitDates?(requestedTo||null):period.to;
 const periodQuery=explicitDates&&!invalidPeriod?new URLSearchParams({from:requestedFrom,to:requestedTo}):foremanPeriodQuery(period);
 const {data,error}=await nextResourceBatches(access);
 const batches=data??[];
 const batch=selected?batches.find(b=>b.id===selected):
  batches.find(b=>(!from||!b.period_end||b.period_end>=from)&&(!to||!b.period_start||b.period_start<=to))??batches[0];
 const navQuery=new URLSearchParams({cost_center:'10'});
 if(from&&to&&!invalidPeriod){
  navQuery.set('from',from);
  navQuery.set('to',to);
  if(!explicitDates&&period.mode==='months'){
   navQuery.set('fiscal_year',String(period.fiscalYear));
   navQuery.set('months',period.months.join(','));
  }
 }
 const viewQuery=new URLSearchParams(periodQuery);
 if(batch)viewQuery.set('batch',batch.id);
 if(machine)viewQuery.set('machine',machine);
 const href=(changes:Record<string,string|null>)=>{
  const params=new URLSearchParams(viewQuery);
  for(const [key,value] of Object.entries(changes)){
   if(value===null)params.delete(key);
   else params.set(key,value);
  }
  return base+'?'+params;
 };

 let report:Report|null=null;
 let problem='';
 if(error)problem='NeXT-importerna kunde inte hämtas.';
 else if(invalidPeriod)problem='Ogiltigt periodval. Välj period på nytt.';
 else if(selected&&!batch)problem='Den valda exporten är inte tillgänglig.';
 else if(batch){
  try{
   const parsed=readNextArticleFile(await loadNextResourceFile(access,batch),{includeMachines:true});
   if(!parsed.workshopColumns)problem='Exporten behöver innehålla Kontonr, Utförd datum och Utf intäkt.';
   else{
    const args={
     t:access.tenantId,p_batch:batch.id,p_rows:parsed.machineRows,
     p_from:from,p_to:to,p_machine:machine,p_project:project,p_order:order,p_months:!explicitDates&&period.mode==='months'?period.months:null,
    };
    const updated=await access.db.rpc('hub_next_machine_followup_v2',args);
    const result=updated.error?.code==='PGRST202'?await access.db.rpc('hub_next_machine_followup',args):updated;
    if(result.error||!result.data)throw Error(result.error?.code??'Empty report');
    report=result.data as Report;
   }
  }catch(error){
   console.error('[machine-followup]',{batchId:batch.id,reason:error instanceof Error?error.message:'Unknown error'});
   problem='Maskinunderlaget kunde inte läsas. Försök igen eller välj en annan export.';
  }
 }
 const current=report?.machines.find(row=>row.machine_id===machine);
 const all=report?.machines??[];
 const machineGroups = new Map<string,Machine[]>();
 for (const row of all) {
  const type = machineTypes.find(({match})=>match.test(row.name))?.title??otherMachineType;
  const group = machineGroups.get(type)??[];
  group.push(row);
  machineGroups.set(type,group);
 }
 const hours=sumPresent(all.map(row=>row.hours));
 const value=sumPresent(all.map(row=>row.value));
 const summary={hours,value,value_per_hour:hours&&all.every(row=>row.hours===null||row.value_per_hour!==null)?all.reduce((sum,row)=>sum+(row.value_per_hour??0)*(row.hours??0),0)/hours:null};
 const summaryCost=sumPresent(all.map(row=>row.total_cost??null));
 const metrics=machine?current:all.length?summary:null;
 const rates=report?.labor_rates;
 const people=report?.person_units;
 const personnelGroups=[{title:'Anläggare',units:[] as PersonUnit[]},{title:'Maskinist',units:[] as PersonUnit[]}];
 for(const unit of people??[]){
  const machinist=unit.operator_hours!=null&&(unit.groundworker_hours==null||Math.abs(unit.operator_hours)>Math.abs(unit.groundworker_hours));
  personnelGroups[machinist?1:0].units.push(unit);
 }
 const manage=people?.some(unit=>unit.person!==null)?
  (await access.db.rpc('hub_has_permission',{p_tenant_id:access.tenantId,p_permission:'kpi.manage'})).data===true:false;
 const statusKey=text(raw.vehicle_link);
 const linkStatus=Object.hasOwn(vehicleLinkStatus,statusKey)?vehicleLinkStatus[statusKey]:undefined;
 const categories=[...new Set(report?.others.map(row=>row.category))];
 return <KpiDetailShell followup="machines" title="Maskinuppföljning" breadcrumb="Humla Dashboard / Entreprenad och maskinuthyrning / Maskiner" query={navQuery.toString()}>
  <div className="content">
   <header className="panel">
    <div className="panel-head"><div><h2>{current?.name??'Entreprenad och maskinuthyrning'}</h2><p>Egna maskiner · NeXT Resursuppföljning</p>{current&&<MachineReference machine={current}/>}</div>
     {machine&&<Link className="secondary" prefetch={false} href={href({machine:null})}>← Alla maskiner</Link>}</div>
    <ForemanPeriodPicker period={period} pathname={base} showRevenueShortcut={false} keepQuery={machine?new URLSearchParams({machine}).toString():''}/>
    <details><summary>Underlag och export</summary>
     {batches.length>0&&<form action={base} className="period-form">
      {machine&&<input type="hidden" name="machine" value={machine}/>}
      {[...periodQuery].map(([name,value])=><input key={name} type="hidden" name={name} value={value}/>)}
      <label>NeXT-export <select name="batch" defaultValue={batch?.id??''}>
       {!batch&&<option value="" disabled>Välj en export</option>}
       {batches.map(b=><option key={b.id} value={b.id}>{b.file_name??'Resursuppföljning'}{b.completed_at?' · '+imported.format(new Date(b.completed_at)):''}</option>)}
      </select></label>
      <button type="submit">Visa</button>
     </form>}
     {batch&&<p>{batch.file_name??'Resursuppföljning'}{batch.period_start&&batch.period_end&&` · ${batch.period_start} – ${batch.period_end}`}</p>}
     <Link className="secondary" prefetch={false} href="/kpi?view=importhistorik&history_kind=next_articles">Importhistorik</Link>
    </details>
   </header>
   {problem?<section className="panel" role="alert">{problem}</section>:!report?<section className="panel"><p>Importera Resursuppföljning från NeXT för att börja följa upp maskiner.</p><Link href="/kpi?view=import#next-artikelimport">Öppna Dataimport</Link></section>:<>
    {metrics&&<section className="metrics-grid" aria-label={machine?'Nyckeltal för vald maskin':'Nyckeltal för egna maskiner'}>
      <article className="metric-card"><span>Intäkt under perioden</span><strong>{money(metrics.value)}</strong><small>NeXT · Utf intäkt</small></article>
      <article className="metric-card"><span>Registrerad tid</span><strong>{metrics.hours===null?'–':number(metrics.hours)+' tim'}</strong></article>
      <article className="metric-card"><span>Värde per timme</span><strong>{money(metrics.value_per_hour)}</strong></article>
      <article className="metric-card"><span>Kostnad under perioden</span><strong>{money(machine?current?.total_cost??null:summaryCost)}</strong><small>Bokfört på maskinen och matchad arbetstid</small></article>
      {current&&<>
       <article className="metric-card"><span>Resultat under perioden</span><strong>{money(current.result??null)}</strong></article>
       <article className="metric-card"><span>Marginal</span><strong>{marginText(current.margin_pct)}</strong></article>
       <article className="metric-card"><span>Nyttjandegrad</span><strong>{utilization(current)}</strong><small>{current.available_hours==null?'Kapacitet saknas':number(current.available_hours)+' tim kapacitet'}</small></article>
       <article className="metric-card"><span>Kostnad per debiterad timme</span><strong>{costPerBilledHour(current)}</strong><small>{current.billed_hours==null?'Fakturerade timmar saknas':number(current.billed_hours)+' tim fakturerade i NeXT'}</small></article>
      </>}
      {!machine&&<article className="metric-card"><span>Egna maskiner i urvalet</span><strong>{number(all.length)}</strong></article>}
    </section>}
    {machine&&!current&&<section className="panel"><p>Inget underlag för maskinen i urvalet.</p></section>}
    {!machine&&<section>
     <h2>Egna maskiner</h2>
     <div className={unitStyles.legend}><span><i style={{background:'#e9b9b9'}}/>Rött resultat = förlust</span><span><i style={{background:'#d8e3ff'}}/>Starkare kostnadsfärg = större andel av intäkten</span></div>
     {rates&&<p>Schablon för personalkostnad i NeXT-underlaget. Maskinförare {money(rates.operator.rate)}, anläggare {money(rates.groundworker.rate)}.</p>}
     <details className="kpi-help"><summary>Om tid och kostnader</summary><p className={unitStyles.caption}>Intäkten är upparbetat värde i NeXT. Intäkt, kostnad och nyttjandegrad följer samma datumurval inom exportens period. Marginal visas när intäkten är positiv och både intäkt och kostnad finns i underlaget. Klicka på en kostnadsruta för att se underlaget.</p></details>
     {all.length?[...machineTypes.map(type=>type.title),otherMachineType].map(type=>{
      const rows=machineGroups.get(type);
      if(!rows?.length)return null;
      const costs=machineCostColumns.slice(0,5);
      const columns=[
       {label:'Maskin'},{label:'Intäkt'},{label:'Kostnad'},{label:'Resultat'},{label:'Marginal'},
       ...costs,{label:'Maskintid'},{label:'Arbetstid'},{label:'Dagar'},{label:'Debiterad tid'},{label:'Nyttjandegrad'},{label:'Värde / h'},{label:'Kostnad / debiterad h'},
      ];
      const head=<thead><tr>{columns.map(c=><th key={c.label} scope="col" className={unitStyles.headingCell} style={{borderTop:'3px solid '+('color' in c?'rgb('+c.color+')':'#cbd5e1')}}>{c.label}</th>)}</tr></thead>;
      return <article className={'panel economic-units '+unitStyles.panel} key={type}>
       <h3>{type} <small>· {rows.length}</small></h3>
       <KpiTableFrame head={head}><table className={unitStyles.table} aria-label={type}>
        {head}<tbody>{[...rows].sort((a,b)=>a.name.localeCompare(b.name,'sv',{numeric:true})).map(m=><tr className="economic-parent" key={m.machine_id}>
         <td className={unitStyles.name}><Link prefetch={false} href={href({machine:m.machine_id})}><strong>{m.name} →</strong></Link>
          <small>{m.machine_reference?('AO '+m.machine_reference+' · '):''}{m.codes.join(', ')}</small></td>
         <td><Link prefetch={false} href={href({machine:m.machine_id})+'#maskinintakt'}>{money(m.value)}</Link></td>
         <td><Link prefetch={false} href={href({machine:m.machine_id})+'#maskinkostnader'}>{money(m.total_cost)}</Link></td>
         <ResultCells result={m.result} margin_pct={m.margin_pct}/>
         {costs.map(c=><td key={c.key} className={unitStyles.cost}>
          <MachineCostCell machine={m} category={c.key} color={c.color} href={href({machine:m.machine_id})+'#kostnad-'+c.key}/>
         </td>)}
         <td>{number(m.hours)}</td><td>{number(m.personnel_hours)}</td><td>{number(m.days??null)}</td><td>{number(m.billed_hours??null)}</td>
         <td>{utilization(m)}</td><td>{money(m.value_per_hour)}</td><td>{costPerBilledHour(m)}</td>
        </tr>)}</tbody>
       </table></KpiTableFrame>
      </article>;
     }):<p>Inga bekräftade egna maskiner har underlag i urvalet.</p>}
    </section>}
    {!machine&&people&&<section className="panel" id="personalenheter">
     <h2>Personaluppföljning</h2>
     <p>Visar arbetstid utan entydig maskinkoppling. Varje person visas en gång. Vid tid i båda rollerna avgör flest timmar vilket block personen visas i. Vid lika många timmar visas personen under Anläggare.</p>
     <p>Resultat och marginal bygger på kända kostnader. Bilkostnader följer bilkopplingens giltighetsperiod.</p>
     {linkStatus&&<p role="status">{linkStatus}</p>}
     {personnelGroups.map(({title,units})=><section className={'panel '+unitStyles.panel} key={title}>
      <h3>{title}</h3>
      {units.length?<div className="table-wrap"><table className={'data-table '+unitStyles.table} aria-label={title}>
      <thead><tr><th scope="col">Person och bil</th><th scope="col">Anläggartid</th><th scope="col">Maskinförartid</th><th scope="col">Upparbetat värde</th><th scope="col">Personalkostnad</th><th scope="col">Bilkostnad</th><th scope="col">Summa känd kostnad</th><th scope="col">Resultat</th><th scope="col">Marginal</th>{manage&&<th scope="col">Bilkoppling</th>}</tr></thead>
      <tbody>{units.map((unit,i)=><tr key={unit.person??i}>
       <th scope="row">{unit.name??'Person saknas i NeXT'}<br/><small>{unit.vehicles.join(', ')||'Bil saknas'}</small></th>
       <td>{number(unit.groundworker_hours)}</td><td>{number(unit.operator_hours)}</td><td>{money(unit.value)}</td>
       <td>{money(unit.personnel_cost)}</td><td>{money(unit.vehicle_cost)}</td><td>{money(unit.total_cost)}</td>
       <ResultCells result={unit.result} margin_pct={unit.margin_pct}/>
       {manage&&<td>{unit.person?<details><summary>Koppla bil</summary>
        <form action={assignPersonVehicle} className="period-form">
         <input type="hidden" name="person" value={unit.person}/>
         <input type="hidden" name="selection" value={viewQuery.toString()}/>
         <label>Registreringsnummer<input name="registration" required maxLength={12}/></label>
         <label>Gäller från<input name="start" required type="date" defaultValue={from??undefined}/></label>
         <button type="submit">Spara</button>
        </form>
       </details>:'Personen behöver kopplas till Humla'}</td>}
      </tr>)}</tbody>
     </table></div>:<p>Ingen arbetstid utan maskinkoppling i urvalet.</p>}
     </section>)}
    </section>}
    {current&&<section className="panel" id="maskinintakt"><h2>Intäkt per användning</h2>
     <p>Bygger på projektets verksamhetsgrupp vid utförandedatum. NeXT-projektets kategori kan komplettera den första klassningen bakåt i tiden. Extern uthyrning kräver en extern kund på resursraden.</p>
     <div className="table-wrap"><table className="data-table"><thead><tr><th scope="col">Användning</th><th scope="col">Registrerad tid</th><th scope="col">Upparbetat värde</th></tr></thead>
      <tbody>{usageLabels.map(label=><tr key={label}><th scope="row">{label}</th><td>{number(current.usage?.[label]?.hours??null)}</td><td>{money(current.usage?.[label]?.value??null)}</td></tr>)}</tbody>
     </table></div>
    </section>}
    {current&&<section className="panel" id="maskinkostnader">
     <h2>Kostnader och arbetstid</h2>
     <dl className={styles.facts}>
      <dt>Kostnader enligt bokföring och avskrivningsregister</dt><dd>{money(current.booked_cost??null)}</dd>
      {current.internal_ao!=null&&<><dt>Interna AO-överföringar</dt><dd>{money(current.internal_ao)}</dd></>}
      <dt>{rates?'Beräknad personalkostnad':'Personalkostnad tilldelad från tidrapporter'}</dt><dd>{money(current.personnel_cost??null)}</dd>
      {rates&&<><dt>Maskinförare</dt><dd>{number(current.operator_hours??null)} tim · {money(current.operator_cost??null)}</dd>
      <dt>Anläggare</dt><dd>{number(current.groundworker_hours??null)} tim · {money(current.groundworker_cost??null)}</dd></>}
      <dt>Matchad arbetstid</dt><dd>{current.personnel_hours==null?'–':number(current.personnel_hours)+' tim'}</dd>
     </dl>
     <p>Avskrivningar hämtas från Humlas avskrivningsregister. – betyder att underlag saknas. NeXT-kostnaderna hämtas från senaste publicerade bokföringsimporten i Humla. Interna AO-överföringar redovisas separat från maskinkostnaden. Kostnad per debiterad timme använder timmar markerade som fakturerade i NeXT. Nyttjandegraden jämför registrerade maskintimmar med Humlas normala kapacitet under exportens period.</p>
     {rates?<p>Humla använder de registrerade personaltimmarna i NeXT där de går att koppla till maskinen. När en maskinförare har registrerats på en maskinrad används maskintimmarna som underlag i övriga fall. Maskinflytt och maskinrader utan förare ger ingen schablonkostnad.</p>:<p>Humla matchar tidrapporter mot förare, utförandedag och maskinartikel i NeXT. Om tidrapporten anger ett projekt behöver projektet också stämma. Om föraren kört flera maskiner fördelas kostnaden efter matchade timmar. Sammanställda arbetstidsrader från NeXT räknas bort för att undvika dubbelräkning.</p>}
     {current.personnel_hours==null&&<p>Ingen beräknad personalkostnad kunde kopplas i urvalet. Kostnaden per debiterad timme bygger på de kostnader som finns i underlaget.</p>}
     <div className="table-wrap"><table className="data-table">
      <caption>Maskinkostnader per kategori</caption>
      <thead><tr><th scope="col">Kostnadsslag</th><th scope="col">Bokföring och register</th><th scope="col">{rates?'Beräknad kostnad':'Från tidrapporter'}</th><th scope="col">Totalt</th></tr></thead>
      <tbody>{[...new Set([...machineCostColumns.map(item=>item.key),...Object.keys(current.categories??{})])].map(category=>{
       const booked=current.categories?.[category]??null;
       const allocated=category==='personnel'?current.personnel_cost:null;
       const amount=machineCost(current,category);
       const column=machineCostColumns.find(item=>item.key===category);
       return <tr key={category} id={'kostnad-'+category}><th scope="row">{costLabel(category)}</th><td>{money(booked)}</td><td>{money(allocated)}</td><td style={{background:column?costShade(column.color,costShare(amount,current.value??0)):undefined}}>{money(amount)}</td></tr>;
      })}</tbody>
      <tfoot><tr><th scope="row">Summa maskinkostnader</th><td>{money(current.booked_cost)}</td><td>{money(current.personnel_cost)}</td><td>{money(current.total_cost)}</td></tr></tfoot>
     </table></div>
     {!!report.cost_accounts?.length&&<details><summary>Visa konton och källor</summary>
      <div className="table-wrap"><table className="data-table">
       <thead><tr><th scope="col">Kostnadsslag</th><th scope="col">Konto</th><th scope="col">Källa</th><th scope="col">Poster</th><th scope="col">Belopp</th></tr></thead>
       <tbody>{report.cost_accounts.map(a=><tr key={JSON.stringify([a.category,a.account,a.source,a.asset_reference,a.asset_source])}>
        <th scope="row">{costLabel(a.category)}</th><td>{a.account??'–'}</td><td>{a.source}{a.asset_reference&&<><br/><small>{a.asset_reference} · {a.asset_source}</small></>}</td><td>{a.row_count}</td><td>{money(a.amount)}</td>
       </tr>)}</tbody>
      </table></div>
     </details>}
    </section>}
    {machine&&current&&<section className="panel">
     <h2>Förare i valt urval</h2>
     <p>Maskinartikeln identifierar maskinen. Utförd av på resursraden visar vem som körde.</p>
     {report.drivers?.length?<div className="table-wrap"><table className="data-table">
      <thead><tr><th scope="col">Förare</th><th scope="col">Registrerad tid</th><th scope="col">Arbetsorder</th><th scope="col">Källrader</th></tr></thead>
      <tbody>{report.drivers.map((driver,index)=><tr key={index}><th scope="row">{driver.name}</th><td>{number(driver.hours)}</td><td>{driver.orders}</td><td>{driver.rows}</td></tr>)}</tbody>
     </table></div>:<p>Föraruppgifter saknas i urvalet.</p>}
    </section>}
    {machine&&report.months.length>0&&<section className="panel"><h2>Maskinens utveckling per månad</h2><MachineMonthlyTrend months={report.months}/><div className="table-wrap"><table className="data-table">
     <thead><tr><th scope="col">Månad</th><th scope="col">Registrerade tim</th><th scope="col">Debiterade tim</th><th scope="col">Nyttjandegrad</th><th scope="col">Intäkt</th><th scope="col">Kostnad</th><th scope="col">Resultat</th><th scope="col">Marginal</th><th scope="col">Kostnad/debiterad tim</th></tr></thead>
     <tbody>{report.months.map(m=><tr key={m.month_key}><th scope="row">{m.month_key}</th><td>{number(m.hours)}</td><td>{number(m.billed_hours??null)}</td><td>{utilization(m)}</td><td>{money(m.value)}</td><td>{money(m.total_cost??null)}</td><ResultCells result={m.result} margin_pct={m.margin_pct}/><td>{costPerBilledHour(m)}</td></tr>)}</tbody>
    </table></div></section>}
    {machine&&!drilling&&report.jobs.length>0&&<section className="panel"><h2>Projekt och arbetsorder</h2><div className="table-wrap"><table className="data-table">
     <thead><tr><th scope="col">Projekt</th><th scope="col">Arbetsorder</th><th scope="col">Förare</th><th scope="col">Användning</th><th scope="col">Registrerad tid</th><th scope="col">Upparbetat värde</th><th scope="col">Matchad arbetstid</th><th scope="col">Tilldelad personalkostnad</th></tr></thead>
     <tbody>{report.jobs.map(j=><tr key={JSON.stringify([j.project,j.work_order,j.usage])}><th scope="row">{j.project} {j.project_name}</th><td><Link prefetch={false} href={href({project:j.project,ao:j.work_order})}>AO {j.work_order||'saknas'} {j.order_name} →</Link></td><td>{j.drivers?.join(', ')||'–'}</td><td>{j.usage??'–'}</td><td>{number(j.hours)}</td><td>{money(j.value)}</td><td>{number(j.personnel_hours??null)}</td><td>{money(j.personnel_cost??null)}</td></tr>)}</tbody>
    </table></div></section>}
    {drilling&&<section className="panel"><p><Link prefetch={false} href={href({})}>← Till projekt och arbetsorder</Link></p><h2>Projekt {project||'saknas'} · AO {order||'saknas'}</h2>
     {report.details.length?<div className="table-wrap"><table className="data-table">
      <thead><tr><th scope="col">Utförd</th><th scope="col">Artikel</th><th scope="col">Förare</th><th scope="col">Användning</th><th scope="col">Registrerad tid</th><th scope="col">Upparbetat värde</th><th scope="col">Källrad</th></tr></thead>
      <tbody>{report.details.map(r=><tr key={r.sheet+':'+r.source_row}><td>{r.performed_on??'–'}</td><th scope="row">{r.code} {r.article}</th><td>{r.driver_name??'–'}</td><td>{r.usage??'–'}</td><td>{number(r.quantity)} {r.unit}</td><td>{money(r.value)}</td><td>{r.sheet} · {r.source_row}</td></tr>)}</tbody>
     </table></div>:<p>Inga resursrader i urvalet.</p>}
    </section>}
    {!machine&&categories.map(category=><details className="panel" key={category}><summary>{category}</summary><div className="table-wrap"><table className="data-table">
     <thead><tr><th scope="col">Artikel</th><th scope="col">Mängd</th><th scope="col">Upparbetat värde</th><th scope="col">Källrader</th></tr></thead>
     <tbody>{report.others.filter(a=>a.category===category).map(a=><tr key={JSON.stringify([a.code,a.article,a.unit])}><th scope="row">{a.code} {a.article}</th><td>{number(a.quantity)} {a.unit}</td><td>{money(a.value)}</td><td>{a.rows}</td></tr>)}</tbody>
    </table></div></details>)}
   </>}
  </div>
 </KpiDetailShell>;
}
