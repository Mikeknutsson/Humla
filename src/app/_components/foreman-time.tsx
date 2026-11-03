import type {TransportTime} from '@/lib/kpi/transport-leader';
import styles from './foreman-mileage.module.css';
const number=new Intl.NumberFormat('sv-SE',{maximumFractionDigits:1});
const money=new Intl.NumberFormat('sv-SE',{style:'currency',currency:'SEK',maximumFractionDigits:0});
const show=(n:number|null|undefined)=>n==null?'–':number.format(n);
export function ForemanTime({value:t}:{value?:TransportTime}){
 return <section className={styles.panel} aria-label="Arbetstid och timkostnad">
 <h4>Timmar &amp; ekonomi <small>TransPA</small></h4>
 <div className={styles.grid}><div><span>Arbetad tid · h</span><strong>{show(t?.worked_hours)}</strong></div><div><span>Intäkt · kr/h</span><strong>{show(t?.revenue_per_hour)}</strong></div><div><span>Kostnad · kr/h</span><strong>{show(t?.cost_per_hour)}</strong></div></div>
 {t?.from&&t.to?<><p className={styles.period}>Registrerad tid · {t.from}–{t.to}{t.complete?'':' · del av valt urval'}</p>
 {(t.uncertain_reports??0)>0&&<p className={styles.period}>Tvetydiga tidskopplingar behöver granskas. Timnyckeltal visas inte.</p>}
 <details><summary>Tidsunderlag och beräkning</summary><p>{t.reports??0} tidsrapporter · {t.registered_days??0} dagar med registrerad tid.</p>
 <p>Intäkter {t.matched_revenue==null?'saknas':money.format(t.matched_revenue)} och kostnader {t.matched_cost==null?'saknas':money.format(t.matched_cost)} avser samma datumurval. Beloppen ingår redan i kortets ekonomi.</p>
 <p>{t.basis??'Registrerad arbetstid från TransPA. Saknad tid uppskattas inte.'}</p><p>Arbetade timmar är inte samma sak som fakturerade timmar.</p></details></>:<p className={styles.period}>{t?.reason??'Entydigt kopplad TransPA-arbetstid saknas i urvalet.'}</p>}
 </section>;
}
