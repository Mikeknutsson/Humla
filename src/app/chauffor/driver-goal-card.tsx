import type {VehicleContext} from '@/lib/hub/driver-self';
import styles from './driver.module.css';

const percent=new Intl.NumberFormat('sv-SE',{maximumFractionDigits:1});
const date=(s:string)=>new Intl.DateTimeFormat('sv-SE',{day:'numeric',month:'short',year:'numeric',timeZone:'UTC'}).format(new Date(s+'T00:00:00Z'));
const finite=(v:number|null|undefined):v is number=>typeof v==='number'&&Number.isFinite(v);
function goalText(v:number|null|undefined){return !finite(v)?'Underlag saknas':v===0?'På målet':`${percent.format(Math.abs(v))} % ${v<0?'under':'över'} målet`;}

function GoalGauge({value,name}:{value:number|null|undefined;name:string}){
 const known=finite(value),min=-50,max=50;
 const point=(v:number,r=76)=>{const angle=Math.PI*(1-(Math.max(min,Math.min(max,v))-min)/(max-min));return {x:110+Math.cos(angle)*r,y:94-Math.sin(angle)*r};};
 const arc=(from:number,to:number)=>{const a=point(from),b=point(to);return `M ${a.x} ${a.y} A 76 76 0 0 1 ${b.x} ${b.y}`;};
 const needle=point(known?value:0,64),tone=!known?'neutral':value>=0?'good':value>=-20?'near':'below';
 return <div className={styles.goalGauge} data-tone={tone}>
 <svg viewBox="0 0 220 128" role="img" aria-label={`${name}: ${goalText(value)}. Noll är målet. Skala minus 50 till plus 50 procent.`}>
 <path d={arc(-50,50)} fill="none" stroke="#34393e" strokeWidth="15"/>
 {known&&<><path d={arc(-50,-20)} fill="none" stroke="#d16c70" strokeWidth="15"/><path d={arc(-20,0)} fill="none" stroke="#d9b65e" strokeWidth="15"/><path d={arc(0,50)} fill="none" stroke="#69bc91" strokeWidth="15"/></>}
 <line x1="110" y1="9" x2="110" y2="30" stroke="#fff" strokeWidth="3"/>
 {known&&<><line x1="110" y1="94" x2={needle.x} y2={needle.y} stroke="#f5f5f2" strokeWidth="3.5" strokeLinecap="round"/><circle cx="110" cy="94" r="6" fill="#f5f5f2"/></>}
 <text x="20" y="122" fill="currentColor" fontSize="11">−50 %</text><text x="110" y="122" textAnchor="middle" fill="currentColor" fontSize="11">0 = målet</text><text x="200" y="122" textAnchor="end" fill="currentColor" fontSize="11">+50 %</text>
 </svg><strong>{goalText(value)}</strong>
 {known&&Math.abs(value)>50&&<small>Visaren är vid skalans gräns. Värdet ovan är den exakta avvikelsen.</small>}
 </div>;
}

function Comparison({label,value,change,from,to}:{label:string;value:number|null|undefined;change:number|null|undefined;from:string;to:string}){
 return <div><span>{label}</span><strong>{goalText(value)}</strong>{finite(change)&&<small>{change===0?'Samma målavvikelse':`${percent.format(Math.abs(change))} procentenheter ${change>0?'bättre':'lägre'}`}</small>}<small>{date(from)}–{date(to)}</small></div>;
}

export function DriverGoalCard({vehicle:v}:{vehicle:VehicleContext}){
 const known=finite(v.goal_deviation_pct),met=known&&v.goal_deviation_pct!>=0;
 return <article className={`${styles.card} ${styles.goalCard}`}>
 <div className={styles.goalHeading}><div><span className={styles.kicker}>MOT MÅLET</span><h2>{v.name}</h2></div><span className={styles.goalBadge}>{met?'Målet nått':known?'Nästa steg framåt':'Inväntar underlag'}</span></div>
 <GoalGauge name={v.name} value={v.goal_deviation_pct}/>
 <p className={styles.goalLead}>{!known?'Mål eller jämförbart intäktsunderlag saknas. Saknade siffror räknas inte som ett dåligt resultat.':met?'Bra jobbat med fordonets utveckling. Fortsätt med det som fungerar och håll i marginalen.':'Varje förbättring hjälper. Ta nästa steg tillsammans med transportledningen.'}</p>
 <div className={styles.goalComparisons}><Comparison label="Förra perioden" value={v.previous_goal_deviation_pct} change={v.change_vs_previous_pp} from={v.comparison_from} to={v.comparison_to}/><Comparison label="Samma period förra året" value={v.year_goal_deviation_pct} change={v.change_vs_year_pp} from={v.year_from??v.comparison_from} to={v.year_to??v.comparison_to}/></div>
 {known&&<section className={styles.goalActions} aria-label={`Nästa steg för ${v.name}`}><h3>{met?'Behåll försprånget':'Det här kan hjälpa'}</h3><ul>{v.actions?.map((a,i)=><li key={a.kind+i}>{a.kind==='fuel'?<><strong>Räkneexempel: cirka {percent.format(a.liters??0)} liter mindre bränsle.</strong> Det motsvarar ungefär {percent.format(a.gap_covered_pct??0)} % av gapet till målet. Se över onödig tomgång, körsätt och planering tillsammans.</>:a.kind==='emptying'?<><strong>Samordna en extra tömning.</strong> Fråga transportledningen om nästa tömning kan passa in på rutten. Antalet som behövs till målet kan räknas först när extra intäkt och kostnad är kända.</>:a.kind==='load'?<><strong>Få med ett extra lass eller en returlast.</strong> Stäm av möjlighet, tid och lönsamhet med transportledningen. Antalet lass till målet kräver underlag för extra intäkt och kostnad.</>:a.kind==='maintain'?<><strong>Fortsätt med bra planering och tidig felrapportering.</strong> Samordnade körningar och färre onödiga stopp hjälper fordonet att hålla målet.</>:<><strong>Få med allt utfört arbete.</strong> Kontrollera att körningar, tömningar och eventuell väntetid är korrekt rapporterade.</>}</li>)}</ul></section>}
 <details className={styles.goalDetails}><summary>Så fungerar målet och exemplen</summary><p>Noll på mätaren betyder att fordonets resultat når sitt satta mål. Avvikelsen räknas i förhållande till målresultatet, inte som marginalprocent. Om utfallet är 80 % av målresultatet visas 20 % under målet.</p><p>Jämförelserna gäller föregående lika långa period och samma datum förra året, mot respektive periods mål. Helger och olika mängd arbete kan påverka jämförelsen. Kostnader kan bokas månadsvis och ge stora svängningar i korta perioder.</p><p>Bränsleexemplet bygger på periodens bokförda bränslekostnad och tankade liter med preliminärt pris. Det visar kostnadseffekt vid samma mängd arbete och högst 10 % av tankad mängd. Tankning är inte uppmätt förbrukning. Förslagen är alternativ att diskutera, inte garanterade besparingar eller krav på extra arbete.</p></details>
 </article>;
}
