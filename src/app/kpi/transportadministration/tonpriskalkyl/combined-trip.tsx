'use client';

import {useState} from 'react';
import {googleRoadEstimate} from '@/app/_components/google-address-field';
import {useGoogleMapsKey} from '@/app/_components/google-maps-provider';
import {compareCombinedTrip} from '@/lib/hub/ton-price-combined-trip';
import {offerMoney} from '@/lib/hub/ton-price-offer';
import type {RatedMaterial} from './quarry-comparison';
import styles from './workspace.module.css';

const decimals = new Intl.NumberFormat('sv-SE',{maximumFractionDigits:2});

export default function CombinedTripSection({delivery,tipping,hourly}: {
  delivery?: RatedMaterial[]; tipping?: RatedMaterial[]; hourly:number;
}) {
  const [open,setOpen] = useState(false);
  const ready = delivery?.length && tipping?.length;

  if (!open && !ready) return null;
  return <details className={styles.card} open={open} onToggle={event => setOpen(event.currentTarget.open)}>
    <summary>Jämför samkörning med bil + kärra</summary>
    {ready
      ? <CombinedTrip key={JSON.stringify([delivery,tipping])} delivery={delivery} tipping={tipping} hourly={hourly}/>
      : <p role="status">Samkörning kräver ett beräknat alternativ för både leverans och bortkörning.</p>}
  </details>;
}

function CombinedTrip({delivery,tipping,hourly}: {delivery: RatedMaterial[]; tipping: RatedMaterial[]; hourly: number}) {
  const [source,setSource] = useState(0);
  const [target,setTarget] = useState(0);
  const [route,setRoute] = useState<Awaited<ReturnType<typeof googleRoadEstimate>>>();
  const [error,setError] = useState('');
  const [busy,setBusy] = useState(false);
  const mapsKey = useGoogleMapsKey();
  const quarry = delivery[source].option;
  const tip = tipping[target].option;
  const eligible = Boolean(quarry.trips && tip.trips && !quarry.round.returnLoad && !tip.round.returnLoad);
  const routed = mapsKey && (quarry.site.address || quarry.site.mapPlaceId) && (tip.site.address || tip.site.mapPlaceId);
  const comparison = route && compareCombinedTrip(quarry,tip,route);
  async function calculate() {
    if (!mapsKey && quarry.site.id !== tip.site.id) return;
    setBusy(true);
    setError('');
    try {
      setRoute(quarry.site.id === tip.site.id ? {miles:'0',driveMinutes:'0'} :
        await googleRoadEstimate(mapsKey!,{address:tip.site.address,id:tip.site.mapPlaceId},{address:quarry.site.address,id:quarry.site.mapPlaceId}));
    } catch {
      setError('Körsträckan från tippen tillbaka till täkten kunde inte hämtas.');
    } finally {
      setBusy(false);
    }
  }
  return <>
    <div className={styles.grid}>
      <label className={styles.field}>Leverans
        <select disabled={busy} value={source} onChange={event => {setSource(Number(event.target.value));setRoute(undefined);setError('');}}>
          {delivery.map((row,index) => <option key={row.material} value={index}>{row.material} · {row.option.site.name}</option>)}
        </select>
      </label>
      <label className={styles.field}>Bortkörning
        <select disabled={busy} value={target} onChange={event => {setTarget(Number(event.target.value));setRoute(undefined);setError('');}}>
          {tipping.map((row,index) => <option key={row.material} value={index}>{row.material} · {row.option.site.name}</option>)}
        </select>
      </label>
    </div>
    <p>Pukavik → {quarry.site.name} → projektet → {tip.site.name} → {quarry.site.name}</p>
    {!eligible && <p>Ange ton för båda materialen. Jämförelsen gäller rundor där ingen annan returlast är inräknad.</p>}
    {eligible && !routed && quarry.site.id !== tip.site.id && <p>En körbar rutt från tippen till täkten behövs för jämförelsen.</p>}
    <button type="button" className="secondary" disabled={busy || !eligible || (!routed && quarry.site.id !== tip.site.id)}
      onClick={() => void calculate()}>{busy ? 'Beräknar…' : 'Beräkna samkörning'}</button>
    {error && <p role="alert">{error}</p>}
    {comparison && <div aria-live="polite">
      <p>{comparison.pairs} kombinerade rundor. Övriga lass räknas som egna rundor.</p>
      <div className={styles.table}><table>
        <thead><tr><th>Körning</th><th>Mil</th><th>Timmar</th><th>Beräknad transportkostnad</th></tr></thead>
        <tbody>{([['Separat','separate'],['Samkörning','combined']] as const).map(([label,key]) => <tr key={key}>
          <td>{label}</td><td>{decimals.format(comparison.miles[key])}</td><td>{decimals.format(comparison.minutes[key]/60)}</td>
          <td>{offerMoney.format(comparison.minutes[key]/60*hourly)} kr</td>
        </tr>)}</tbody>
      </table></div>
      <p>Skillnad vid samkörning (separat minus samkörning) {decimals.format(comparison.miles.saved)} mil · {decimals.format(comparison.minutes.saved/60)} timmar · {offerMoney.format(comparison.minutes.saved/60*hourly)} kr.</p>
      <small>Jämförelsen är ett internt kalkylunderlag. Offertpriset bygger på separata körningar.</small>
    </div>}
  </>;
}
