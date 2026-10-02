import Link from 'next/link';
import {analysisHref} from '@/lib/kpi/analysis';
import {fiscalMonths,monthLabels} from '@/lib/kpi/period';
export type MonthlyPoint={month:number;period_start:string;period_end:string;revenue:number;cost:number;result:number;rows:number};
const money=new Intl.NumberFormat('sv-SE',{style:'currency',currency:'SEK',maximumFractionDigits:0});
export function KpiMonthChart({points,query}:{points:MonthlyPoint[];query:string}) {
 const series=[{key:'revenue',label:'Omsättning',color:'#e1b500'},{key:'cost',label:'Kostnader',color:'#6c7d95'},{key:'result',label:'Resultat',color:'#16816a'}] as const;
 const min=Math.min(0,...points.map(p=>p.result));const max=Math.max(1,...points.flatMap(p=>[p.revenue,p.cost,p.result]));const range=max-min;
 const y=(v:number)=>245-(v-min)/range*200;
 const width=Math.max(720,points.length*80+100);const x=(i:number)=>70+(i+.5)*(width-100)/Math.max(points.length,1);
 function href(p:MonthlyPoint) {const q=new URLSearchParams(query);q.set('date_from',p.period_start);q.set('date_to',p.period_end);q.set('level','group');return analysisHref(q.toString());}
 return <section className="panel monthly-panel"><div className="panel-head"><div><span className="section-kicker">Ekonomisk utveckling</span><h2>Omsättning, kostnader och resultat per månad</h2></div><small>Klicka på en månad för detaljer</small></div>
 <div className="monthly-legend">{series.map(s=><span key={s.key}><i style={{background:s.color}}/>{s.label}</span>)}</div>
 <div className="monthly-scroll"><svg role="img" aria-label="Ekonomisk utveckling per vald månad" viewBox={`0 0 ${width} 290`} style={{minWidth:width}}>
 {[0,.5,1].map(t=>{const value=min+range*t;return <g key={t}><line x1="65" x2={width-20} y1={y(value)} y2={y(value)} stroke="#e7e9ec"/><text x="58" y={y(value)+4} textAnchor="end" fontSize="11" fill="#617084">{new Intl.NumberFormat('sv-SE',{notation:'compact',maximumFractionDigits:1}).format(value)}</text></g>})}
 <line x1="65" x2={width-20} y1={y(0)} y2={y(0)} stroke="#bac2cc"/>
 {series.map(s=><polyline key={s.key} fill="none" stroke={s.color} strokeWidth="3" points={points.map((p,i)=>`${x(i)},${y(p[s.key])}`).join(' ')}/>)}
 {points.map((p,i)=><Link prefetch={false} key={p.month} href={href(p)} aria-label={`${monthLabels[fiscalMonths.indexOf(p.month)]}: omsättning ${money.format(p.revenue)}, kostnader ${money.format(p.cost)}, resultat ${money.format(p.result)}. Öppna månad.`}><title>{`${p.period_start} · Omsättning ${money.format(p.revenue)} · Kostnader ${money.format(p.cost)} · Resultat ${money.format(p.result)}`}</title><rect x={x(i)-28} y="30" width="56" height="250" fill="transparent"/>{series.map(s=><circle key={s.key} cx={x(i)} cy={y(p[s.key])} r="5" fill={s.color} stroke="white" strokeWidth="2"/>)}<text x={x(i)} y="277" textAnchor="middle" fontSize="13" fill="#233347">{monthLabels[fiscalMonths.indexOf(p.month)]}</text></Link>)}
 </svg></div><details className="monthly-values"><summary>Visa månadsvärden</summary><div className="table-wrap"><table><thead><tr><th>Månad</th><th>Omsättning</th><th>Kostnader</th><th>Resultat</th></tr></thead><tbody>{points.map(p=><tr key={p.month}><td><Link prefetch={false} href={href(p)}>{monthLabels[fiscalMonths.indexOf(p.month)]}</Link></td><td>{money.format(p.revenue)}</td><td><Link prefetch={false} href={analysisHref(href(p).split('?')[1],{kind:'cost'})}>{money.format(p.cost)}</Link></td><td>{money.format(p.result)}</td></tr>)}</tbody></table></div></details>
 </section>;
}
