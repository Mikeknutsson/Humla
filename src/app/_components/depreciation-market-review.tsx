import type {Asset} from '@/lib/hub/asset-tco';
import {reviewLabels} from '@/lib/hub/market-review';
import styles from './asset-tco-workspace.module.css';
const money=(n:number|null|undefined)=>n==null?'Saknas':`${new Intl.NumberFormat('sv-SE',{maximumFractionDigits:0}).format(n)} kr`;
export function DepreciationMarketReview({asset,editable,today,busy,onSubmit}:{asset:Asset;editable:boolean;today:string;busy:boolean;onSubmit:(e:React.FormEvent<HTMLFormElement>)=>void}){
 const r=asset.market_review;if(!r)return null;
 const gap=r.gap;const context=r.context;const estimate=r.estimate;
 const eligible=(r.sold_stats?.n??0)+(r.asking_stats?.n??0);
 return <section className="panel">
 <h2>Avskrivning jämfört med marknaden · {asset.registration||asset.description}</h2>
 <div className={styles.cards}>
 <div className={styles.stat}><h3>Värde enligt avskrivningsmodellen</h3><strong>{money(r.reference)}</strong><p>{r.reference_kind==='register_model'?'Linjärt från inköpsdatum enligt registret':'Planerat värde enligt innehavsprofilen'}</p></div>
 <div className={styles.stat}><h3>Uppskattat marknadsvärde</h3><strong>{estimate?money(estimate.median):'Prisunderlag behövs'}</strong>{estimate?<><p>{money(estimate.low)} – {money(estimate.high)}</p><p>{estimate.n} objekt · {estimate.sources} källor · {estimate.basis==='sold'?'bekräftade försäljningar':'annonspriser'}</p><p>Senaste prisdatum {estimate.latest_date} · {r.price_basis==='net'?'exklusive':'inklusive'} moms</p></>:<p>Minst tre kontrollerade objekt av samma pristyp behövs.</p>}</div>
 <div className={styles.stat}><h3>Marknad minus modell</h3><strong>{gap.status==='compared'?money(gap.delta):'Ej jämförbart ännu'}</strong><p>{gap.status==='compared'?(gap.percent==null?'Procent kan inte räknas mot 0 kr':`${new Intl.NumberFormat('sv-SE',{maximumFractionDigits:1,signDisplay:'always'}).format(gap.percent)} % av modellvärdet`):gap.status==='basis_unconfirmed'?'Bekräfta samma momsgrund för båda värdena':gap.status==='missing_reference'?'Inköpsunderlag eller avskrivningsmodell saknas':'Marknadspriser behöver kompletteras'}</p></div>
 </div>
 <p role="status"><strong>{gap.status==='compared'?reviewLabels[gap.direction]:gap.status==='basis_unconfirmed'?'Momsgrund behöver bekräftas':gap.status==='missing_reference'?'Modellvärde saknas':'Marknadsjämförelse väntar på underlag'}</strong></p>
 <p>Avvikelsen jämför medianen med modellvärdet. En granskningssignal kräver över 20 % avvikelse, hela prisintervallet på samma sida om modellvärdet, minst två källor och högst 50 % spridning mellan lägsta och högsta pris. Annonspriser ger lägre säkerhet än bekräftade försäljningar. Ingen bokförd avskrivning ändras.</p>
 <p>{r.total_rows} sparade prisobjekt · {eligible} klarar datum, årsmodell, mätarställning, momsgrund och bekräftad jämförbarhet. {r.model_year==null?'Årsmodell behöver kompletteras. ':''}{r.meter_type!=='none'&&r.meter==null?'Jämförbar mätarställning saknas. ':''}{!r.price_basis?'Välj prisgrund för marknadspriserna. ':''}</p>
 {editable?<details open={!context}><summary>Uppgifter för marknadsjämförelsen</summary>
 <p>Detta kräver ingen komplett TCO-profil. Ange årsmodell och prisgrund, och lägg sedan till kontrollerade prisobjekt under ”Lägg till jämförelseobjekt” längre ned. För släp kan ”Ingen mätare” väljas.</p>
 <form className={styles.form} onSubmit={onSubmit} key={JSON.stringify(context)}>
 <label>Årsmodell för vårt fordon<input name="model_year" type="number" required min="1900" max={Number(today.slice(0,4))+1} defaultValue={r.model_year??''}/></label>
 <label>Mätartyp för jämförelsen<select name="meter_type" defaultValue={r.meter_type}><option value="odometer_km">Kilometer</option><option value="engine_hours">Drifttimmar</option><option value="none">Ingen mätare / släp</option></select></label>
 <label>Marknadsprisernas momsgrund<select name="price_basis" required defaultValue={r.price_basis??''}><option value="" disabled>Välj momsgrund</option><option value="net">Exklusive moms</option><option value="gross">Inklusive moms</option></select></label>
 <label>Inköpsbeloppets momsgrund i registret<select name="register_price_basis" defaultValue={context?.register_price_basis??'unknown'}><option value="unknown">Ej bekräftad ännu</option><option value="net">Bekräftat exklusive moms</option><option value="gross">Bekräftat inklusive moms</option></select></label>
 <label className={styles.wide}>Utförande att matcha<input name="variant" maxLength={300} defaultValue={context?.variant??asset.ownership?.variant??asset.description??''} placeholder="Axlar, påbyggnad och utrustning"/></label>
 <button disabled={busy}>Spara jämförelseuppgifter</button>
 </form></details>:<p>Fordonsadministratör kan komplettera jämförelseuppgifterna när dagens datum är valt.</p>}
 </section>;
}
