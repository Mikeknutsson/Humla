'use client';
import {useEffect,useState,useTransition} from 'react';
import Link from 'next/link';
import {KpiTableFrame} from './kpi-table-frame';
import {KpiGroupFilter} from './kpi-cost-center-filter';
import {analysisHref} from '@/lib/kpi/analysis';
import {useRouter} from 'next/navigation';
import {useKpiReportSelection} from './kpi-report-selection';
import styles from './kpi-economic-units.module.css';
import type {MaterialRow} from '@/lib/hub/material-reconciliation';
export type EconomicUnit={key:string;label:string;revenue:number;cost:number;result:number;rows:number;is_fallback?:boolean;
 cost_categories?:Record<string,number|null>;margin_pct?:number|null;worked_hours?:number|null;productive_hours?:number|null;
 billing_percent?:number|null;utilization?:number|null;occupied_hours?:number|null;available_hours?:number|null;
 revenue_per_hour?:number|null;cost_per_hour?:number|null;distance_mil?:number|null;cost_per_mil?:number|null;
 distance_basis?:string;
 revenue_per_mil?:number|null;fuel_cost_per_mil?:number|null;fuel_liters_per_mil?:number|null;
 children:Array<{key:string;label:string;vehicle:string|null;project:string|null;revenue:number;cost:number;result:number;rows:number}>};
const money=new Intl.NumberFormat('sv-SE',{style:'currency',currency:'SEK',maximumFractionDigits:0});
const num=new Intl.NumberFormat('sv-SE',{maximumFractionDigits:1});
const costs=[['management','Arbetsledning'],['overhead','Övrig overhead'],['personnel','Personal'],['fuel','Bränsle'],['service_repair','Service & Rep'],['fixed','Fasta'],['depreciation','Avskrivning'],['material','Material'],['tipp_deponi','Tipp/Deponi'],['hired','Inhyrda'],['other','Övrigt']] as const;
const ratios=[['margin_pct','Marginal','%'],['worked_hours','Arbetad tid','h'],['billing_percent','Debiteringsgrad*','%'],['utilization','Beläggningsgrad','%'],['revenue_per_hour','Intäkt / h','kr'],['cost_per_hour','Kostnad / h','kr'],['distance_mil','Körsträcka','mil'],['cost_per_mil','Kostnad / mil','kr'],['revenue_per_mil','Intäkt / mil','kr'],['fuel_cost_per_mil','Bränsle / mil','kr'],['fuel_liters_per_mil','Förbrukning / mil','l']] as const;
function value(n:number|null|undefined,suffix:string){return n==null?'–':num.format(n)+' '+suffix;}
function EconomicGroupFilter({query,groups}:{query:string;groups:string[]}){
 const selection=useKpiReportSelection(),router=useRouter();const [pending,start]=useTransition();
 const selectedGroup=new URLSearchParams(selection?.query??query).get('group')??'';
 function change(group:string){const p=new URLSearchParams(selection?.query??query);p.set('view','kpi');if(group)p.set('group',group);else p.delete('group');for(const k of ['unit','vehicle','project'])p.delete(k);if(selection)selection.change(p.toString());else start(()=>router.push('/kpi?'+p));}
 return <KpiGroupFilter value={selectedGroup} groups={groups} disabled={pending} onChange={change}/>;
}
export function economicUnitHref(query:string,unit:string){const p=new URLSearchParams(query);p.set('unit',unit);for(const k of ['vehicle','project','category','kind','source','page','view','level','grain'])p.delete(k);return '/kpi/enhet?'+p;}
const costColumns=[
 {key:'personnel',label:'Personal',color:'59,130,246'},
 {key:'fuel',label:'Bränsle',color:'217,119,6'},
 {key:'service_repair',label:'Service/Rep',color:'168,85,247'},
 {key:'fixed',label:'Fasta',color:'100,116,139'},
 {key:'depreciation',label:'Avskrivning',color:'20,140,140'},
 {key:'management',label:'Arbetsledning',color:'99,102,241'},
 {key:'overhead',label:'Overhead',color:'107,114,128'},
 {key:'other',label:'Övrigt',color:'148,105,69'},
 {key:'material',label:'Material',color:'22,163,74'},
 {key:'tipp_deponi',label:'Tipp/Deponi',color:'180,83,9'},
 {key:'hired',label:'Inhyrda',color:'219,39,119'},
] as const;
function finite(n:unknown):number|null{return typeof n==='number'&&Number.isFinite(n)?n:null;}
function costShare(amount:number|null,revenue:number){return amount!==null&&revenue>0?amount/revenue*100:null;}
function costShade(color:string,share:number|null){return share===null||share===0?'transparent':share<0?'#f1f5f9':'rgba('+color+','+(0.04+Math.min(share,100)/100*0.32)+')';}
const compact=new Intl.NumberFormat('sv-SE',{minimumFractionDigits:1,maximumFractionDigits:1});
export function KpiEconomicUnits({units,query,totals,canManage,groups=[]}:{units:EconomicUnit[];query:string;totals:{revenue:number;cost:number;result:number};canManage:boolean;groups:string[]}){
 const [sort,setSort]=useState('label'),[direction,setDirection]=useState<'asc'|'desc'>('asc');
 const [showAllCosts,setShowAllCosts]=useState(false),[display,setDisplay]=useState<'share'|'amount'>('share'),[lossOnly,setLossOnly]=useState(false);
 const shownCosts=showAllCosts?costColumns:costColumns.slice(0,5);
 const columns=[{key:'label',label:'Enhet'},{key:'revenue',label:'Intäkt'},{key:'cost',label:'Kostnad'},{key:'result',label:'Resultat'},{key:'margin_pct',label:'Marginal'},...shownCosts.map(c=>({key:'category:'+c.key,label:c.label,color:c.color})),{key:'worked_hours',label:'Timmar'},{key:'distance_mil',label:'Mil'},{key:'revenue_per_hour',label:'Intäkt/h'},{key:'cost_per_mil',label:'Kostnad/mil'}];
 function changeSort(key:string){if(sort===key)setDirection(d=>d==='asc'?'desc':'asc');else{setSort(key);setDirection(key==='label'?'asc':'desc');}}
 function sortValue(unit:EconomicUnit){if(sort.startsWith('category:')){const amount=finite(unit.cost_categories?.[sort.slice(9)]);return display==='share'?costShare(amount,unit.revenue):amount;}return finite(unit[sort as keyof EconomicUnit]);}
 const selection=useKpiReportSelection(),router=useRouter();
 function showAll(){const p=new URLSearchParams(selection?.query??query);for(const key of ['cost_center','group','unit','vehicle','project','category','kind','source','page'])p.delete(key);p.set('view','kpi');if(selection)selection.change(p.toString());else router.push('/kpi?'+p);}
 const visibleUnits=units.filter(u=>Number.isFinite(u.revenue)&&u.revenue>0);
 const lossCount=visibleUnits.filter(u=>u.result<0).length;
 const filteredUnits=lossOnly?visibleUnits.filter(u=>u.result<0):visibleUnits;
 const ordered=[...filteredUnits].sort((a,b)=>{const names=a.label.localeCompare(b.label,'sv',{numeric:true});if(sort==='label')return direction==='asc'?names:-names;const av=sortValue(a),bv=sortValue(b);if(av===null||bv===null)return av===bv?names:av===null?1:-1;return (direction==='asc'?av-bv:bv-av)||names;});
 const header=(interactive:boolean)=><thead><tr>{columns.map(c=>{const {key,label}=c,active=sort===key,arrow=active?(direction==='asc'?'↑':'↓'):'↕';return <th scope="col" key={key} className={styles.headingCell} style={{borderTop:'3px solid '+('color'in c?'rgb('+c.color+')':'#cbd5e1')}} aria-sort={active?(direction==='asc'?'ascending':'descending'):'none'}>{interactive?<button type="button" className={styles.sort} onClick={()=>changeSort(key)} aria-label={label+': sortera '+(active&&direction==='desc'?'stigande':'fallande')}>{label} <span aria-hidden="true">{arrow}</span></button>:<>{label} {arrow}</>}</th>;})}</tr></thead>;
 function costCell(amount:number|null,revenue:number,color:string,href?:string){
  const share=costShare(amount,revenue),amountText=amount===null?'–':compact.format(amount/1000)+' tkr',shareText=value(share,'%');
  const content=<><strong>{display==='share'?shareText:amountText}</strong><small>{display==='share'?amountText:shareText}{share!==null&&share>=100?' · ≥ intäkt':share!==null&&share<0?' · kredit':''}</small></>;
  return <div className={styles.costCell} style={{background:costShade(color,share)}} title={amount===null?'Underlag saknas':money.format(amount)+' · '+shareText+' av intäkterna'}>{href?<Link prefetch={false} href={href}>{content}</Link>:content}</div>;
 }
 function categoryTotal(category:string){const values=units.map(u=>finite(u.cost_categories?.[category]));return values.some(v=>v===null)?null:values.reduce<number>((sum,v)=>sum+(v??0),0);}
 function drill(unit:EconomicUnit,kind:string,category:string|null=null){return analysisHref(query,{unit:unit.key,vehicle:null,project:null,category,kind,level:'transaction'});}
 return <article className={'panel economic-units '+styles.panel}><h2>Ekonomiska enheter</h2>
 <div className="unit-table-controls"><EconomicGroupFilter query={query} groups={groups}/><div className={styles.switch} role="group" aria-label="Visning av kostnader"><button type="button" aria-pressed={display==='share'} onClick={()=>setDisplay('share')}>Andel %</button><button type="button" aria-pressed={display==='amount'} onClick={()=>setDisplay('amount')}>Belopp</button></div><label className={styles.check}><input type="checkbox" checked={showAllCosts} onChange={e=>{setShowAllCosts(e.target.checked);if(!e.target.checked&&costColumns.slice(5).some(c=>sort==='category:'+c.key))setSort('label');}}/>Alla kostnadsslag</label><label className={styles.check}><input type="checkbox" checked={lossOnly} onChange={e=>setLossOnly(e.target.checked)}/>Bara förlust ({lossCount})</label></div>
 <div className={styles.legend}><span><i style={{background:'#e9b9b9'}}/>Rött resultat = förlust</span><span><i style={{background:'#d8e3ff'}}/>Starkare kostnadsfärg = större andel av intäkt</span><span>Belopp i tkr · 1 tkr = 1 000 kr</span></div>
 <p className={styles.caption}>Sortera på valfri kolumn för att hitta höga kostnadsandelar. Kostnadsfärgerna visar storlek, inte avvikelse mot mål. Klicka på en kostnadsruta för dess transaktioner.</p>
 <KpiTableFrame head={header(true)} interactiveHead><table className={styles.table}>{header(false)}<tbody>{ordered.length===0&&<tr><td colSpan={columns.length}>Inga enheter matchar urvalet.</td></tr>}{ordered.map(u=><tr className="economic-parent" key={u.key}>
 <td className={styles.name}><Link prefetch={false} href={economicUnitHref(query,u.key)}><strong>{u.label.toLocaleLowerCase('sv').includes('grusmaterial')?'Grusmaterial':u.label} →</strong></Link><small>{u.children.length} objekt · {u.rows} rader</small></td>
 <td><Link prefetch={false} href={drill(u,'revenue')} title={money.format(u.revenue)}>{compact.format(u.revenue/1000)}</Link></td>
 <td><Link prefetch={false} href={drill(u,'cost')} title={money.format(u.cost)}>{compact.format(u.cost/1000)}</Link></td>
 <td className={u.result<0?styles.negative:styles.positive}><strong title={money.format(u.result)}>{compact.format(u.result/1000)}</strong><small>{u.result<0?'Förlust':'Överskott'}</small></td>
 <td className={u.result<0?styles.negative:styles.positive}><strong>{value(u.margin_pct,'%')}</strong></td>
 {shownCosts.map(c=><td key={c.key} className={styles.cost}>{costCell(finite(u.cost_categories?.[c.key]),u.revenue,c.color,drill(u,'cost',c.key))}</td>)}
 <td>{value(u.worked_hours,'h')}</td><td>{u.distance_basis==='main_vehicle_interpolated_period'&&u.distance_mil!=null?'≈ ':''}{value(u.distance_mil,'mil')}</td><td>{value(u.revenue_per_hour,'kr')}</td><td>{u.distance_basis==='main_vehicle_interpolated_period'&&u.cost_per_mil!=null?'≈ ':''}{value(u.cost_per_mil,'kr')}</td>
 </tr>)}</tbody><tfoot><tr><th scope="row">Hela urvalet</th><td title={money.format(totals.revenue)}>{compact.format(totals.revenue/1000)}</td><td title={money.format(totals.cost)}>{compact.format(totals.cost/1000)}</td><td title={money.format(totals.result)}>{compact.format(totals.result/1000)}</td><td>{totals.revenue===0?'–':value(totals.result/totals.revenue*100,'%')}</td>{shownCosts.map(c=><td key={c.key} className={styles.cost}>{costCell(categoryTotal(c.key),totals.revenue,c.color)}</td>)}<td>–</td><td>–</td><td>–</td><td>–</td></tr></tfoot></table></KpiTableFrame>
 <p className={styles.caption}>{ordered.length} av {visibleUnits.length} enheter med positiva intäkter visas. Totalraden gäller hela urvalet, även dolda enheter. Alla kostnadsslag visar även arbetsledning, overhead, övrigt, material, tipp/deponi och inhyrda. Personal är kostnad enligt underlaget. Timmar kommer från TransPA. ≈ är beräknad körsträcka. – betyder saknat underlag.</p>
 <div className="dashboard-report-actions"><Link prefetch={false} href="/kpi/ekonomiska-enheter">Alla mappade ekonomiska enheter →</Link><Link prefetch={false} href="/kpi/arbetskostnader">Arbetskostnad och NEXT-timmar →</Link><button type="button" className="secondary" disabled={selection?.pending} onClick={showAll}>Visa mappade enheter i alla kostnadsställen</button>{canManage&&<><Link prefetch={false} className="secondary" href={'/kpi/kontrollpanel?'+new URLSearchParams({...Object.fromEntries(new URLSearchParams(query)),section:'allocation'})}>Fördela kostnader →</Link><Link prefetch={false} href={'/kpi/kontrollpanel?'+new URLSearchParams({...Object.fromEntries(new URLSearchParams(query)),section:'units'})}>Hantera kostnadsbärare</Link></>}</div></article>;
}

function MaterialReconciliation({query}:{query:string}){
 const [rows,setRows]=useState<MaterialRow[]>([]);const [loading,setLoading]=useState(true);const [loadError,setLoadError]=useState('');
 useEffect(()=>{let active=true;fetch('/api/kpi/material-reconciliation?'+new URLSearchParams(query)).then(async r=>{const d=await r.json();if(!r.ok)throw Error(d.error??'Materialunderlaget kunde inte hämtas');if(active){setRows(d.rows??[]);setLoadError('');}}).catch(e=>{if(active){setRows([]);setLoadError(e.message);}}).finally(()=>{if(active)setLoading(false);});return()=>{active=false;};},[query]);
 return <section className="panel"><h2>Mängdavstämning</h2><p>Såld mängd från Workify för valda månader mot daterade inköpspriser. Visar endast rena materialartiklar; transportdelen hålls utanför.</p>{loadError?<p role="alert">{loadError}</p>:loading?<p>Hämtar mängder…</p>:<div className="table-wrap"><table><thead><tr><th>Material</th><th>Sålt</th><th>Intäkt</th><th>Vägt inköpspris</th><th>Ber. materialkostnad</th><th>Marginal</th><th>Marginal %</th></tr></thead><tbody>{rows.map(r=><tr key={r.material_key}><td><strong>{r.material_name}</strong><small>{r.material_key}{r.missing_price_rows>0?` · ${r.missing_price_rows} rader saknar pris eller mängd`:''}</small></td><td>{num.format(r.sold_quantity)} {r.unit}</td><td>{money.format(r.sale_amount)}</td><td>{r.purchase_price_per_unit==null?'Saknas':num.format(r.purchase_price_per_unit)+' kr/'+r.unit}</td><td>{r.estimated_purchase_cost==null?'–':money.format(r.estimated_purchase_cost)}</td><td>{r.gross_result==null?'–':money.format(r.gross_result)}</td><td>{value(r.margin_pct,'%')}</td></tr>)}</tbody></table></div>}<p>Beräknad materialkostnad är summan av varje rads mängd × inköpspriset på radens datum och ersätter inte bokförd NEXT-kostnad. Tabellen används som kontroll av marginal och mängd.</p></section>;
}
export function EconomicUnitDetail({unit:u,query}:{unit:EconomicUnit;query:string}){
 const link=(kind:string|null,category:string|null=null,child?:EconomicUnit['children'][number])=>analysisHref(query,{unit:u.key,vehicle:child?.vehicle??null,project:child?.vehicle?null:child?.project??null,kind,category:child?.key.startsWith('overhead:')?child.key.split(':')[1]:category,source:child?.key.startsWith('overhead:')?'Overhead':new URLSearchParams(query).get('source'),level:'transaction'});
 return <><section className="panel">{u.is_fallback?<p>Samlade övriga enheter och poster utan säker enhetskoppling. Kostnadsställe och period följer varje transaktion. Öppna underlaget för granskning och senare fördelning.</p>:<Link prefetch={false} href={'/kpi/ekonomiska-enheter?'+new URLSearchParams({unit:u.key})}>Kopplingar och historik i Humla →</Link>}<h2>{u.label.toLocaleLowerCase('sv').includes('grusmaterial')?'Grusmaterial':u.label}</h2><div className="analysis-totals"><Link prefetch={false} href={link('revenue')}>Omsättning<strong>{money.format(u.revenue)}</strong></Link><Link prefetch={false} href={link('cost')}>Kostnad<strong>{money.format(u.cost)}</strong></Link><div>Marginal<strong>{money.format(u.result)}</strong></div><div>Marginal %<strong>{value(u.margin_pct,'%')}</strong></div></div></section>
 <section className="panel"><h2>Mil och timmar</h2><div className="analysis-totals"><div>Arbetad tid<strong>{value(u.worked_hours,'h')}</strong></div><div>Körsträcka<strong>{u.distance_basis==='main_vehicle_interpolated_period'?'≈ ':''}{value(u.distance_mil,'mil')}</strong></div><div>Kostnad / timme<strong>{value(u.cost_per_hour,'kr/h')}</strong></div><div>Kostnad / mil<strong>{value(u.cost_per_mil,'kr/mil')}</strong></div></div><p>Arbetad tid bygger på TransPA. – betyder att verifierat underlag saknas för urvalet.</p></section>
 {u.label.toLocaleLowerCase('sv').includes('grusmaterial')&&<MaterialReconciliation key={query} query={query}/>}
 <section className="panel"><h2>Kostnader</h2><div className="table-wrap"><table><thead><tr><th>Kostnadsslag</th><th>Belopp</th></tr></thead><tbody>{costs.map(([key,label])=><tr key={key}><td><Link prefetch={false} href={link('cost',key)}>{label} →</Link></td><td><Link prefetch={false} href={link('cost',key)}>{u.cost_categories?.[key]==null?'–':money.format(u.cost_categories[key]!)}</Link></td></tr>)}</tbody></table></div></section>
 <section className="panel"><h2>Ingående fordon och projekt</h2><div className="table-wrap"><table><thead><tr><th>Objekt</th><th>Omsättning</th><th>Kostnad</th><th>Marginal</th><th>Transaktioner</th></tr></thead><tbody>{u.children.map(c=><tr key={c.key}><td><Link prefetch={false} href={link(null,null,c)}>{c.label} →</Link></td><td><Link prefetch={false} href={link('revenue',null,c)}>{money.format(c.revenue)}</Link></td><td><Link prefetch={false} href={link('cost',null,c)}>{money.format(c.cost)}</Link></td><td>{money.format(c.result)}</td><td><Link prefetch={false} href={link(null,null,c)}>{c.rows} rader →</Link></td></tr>)}</tbody></table></div><p>Objekten ingår i kostnadsbärarens total. Fördelade kostnader kan följas till originalet.</p></section>
 <details className="panel"><summary>Tid, körsträcka och övriga nyckeltal</summary><div className="table-wrap"><table><tbody>{ratios.filter(([k])=>k!=='margin_pct').map(([key,label,suffix])=><tr key={key}><th>{label}</th><td>{u.distance_basis==='main_vehicle_interpolated_period'&&['distance_mil','cost_per_mil','revenue_per_mil','fuel_cost_per_mil'].includes(key)&&u[key]!=null?'≈ ':''}{value(u[key],suffix)}</td></tr>)}</tbody></table></div><p>– betyder att verifierat underlag saknas. ≈ betyder att körsträckan beräknats mellan mätningar. Debiteringsgrad använder intäktskopplad TransPA-tid i förhållande till arbetad tid.</p></details><Link className="secondary" prefetch={false} href={link(null)}>Alla transaktioner för {u.label} →</Link></>;
}
