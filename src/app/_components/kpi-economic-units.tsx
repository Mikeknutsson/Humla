'use client';
import {useState,useTransition} from 'react';
import Link from 'next/link';
import {KpiTableFrame} from './kpi-table-frame';
import {KpiGroupFilter} from './kpi-cost-center-filter';
import {analysisHref} from '@/lib/kpi/analysis';
import {useRouter} from 'next/navigation';
import {useKpiReportSelection} from './kpi-report-selection';
export type EconomicUnit={key:string;label:string;revenue:number;cost:number;result:number;rows:number;
 cost_categories?:Record<string,number|null>;margin_pct?:number|null;worked_hours?:number|null;productive_hours?:number|null;
 billing_percent?:number|null;utilization?:number|null;occupied_hours?:number|null;available_hours?:number|null;
 revenue_per_hour?:number|null;cost_per_hour?:number|null;distance_mil?:number|null;cost_per_mil?:number|null;
 distance_basis?:string;
 revenue_per_mil?:number|null;fuel_cost_per_mil?:number|null;fuel_liters_per_mil?:number|null;
 children:Array<{key:string;label:string;vehicle:string|null;project:string|null;revenue:number;cost:number;result:number;rows:number}>};
const money=new Intl.NumberFormat('sv-SE',{style:'currency',currency:'SEK',maximumFractionDigits:0});
const num=new Intl.NumberFormat('sv-SE',{maximumFractionDigits:1});
const costs=[['personnel','Personal'],['fuel','Bränsle'],['service_repair','Service & Rep'],['fixed','Fasta'],['depreciation','Avskrivning'],['material','Material'],['tipp_deponi','Tipp/Deponi'],['hired','Inhyrda'],['other','Övrigt']] as const;
const ratios=[['margin_pct','Marginal','%'],['worked_hours','Arbetad tid','h'],['billing_percent','Debiteringsgrad*','%'],['utilization','Beläggningsgrad','%'],['revenue_per_hour','Intäkt / h','kr'],['cost_per_hour','Kostnad / h','kr'],['distance_mil','Körsträcka','mil'],['cost_per_mil','Kostnad / mil','kr'],['revenue_per_mil','Intäkt / mil','kr'],['fuel_cost_per_mil','Bränsle / mil','kr'],['fuel_liters_per_mil','Förbrukning / mil','l']] as const;
function value(n:number|null|undefined,suffix:string){return n==null?'–':num.format(n)+' '+suffix;}
function EconomicGroupFilter({query,groups}:{query:string;groups:string[]}){
 const selection=useKpiReportSelection(),router=useRouter();const [pending,start]=useTransition();
 const selectedGroup=new URLSearchParams(selection?.query??query).get('group')??'';
 function change(group:string){const p=new URLSearchParams(selection?.query??query);p.set('view','kpi');if(group)p.set('group',group);else p.delete('group');for(const k of ['unit','vehicle','project'])p.delete(k);if(selection)selection.change(p.toString());else start(()=>router.push('/kpi?'+p));}
 return <KpiGroupFilter value={selectedGroup} groups={groups} disabled={pending} onChange={change}/>;
}
export function economicUnitHref(query:string,unit:string){const p=new URLSearchParams(query);p.set('unit',unit);for(const k of ['vehicle','project','category','kind','source','page','view','level','grain'])p.delete(k);return '/kpi/enhet?'+p;}
export function KpiEconomicUnits({units,query,totals,canManage,groups=[]}:{units:EconomicUnit[];query:string;totals:{revenue:number;cost:number;result:number};canManage:boolean;groups:string[]}){
 const [sort,setSort]=useState('label');
 const ordered=[...units].sort((a,b)=>sort==='label'?a.label.localeCompare(b.label,'sv'):((b[sort as keyof EconomicUnit] as number|null)??-Infinity)-((a[sort as keyof EconomicUnit] as number|null)??-Infinity));
 const head=<thead><tr><th>Kostnadsbärare</th><th>Omsättning</th><th>Kostnad</th><th>Marginal</th><th>Marginal %</th></tr></thead>;
 return <article className="panel economic-units"><h2>Kostnadsbärare</h2><div className="unit-table-controls"><EconomicGroupFilter query={query} groups={groups}/><label>Sortera<select value={sort} onChange={e=>setSort(e.target.value)}><option value="label">Namn</option><option value="revenue">Omsättning, högst först</option><option value="cost">Kostnad, högst först</option><option value="result">Marginal, högst först</option><option value="margin_pct">Marginal %, högst först</option></select></label><span>{units.length} kostnadsbärare</span></div><p>Välj en kostnadsbärare för samlad ekonomi, ingående objekt och transaktioner.</p>
 <KpiTableFrame head={head}><table>{head}<tbody>{ordered.map(u=><tr className="economic-parent" key={u.key}><td><Link prefetch={false} href={economicUnitHref(query,u.key)}><strong>{u.label} →</strong></Link><small>{u.children.length} ingående objekt · {u.rows} transaktioner</small></td><td><Link prefetch={false} href={analysisHref(query,{unit:u.key,vehicle:null,project:null,category:null,kind:'revenue',level:'transaction'})}>{money.format(u.revenue)}</Link></td><td><Link prefetch={false} href={analysisHref(query,{unit:u.key,vehicle:null,project:null,category:null,kind:'cost',level:'project'})}>{money.format(u.cost)}</Link></td><td><strong>{money.format(u.result)}</strong></td><td>{value(u.margin_pct,'%')}</td></tr>)}</tbody><tfoot><tr><th>Totalt för urvalet</th><td>{money.format(totals.revenue)}</td><td>{money.format(totals.cost)}</td><td>{money.format(totals.result)}</td><td>{totals.revenue===0?'–':value(totals.result/totals.revenue*100,'%')}</td></tr></tfoot></table></KpiTableFrame>
 {canManage&&<div className="dashboard-report-actions"><Link prefetch={false} className="secondary" href={'/kpi/kontrollpanel?'+new URLSearchParams({...Object.fromEntries(new URLSearchParams(query)),section:'allocation'})}>Fördela kostnader →</Link><Link prefetch={false} href={'/kpi/kontrollpanel?'+new URLSearchParams({...Object.fromEntries(new URLSearchParams(query)),section:'units'})}>Hantera kostnadsbärare</Link></div>}</article>;
}
export function EconomicUnitDetail({unit:u,query}:{unit:EconomicUnit;query:string}){
 const link=(kind:string|null,category:string|null=null,child?:EconomicUnit['children'][number])=>analysisHref(query,{unit:u.key,vehicle:child?.vehicle??null,project:child?.vehicle?null:child?.project??null,kind,category,level:'transaction'});
 return <><section className="panel"><h2>{u.label}</h2><div className="analysis-totals"><Link prefetch={false} href={link('revenue')}>Omsättning<strong>{money.format(u.revenue)}</strong></Link><Link prefetch={false} href={link('cost')}>Kostnad<strong>{money.format(u.cost)}</strong></Link><div>Marginal<strong>{money.format(u.result)}</strong></div><div>Marginal %<strong>{value(u.margin_pct,'%')}</strong></div></div></section>
 <section className="panel"><h2>Kostnader</h2><div className="table-wrap"><table><thead><tr><th>Kostnadsslag</th><th>Belopp</th></tr></thead><tbody>{costs.map(([key,label])=><tr key={key}><td><Link prefetch={false} href={link('cost',key)}>{label} →</Link></td><td><Link prefetch={false} href={link('cost',key)}>{u.cost_categories?.[key]==null?'–':money.format(u.cost_categories[key]!)}</Link></td></tr>)}</tbody></table></div></section>
 <section className="panel"><h2>Ingående fordon och projekt</h2><div className="table-wrap"><table><thead><tr><th>Objekt</th><th>Omsättning</th><th>Kostnad</th><th>Marginal</th><th>Transaktioner</th></tr></thead><tbody>{u.children.map(c=><tr key={c.key}><td><Link prefetch={false} href={link(null,null,c)}>{c.label} →</Link></td><td><Link prefetch={false} href={link('revenue',null,c)}>{money.format(c.revenue)}</Link></td><td><Link prefetch={false} href={link('cost',null,c)}>{money.format(c.cost)}</Link></td><td>{money.format(c.result)}</td><td><Link prefetch={false} href={link(null,null,c)}>{c.rows} rader →</Link></td></tr>)}</tbody></table></div><p>Objekten ingår i kostnadsbärarens total. Fördelade kostnader kan följas till originalet.</p></section>
 <details className="panel"><summary>Tid, körsträcka och övriga nyckeltal</summary><div className="table-wrap"><table><tbody>{ratios.filter(([k])=>k!=='margin_pct').map(([key,label,suffix])=><tr key={key}><th>{label}</th><td>{u.distance_basis==='main_vehicle_interpolated_period'&&['distance_mil','cost_per_mil','revenue_per_mil','fuel_cost_per_mil'].includes(key)&&u[key]!=null?'≈ ':''}{value(u[key],suffix)}</td></tr>)}</tbody></table></div><p>– betyder att verifierat underlag saknas. ≈ betyder att körsträckan beräknats mellan mätningar. Debiteringsgrad använder intäktskopplad TransPA-tid i förhållande till arbetad tid.</p></details><Link className="secondary" prefetch={false} href={link(null)}>Alla transaktioner för {u.label} →</Link></>;
}
