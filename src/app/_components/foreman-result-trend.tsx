'use client';
import {useState,type PointerEvent} from 'react';
import {foremanTrendPlot,type ForemanTrend} from '@/lib/kpi/foreman-trend';
import styles from './foreman-result-trend.module.css';

const money=new Intl.NumberFormat('sv-SE',{style:'currency',currency:'SEK',maximumFractionDigits:0});
const number=new Intl.NumberFormat('sv-SE',{maximumFractionDigits:1});
const axis=new Intl.NumberFormat('sv-SE',{notation:'compact',maximumFractionDigits:1});
const date=(s:string)=>new Intl.DateTimeFormat('sv-SE',{day:'numeric',month:'short',timeZone:'UTC'}).format(new Date(s+'T00:00:00Z'));
const pct=(n:number|null)=>n==null?'–':number.format(n)+' %';

export function ForemanResultTrend({trend}:{trend:ForemanTrend}) {
 const [selected,setSelected]=useState(trend.points.length-1);
 if(!trend.latest||!trend.points.length)return <section className="panel"><h2>Resultatets utveckling</h2><p>Underlag saknas för perioden.</p></section>;
 const plot=foremanTrendPlot(trend);
 const point=trend.points[Math.max(0,Math.min(selected,trend.points.length-1))];
 const latest=trend.latest;
 const status=latest.deviation_amount==null?'unknown':latest.deviation_amount>=0?'above':'below';
 const pointer=(event:PointerEvent<SVGSVGElement>)=>{
  const bounds=event.currentTarget.getBoundingClientRect();
  const position=(event.clientX-bounds.left)/bounds.width*900;
  let nearest=0;
  for(let i=1;i<trend.points.length;i++)if(Math.abs(plot.x(trend.points[i].date)-position)<Math.abs(plot.x(trend.points[nearest].date)-position))nearest=i;
  setSelected(nearest);
 };
 return <section className={'panel '+styles.panel} aria-label="Resultatets utveckling för hela området">
 <div className={styles.heading}><div><h2>Resultatets utveckling</h2><p>Hela området · ackumulerat under vald period</p></div>
 <div className={styles.status} data-status={status}>{latest.deviation_amount==null?'Områdets mål är inte komplett':<><strong>{money.format(Math.abs(latest.deviation_amount))} {latest.deviation_amount>=0?'över':'under'} mål</strong><span>{pct(latest.margin_percent)} i resultat · mål {pct(latest.target_margin_percent)}</span></>}</div></div>
 <div className={styles.legend}><span><i className={styles.actualKey}/>Resultat</span>{plot.showTarget&&<span><i className={styles.targetKey}/>Mål för hela området</span>}</div>
 <div className={styles.scroll}><svg className={styles.chart} viewBox="0 0 900 225" role="img" aria-label={'Ackumulerat resultat '+money.format(latest.result)+(plot.showTarget?', mål '+money.format(latest.target_result!):'. Mål saknas för delar av området')} onPointerMove={pointer} onPointerLeave={()=>setSelected(trend.points.length-1)}>
 {plot.ticks.map((value,i)=><g key={i}><line x1="64" x2="856" y1={plot.y(value)} y2={plot.y(value)} stroke="#e8edf2"/><text x="54" y={plot.y(value)+4} textAnchor="end" className={styles.axis}>{axis.format(value)} kr</text></g>)}
 <line x1="64" x2="856" y1={plot.zero} y2={plot.zero} stroke="#96a4b3" strokeDasharray="3 4"/>
 <path d={plot.area} fill="#1769aa" fillOpacity=".07"/>
 {plot.showTarget&&<path d={plot.target} fill="none" stroke="#b68508" strokeWidth="2.5" strokeDasharray="7 5" strokeLinejoin="round"/>}
 <path d={plot.actual} fill="none" stroke="#1769aa" strokeWidth="3" strokeLinejoin="round" strokeLinecap="round"/>
 <line x1={plot.x(point.date)} x2={plot.x(point.date)} y1="18" y2="192" stroke="#9aa9b8" strokeDasharray="3 4"/>
 {plot.showTarget&&point.target_result!=null&&<circle cx={plot.x(point.date)} cy={plot.y(point.target_result)} r="4" fill="#b68508"/>}
 <circle cx={plot.x(point.date)} cy={plot.y(point.result)} r="5" fill="#1769aa" stroke="white" strokeWidth="2"/>
 <text x="64" y="216" className={styles.axis}>{date(trend.from)}</text><text x="460" y="216" textAnchor="middle" className={styles.axis}>{date(new Date((Date.parse(trend.from)+Date.parse(trend.to))/2).toISOString().slice(0,10))}</text><text x="856" y="216" textAnchor="end" className={styles.axis}>{date(trend.to)}</text>
 </svg></div>
 <div className={styles.readout}><strong>{date(point.date)}</strong><span>Resultat <b>{money.format(point.result)}</b></span><span>Resultat % <b>{pct(point.margin_percent)}</b></span>{plot.showTarget&&<span>Mål <b>{point.target_result==null?'–':money.format(point.target_result)}</b></span>}</div>
 <input className={styles.slider} type="range" min="0" max={Math.max(0,trend.points.length-1)} value={Math.max(0,selected)} disabled={trend.points.length<2} onChange={e=>setSelected(Number(e.target.value))} aria-label="Följ resultatet datum för datum" aria-valuetext={date(point.date)+': '+money.format(point.result)}/>
 <p className={styles.caption}>För musen över linjen eller dra reglaget för att följa utvecklingen. {plot.showTarget?(trend.area_target_margin_percent!=null?'Mållinjen visar '+pct(trend.area_target_margin_percent)+' av hela områdets intäkter.':'Mållinjen följer intäkterna och de satta marginalmålen.'):'Mål saknas för en eller flera intäktsposter, därför visas ingen gemensam mållinje.'} Visar inläst underlag, ingen prognos.</p>
 <details className={styles.details}><summary>Visa siffror per datum</summary><div className="monthly-scroll"><table><caption>Ackumulerat från {trend.from}</caption><thead><tr><th>Datum</th><th>Intäkter</th><th>Kostnader</th><th>Resultat</th><th>Resultat %</th><th>Mål kr</th></tr></thead><tbody>{trend.points.map(p=><tr key={p.date}><th scope="row">{p.date}</th><td>{money.format(p.revenue)}</td><td>{money.format(p.cost)}</td><td>{money.format(p.result)}</td><td>{pct(p.margin_percent)}</td><td>{plot.showTarget&&p.target_result!=null?money.format(p.target_result):'Mål saknas'}</td></tr>)}</tbody></table></div></details>
 </section>;
}
