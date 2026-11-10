import type {VehicleContext} from '@/lib/hub/driver-self';
import styles from './driver.module.css';

const percent=new Intl.NumberFormat('sv-SE',{maximumFractionDigits:1});
const date=(s:string)=>new Intl.DateTimeFormat('sv-SE',{day:'numeric',month:'short',year:'numeric',timeZone:'UTC'}).format(new Date(s+'T00:00:00Z'));
const finite=(v:number|null|undefined):v is number=>typeof v==='number'&&Number.isFinite(v);
function goalText(v:number|null|undefined){return !finite(v)?'Underlag saknas':v===0?'På målet':`${v<0?'Under':'Över'} målet`;}

function GoalGauge({value,name}:{value:number|null|undefined;name:string}){
 const known=finite(value),min=-50,max=50;
 const point=(v:number,r=76)=>{const angle=Math.PI*(1-(Math.max(min,Math.min(max,v))-min)/(max-min));return {x:110+Math.cos(angle)*r,y:94-Math.sin(angle)*r};};
 const arc=(from:number,to:number)=>{const a=point(from),b=point(to);return `M ${a.x} ${a.y} A 76 76 0 0 1 ${b.x} ${b.y}`;};
 const needle=point(known?value:0,64),tone=!known?'neutral':value>=0?'good':'below';
 return <div className={styles.goalGauge} data-tone={tone}>
 <svg viewBox="0 0 220 128" role="img" aria-label={`${name}: ${goalText(value)}. Noll är målet. Rött under målet och grönt över målet.`}>
 <path d={arc(min,max)} fill="none" stroke="#34393e" strokeWidth="15"/>
 {known&&<><path d={arc(min,0)} fill="none" stroke="#d16c70" strokeWidth="15"/><path d={arc(0,max)} fill="none" stroke="#69bc91" strokeWidth="15"/></>}
 <line x1="110" y1="9" x2="110" y2="30" stroke="#fff" strokeWidth="3"/>
 {known&&<><line x1="110" y1="94" x2={needle.x} y2={needle.y} stroke="#f5f5f2" strokeWidth="3.5" strokeLinecap="round"/><circle cx="110" cy="94" r="6" fill="#f5f5f2"/></>}
 <text x="20" y="122" fill="currentColor" fontSize="11">Under</text><text x="110" y="122" textAnchor="middle" fill="currentColor" fontSize="11">Målet</text><text x="200" y="122" textAnchor="end" fill="currentColor" fontSize="11">Över</text>
 </svg><strong>{goalText(value)}</strong>
 {known&&value!==0&&<small>{percent.format(Math.abs(value))} procentenheter {value<0?'under':'över'} målet</small>}

 </div>;
}

function Comparison({label,value,change,from,to}:{label:string;value:number|null|undefined;change:number|null|undefined;from:string;to:string}){
 return <div><span>{label}</span><strong>{goalText(value)}</strong>{finite(change)&&<small>{change===0?'Samma målavvikelse':change>0?'Utvecklingen har förbättrats':'Utvecklingen har försämrats'}</small>}<small>{date(from)}–{date(to)}</small></div>;
}

export function DriverGoalCard({vehicle:v,annual,annualFrom,annualTo,periodFrom,periodTo}:{vehicle:VehicleContext;annual?:VehicleContext;annualFrom?:string;annualTo?:string;periodFrom?:string;periodTo?:string}){
 const known=finite(v.goal_gap_pp),met=known&&v.goal_gap_pp!>=0;
 return <article className={`${styles.card} ${styles.goalCard}`}>
 <div className={styles.goalHeading}><div><span className={styles.kicker}>MOT MÅLET</span><h2>{v.name}</h2></div><span className={styles.goalBadge}>{met?'Målet nått':known?'Nästa steg framåt':'Inväntar underlag'}</span></div>
 {v.coverage_status==='registered'&&<p className={styles.source}>Preliminärt · intäkter, kostnader och arbetstid finns i perioden.</p>}
 <div className={styles.goalMeters}>
 <section aria-label="Verksamhetsåret hittills"><h3>Verksamhetsåret hittills</h3>{annualFrom&&annualTo&&<small>{date(annualFrom)}–{date(annualTo)}</small>}<GoalGauge name={`${v.name} · verksamhetsåret`} value={annual?.goal_gap_pp}/></section>
 <section aria-label="Vald period"><h3>Vald period</h3>{periodFrom&&periodTo&&<small>{date(periodFrom)}–{date(periodTo)}</small>}<GoalGauge name={`${v.name} · vald period`} value={v.goal_gap_pp}/></section>
 </div>
 <p className={styles.goalLead}>{!known?'Någon del av intäkter, kostnader, arbetstid eller mål saknas för fordonet. Därför visas ingen röd eller grön bedömning ännu.':met?'Bra jobbat med fordonets utveckling. Fortsätt med det som fungerar och håll i marginalen.':'Varje förbättring hjälper. Ta nästa steg tillsammans med transportledningen.'}</p>
 <div className={styles.goalComparisons}>{finite(v.previous_goal_gap_pp)&&<Comparison label="Förra perioden" value={v.previous_goal_gap_pp} change={v.change_vs_previous_pp} from={v.comparison_from} to={v.comparison_to}/>} {finite(v.year_goal_gap_pp)&&<Comparison label="Samma period förra året" value={v.year_goal_gap_pp} change={v.change_vs_year_pp} from={v.year_from??v.comparison_from} to={v.year_to??v.comparison_to}/>}</div>
 {known&&<section className={styles.goalActions} aria-label={`Nästa steg för ${v.name}`}><h3>{met?'Behåll försprånget':'Det här kan hjälpa'}</h3><ul>{v.actions?.map((a,i)=><li key={a.kind+i}>{a.kind==='fuel'?<><strong>Räkneexempel: cirka {percent.format(a.liters??0)} liter mindre bränsle.</strong> Se över onödig tomgång, körsätt och planering tillsammans.</>:a.kind==='emptying'?<><strong>Samordna en extra tömning.</strong> Fråga transportledningen om nästa tömning kan passa in på rutten. Antalet som behövs till målet kan räknas först när extra intäkt och kostnad är kända.</>:a.kind==='load'?<><strong>Få med ett extra lass eller en returlast.</strong> Stäm av möjlighet, tid och lönsamhet med transportledningen. Antalet lass till målet kräver underlag för extra intäkt och kostnad.</>:a.kind==='maintain'?<><strong>Fortsätt med bra planering och tidig felrapportering.</strong> Samordnade körningar och färre onödiga stopp hjälper fordonet att hålla målet.</>:<><strong>Få med allt utfört arbete.</strong> Kontrollera att körningar, tömningar och eventuell väntetid är korrekt rapporterade.</>}</li>)}</ul></section>}
 <details className={styles.goalDetails}><summary>Så fungerar målet och exemplen</summary><p>Målet ligger i mitten. Rött betyder under målet och grönt över målet. Siffran visar skillnaden i procentenheter: 8 % marginal mot 10 % mål betyder 2 procentenheter under målet. Kostnader fördelas över perioden på samma sätt som i arbetsledarvyn.</p><p>Vyn använder perioder med registrerade intäkter, kostnader, arbetskostnad, bränsle, overhead och arbetstid fram till senaste gemensamma källdatum. Uppdatering kan ske veckovis eller dagligen. Inlästa poster är ett preliminärt underlag, inte ett intyg om att bokföringen är slutligt avstämd. Jämförelser visas bara när motsvarande datadelar finns även där.</p><p>Bränsleexemplet bygger på periodens bokförda bränslekostnad och tankade liter med preliminärt pris. Det visar kostnadseffekt vid samma mängd arbete och högst 10 % av tankad mängd. Tankning är inte uppmätt förbrukning. Förslagen är alternativ att diskutera, inte garanterade besparingar eller krav på extra arbete.</p></details>
 </article>;
}
