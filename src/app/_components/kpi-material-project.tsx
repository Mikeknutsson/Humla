import Link from 'next/link';
import {economicUnitHref,type EconomicUnit} from './kpi-economic-units';
import {analysisHref} from '@/lib/kpi/analysis';
const money=new Intl.NumberFormat('sv-SE',{style:'currency',currency:'SEK',maximumFractionDigits:0});
const percent=new Intl.NumberFormat('sv-SE',{maximumFractionDigits:1});
export function KpiMaterialProject({unit,unitId,query}:{unit?:EconomicUnit;unitId?:string|null;query:string}){
 const href=unitId?economicUnitHref(query,unitId):null;
 return <section className="panel" aria-labelledby="material-project-title">
  <div className="panel-head"><div><span className="section-kicker">Projekt · valt periodurval</span><h2 id="material-project-title">Grusmaterial</h2></div>{href&&<Link prefetch={false} href={href}>Visa projektet →</Link>}</div>
  {unit?<div className="metrics-grid">
   <Link prefetch={false} className="metric-card overview-card" href={analysisHref(query,{unit:unit.key,project:null,vehicle:null,kind:'revenue',category:null,level:'transaction'})}><span>Intäkter</span><strong>{money.format(unit.revenue)}</strong><small>Materialintäkter i valt urval</small></Link>
   <Link prefetch={false} className="metric-card overview-card" href={analysisHref(query,{unit:unit.key,project:null,vehicle:null,kind:'cost',category:null,level:'transaction'})}><span>Kostnader</span><strong>{money.format(unit.cost)}</strong><small>Registrerade kostnader i valt urval</small></Link>
   <Link prefetch={false} className="metric-card overview-card" href={href!}><span>Resultat</span><strong>{money.format(unit.result)}</strong><small>Intäkter minus kostnader</small></Link>
   <Link prefetch={false} className="metric-card overview-card" href={href!}><span>Marginal</span><strong>{unit.margin_pct==null?'Underlag saknas':percent.format(unit.margin_pct)+' %'}</strong><small>Av projektets intäkter</small></Link>
  </div>:<p>Grusmaterial har inget underlag i valt urval. Kontrollera period och filter.</p>}
  <p className="muted-line">Följer samma period och filter som rapporten. Beloppen ingår redan i totalsummorna. Intäkter och resultat följer Hubbens materialfördelning.</p>
 </section>;
}
