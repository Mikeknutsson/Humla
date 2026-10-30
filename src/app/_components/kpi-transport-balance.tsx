import Link from 'next/link';
import type {DailyRevenueTarget} from '@/lib/hub/daily-revenue-target';
import type {TransportScorecard, TransportMetrics, TransportBreakdown, TransportCardAnalysis, TransportCostBreakdown} from '@/lib/kpi/transport-leader';
import {KpiMarginGauge} from './kpi-margin-gauge';
import styles from './kpi-margin-gauge.module.css';

const currency = new Intl.NumberFormat('sv-SE',{style:'currency',currency:'SEK',maximumFractionDigits:0});
const number = new Intl.NumberFormat('sv-SE',{maximumFractionDigits:1});
const money = (n:number|null|undefined) => n == null ? 'Underlag saknas' : currency.format(n);
const pct = (n:number|null|undefined) => n == null ? '–' : `${number.format(n)} %`;
const labels:Record<string,string> = {management:'Arbetsledning',overhead:'Övrig overhead',transport:'Transport',material:'Material / ballast',tipp:'Tippavgifter',tipp_deponi:'Tippavgifter / deponi',other:'Övrigt',unclassified:'Ej klassificerat',personnel:'Personal',fuel:'Bränsle',service_repair:'Service & reparation',fixed:'Fasta kostnader',depreciation:'Avskrivning',hired:'Inhyrda resurser'};

const costCategories=['personnel','fuel','service_repair','fixed','depreciation','hired','management','overhead','material','tipp_deponi','other','unclassified'];
const costCategoryOrder=(category:string)=>{const index=costCategories.indexOf(category);return index<0?costCategories.length:index;};

function BalanceCard({label,href,metrics,previous,analysis,costBreakdown,foremanMode=false,dailyTarget}:{label:string;href?:string;metrics:TransportMetrics;previous?:TransportMetrics;analysis?:TransportCardAnalysis;costBreakdown?:TransportCostBreakdown[];foremanMode?:boolean;dailyTarget?:DailyRevenueTarget}) {
 return <article className={styles.card}><div className={styles.cardTop}><h3>{href?<Link prefetch={false} href={href}>{label}</Link>:label}</h3>
 <KpiMarginGauge label={label} margin={metrics.margin_percent} target={metrics.target_margin_percent}/></div>
 <dl className={styles.facts}>
 <dt>Intäkter</dt><dd>{money(metrics.revenue)}</dd><dt>Kostnader</dt><dd>{money(metrics.cost)}</dd>
 {foremanMode && (costBreakdown == null ? <><dt>Kostnadsfördelning</dt><dd>Underlag saknas</dd></> : [...costBreakdown].sort((a,b)=>costCategoryOrder(a.category)-costCategoryOrder(b.category)||a.category.localeCompare(b.category,'sv')).map(row=><div key={row.category} className={styles.costRow}><dt>{labels[row.category]??row.category}</dt><dd>{money(row.amount)}</dd></div>))}
 <dt>Resultat</dt><dd><strong>{money(metrics.result)}</strong></dd>
 <dt>Målmarginal</dt><dd>{metrics.target_margin_percent==null?'Mål saknas':pct(metrics.target_margin_percent)}</dd>
 {foremanMode&&dailyTarget&&<><dt>Intäkt som krävs / vardag</dt><dd><strong>{dailyTarget.required==null?dailyTarget.reason:money(dailyTarget.required)}</strong></dd><dt>Faktisk snittintäkt / vardag</dt><dd>{money(dailyTarget.actual)}</dd><dt>Över / under dagsbehov</dt><dd>{dailyTarget.gap==null?'–':(dailyTarget.gap>=0?'+':'')+money(dailyTarget.gap)}</dd></>}
 <dt>Avvikelse mot mål</dt><dd>{metrics.deviation_pp==null?'Mål saknas':`${number.format(metrics.deviation_pp)} pp`}</dd>
 <dt>Marginal fg. år</dt><dd>{pct(previous?.margin_percent)}</dd>
 <dt>Resultat fg. år</dt><dd>{money(previous?.result)}</dd>
 </dl>
 {analysis&&analysis.insights.length>0&&<aside className={styles.analysis} aria-label={`Avvikelse – ${label}`} data-status="warning">
 <strong>{analysis.insights[0].title}</strong>
 <details><summary>Visa jämförelse</summary>{analysis.insights[0].evidence.map(e=><p key={e}>{e}</p>)}</details>
 </aside>}
 {!foremanMode&&<details className={styles.explanation}><summary>Om siffrorna</summary>
 <p>Resultat = intäkter minus kostnader, inklusive fördelad overhead. Marginal = resultatets andel av intäkterna. Avvikelse mot mål anges i procentenheter. Fg. år avser samma period föregående år.</p>
 <p>Endast tydliga avvikelser visas. Jämförelsen gäller egen historik eller minst två andra enheter i samma verksamhetsområde. Timanalys kräver tillförlitlig TransPA-tid. Engångskostnader och olika uppdrag kan påverka jämförelsen.</p>
 </details>}</article>;
}

export function TransportBalanceCards({report,prior,base,selectedUnit,selectedGroup,analyses,hideGroups=false,foremanMode=false,dailyTargets,dailyPeriod}:{report:TransportScorecard;prior:TransportScorecard|null;base:string;selectedUnit:string|null;selectedGroup:string|null;analyses?:{units:Record<string,TransportCardAnalysis>;groups:Record<string,TransportCardAnalysis>};hideGroups?:boolean;foremanMode?:boolean;dailyTargets?:Record<string,DailyRevenueTarget>;dailyPeriod?:{from:string;to:string;days:number}}) {
 const link = (key:string,value:string) => {const p=new URLSearchParams(base);p.set(key,value);return '/kpi/transportledare?'+p;};
 const all=new URLSearchParams(base);all.delete('group');
 return <>
 {!hideGroups&&<section className="panel"><h2>{selectedGroup??'Verksamhetsområden'}</h2>
 {selectedGroup&&<Link href={'/kpi/transportledare?'+all}>← Alla verksamhetsområden</Link>}
 <p>Marginal efter samtliga kostnader i urvalet. Rött visar negativt resultat, gult positiv marginal under mål och grönt uppnått mål. Grått fält betyder att mål saknas.</p>
 <p>Period: {report.from}–{report.to}. Klicka på ett verksamhetsområde eller en enhet för att se underlaget. Förklaringar finns i varje ruta under ”Om siffrorna”.</p>
 <div className={styles.cards}>{report.groups.map(g=><BalanceCard key={g.business_group} label={g.business_group} metrics={g} previous={prior?.groups.find(p=>p.business_group===g.business_group)} analysis={analyses?.groups[g.business_group]} href={selectedUnit?undefined:link('group',g.business_group)}/>)}</div>
 </section>}
 <section className="panel"><h2>Enheternas balans</h2>{foremanMode&&dailyPeriod&&<p>Dagsbehov och faktiskt snitt avser {dailyPeriod.from}–{dailyPeriod.to} · {dailyPeriod.days} vardagar (mån–fre).</p>}{foremanMode&&dailyPeriod&&<details><summary>Så räknas dagsbehovet</summary><p>Även helgdagar och dagar utan intäkt ingår bland vardagarna. Intäktsbehov = periodens nettokostnad inklusive fördelad overhead ÷ (1 − målmarginal) ÷ vardagar. Alla periodens intäkter ingår. Historiskt riktvärde vid samma kostnadsnivå; ingen prognos för återstående dagar. Periodens intäktsvägda mål används. Kortare ansvarstid eller ofullständiga importer kan påverka snittet.</p></details>}{foremanMode&&!dailyPeriod&&<p>Dagsbehovets historiska underlag kunde inte hämtas.</p>}<div className={styles.cards}>{report.units.map(u=><BalanceCard key={u.unit_id??'unassigned'} label={u.unit_name??'Ej kopplat till enhet'} metrics={u} previous={prior?.units.find(p=>p.unit_id===u.unit_id)} analysis={analyses?.units[u.unit_id??'unassigned']} dailyTarget={dailyTargets?.[u.unit_id??'']} costBreakdown={u.cost_breakdown} foremanMode={foremanMode} href={!foremanMode&&u.unit_id?link('unit',u.unit_id):undefined}/>)}</div></section>
 </>;
}

export function TransportBreakdowns({report,prior}:{report:TransportScorecard;prior:TransportScorecard|null}) {
 const currentAvailable=report.summary.rows>0;
 const previousAvailable=prior!=null&&prior.summary.rows>0;
 const find=(rows:TransportBreakdown[]|undefined,kind:string,category:string)=>rows?.find(r=>r.kind===kind&&r.category===category);
 return <section className="panel"><h2>Intäkter och kostnader – avvikelser</h2><p>Samma period föregående år. Andel avser respektive post i förhållande till omsättningen. Förändring i andel visas i procentenheter (pp).</p>
 <div className={styles.breakdowns}>{(['revenue','cost']as const).map(kind=>{
 const categories=[...new Set([...report.breakdown,...(prior?.breakdown??[])].filter(r=>r.kind===kind).map(r=>r.category))];
 return <div key={kind}><h3>{kind==='revenue'?'Intäkter':'Kostnader'}</h3><div className="monthly-scroll"><table><thead><tr><th>Post</th><th>Utfall</th><th>Fg. år</th><th>Skillnad kr</th><th>Andel</th><th>Δ andel</th></tr></thead><tbody>{categories.map(category=>{
 const c=find(report.breakdown,kind,category),p=find(prior?.breakdown,kind,category);
 const value=currentAvailable?(c?.amount??0):null,old=previousAvailable?(p?.amount??0):null;
 const share=currentAvailable&&report.summary.revenue!=null&&report.summary.revenue>0?(c?.share_of_revenue??0):null;
 const oldShare=previousAvailable&&prior?.summary.revenue!=null&&prior.summary.revenue>0?(p?.share_of_revenue??0):null;
 return <tr key={category}><th scope="row">{labels[category]??category}</th><td>{money(value)}</td><td>{money(old)}</td><td>{value!=null&&old!=null?money(value-old):'–'}</td><td>{pct(share)}</td><td>{share!=null&&oldShare!=null?`${number.format(share-oldShare)} pp`:'–'}</td></tr>;
 })}</tbody><tfoot><tr><th>Totalt</th><td>{money(report.summary[kind==='revenue'?'revenue':'cost'])}</td><td>{money(prior?.summary[kind==='revenue'?'revenue':'cost'])}</td><td colSpan={3}/></tr></tfoot></table></div></div>;
 })}</div></section>;
}
