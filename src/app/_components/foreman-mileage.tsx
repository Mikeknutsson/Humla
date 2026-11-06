import type {TransportMileage} from '@/lib/kpi/transport-leader';
import styles from './foreman-mileage.module.css';
const number=new Intl.NumberFormat('sv-SE',{maximumFractionDigits:1});
const money=new Intl.NumberFormat('sv-SE',{style:'currency',currency:'SEK',maximumFractionDigits:0});
export function ForemanMileage({value:m}:{value?:TransportMileage}){
 const shown=(n:number|null|undefined)=>n==null?'–':(m?.estimated?'≈ ':'')+number.format(n);
 return <section className={styles.panel} aria-label="Körsträcka och milkostnad">
 <h4>Mil &amp; kostnad <small>{m?.source??'Humla Hub'}</small></h4>
 <div className={styles.grid}><div><span>Körsträcka · mil</span><strong>{shown(m?.distance_mil)}</strong></div><div><span>Kostnad · kr/mil</span><strong>{shown(m?.cost_per_mil)}</strong></div><div><span>Bränsle · kr/mil</span><strong>{shown(m?.fuel_cost_per_mil)}</strong></div></div>
 {m?.source_note&&<p className={styles.period}>{m.source_note}</p>}
 {m?.from&&m.to?<><p className={styles.period}>{m.complete?'Hela valt urval':'Del av valt urval'} · {m.covered_days}/{m.selected_days} kalenderdagar</p><details><summary>Mätperiod och beräkning</summary>
 <ul>{m.segments.map(s=><li key={s.vehicle+s.from+s.to}>{s.vehicle} · {s.from}–{s.to} · {s.basis==='interpolated'?'≈ ':''}{number.format(s.mil)} mil</li>)}</ul>
 <p>Kostnaderna avser exakt samma mätperioder: {m.matched_cost==null?'saknat kostnadsunderlag':money.format(m.matched_cost)}, varav bränsle {m.matched_fuel_cost==null?'saknat underlag':money.format(m.matched_fuel_cost)}. Beloppen ingår redan i kortets ekonomi.</p>
 <p>Huvudbilens körsträcka används. ≈ betyder beräkning mellan mätaravläsningar. Bränsle visas som kostnad per mil, inte liter per mil.</p>
 {m.reason&&<p>{m.reason}</p>}</details></>:<p className={styles.period}>{m?.reason??'Mätunderlaget kunde inte hämtas.'}</p>}
 </section>;
}
