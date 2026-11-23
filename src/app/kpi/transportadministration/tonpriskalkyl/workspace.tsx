'use client';

import {useEffect, useState} from 'react';
import {Calculator, ExternalLink, Plus, Printer, Trash2} from 'lucide-react';
import {initialTonPriceDraft, newMaterial, newRound, type calculateTonPrices, type Material, type Round, type TonPriceDraft, type Vehicle} from '@/lib/hub/ton-price';
import {recalculateTonPrices} from './actions';
import styles from './workspace.module.css';

const decimals = new Intl.NumberFormat('sv-SE', {maximumFractionDigits: 2});
const whole = new Intl.NumberFormat('sv-SE', {maximumFractionDigits: 0});
const format = (value: number | undefined | null) => value == null ? '–' : decimals.format(value);
const profiles = [['reference', 'Excel-last'], ['bk1', 'BK1'], ['bk4', 'BK4']] as const;

function Field({label, value, onChange, numeric = false, placeholder, type = 'text'}: {
  label: string; value: string; onChange: (value: string) => void; numeric?: boolean; placeholder?: string; type?: string;
}) {
  return <label className={styles.field}>{label}
    <input type={type} value={value} maxLength={numeric ? 16 : 240} inputMode={numeric ? 'decimal' : undefined}
      onChange={event => onChange(event.target.value)} placeholder={placeholder}/>
  </label>;
}

function mapLink(origin: string, destination: string) {
  return `https://www.google.com/maps/dir/?${new URLSearchParams({api: '1', origin, destination, travelmode: 'driving'})}`;
}

function RoundEditor({round, index, change, remove}: {
  round: Round; index: number; change: (patch: Partial<Round>) => void; remove?: () => void;
}) {
  const field = (key: 'pickup' | 'delivery' | 'returnTo' | 'minutesPerMile' | 'loading' | 'unloading' | 'waiting', label: string, numeric = false) =>
    <Field key={key} label={label} value={round[key]} onChange={value => change({[key]: value})} numeric={numeric}/>;
  const legs = round.mirror ? ['outbound'] as const : ['outbound', 'inbound'] as const;
  const returnTo = round.returnTo.trim() || round.pickup.trim();
  return <fieldset className={styles.card}>
    <legend>Runda {index + 1}</legend>
    <div className={styles.grid}>
      {field('pickup', 'Täkt / hämtningsadress')}
      {field('delivery', 'Leveransadress')}
      {!round.mirror && field('returnTo', 'Returadress (valfri)')}
    </div>
    <div className={styles.actions}>
      <label><input type="checkbox" checked={round.mirror} onChange={event => change({mirror: event.target.checked})}/> Samma sträcka och körtid på returen</label>
      {round.pickup.trim() && round.delivery.trim() && <a href={mapLink(round.pickup, round.delivery)} target="_blank" rel="noreferrer"><ExternalLink size={14}/> Karta dit</a>}
      {!round.mirror && round.delivery.trim() && returnTo && <a href={mapLink(round.delivery, returnTo)} target="_blank" rel="noreferrer"><ExternalLink size={14}/> Karta retur</a>}
    </div>
    <div className={styles.grid}>
      {legs.map(key => <div className={styles.pair} key={key}>
        <Field label={key === 'outbound' ? 'Dit (mil)' : 'Retur (mil)'} value={round[key].miles} numeric
          onChange={miles => change({[key]: {...round[key], miles}})}/>
        <Field label={key === 'outbound' ? 'Körtid dit (min)' : 'Körtid retur (min)'} value={round[key].driveMinutes} numeric
          placeholder="Använd schablon" onChange={driveMinutes => change({[key]: {...round[key], driveMinutes}})}/>
      </div>)}
      {field('minutesPerMile', 'Schablon (min/mil)', true)}
      {field('loading', 'Lastning (min)', true)}
      {field('unloading', 'Lossning (min)', true)}
      {field('waiting', 'Väntetid (min)', true)}
    </div>
    {remove && <button type="button" className="secondary" onClick={remove}><Trash2 size={15}/> Ta bort runda</button>}
  </fieldset>;
}

function MaterialEditor({material, index, draft, change, remove}: {
  material: Material; index: number; draft: TonPriceDraft; change: (patch: Partial<Material>) => void; remove?: () => void;
}) {
  const field = (key: 'name' | 'listPrice' | 'discount' | 'purchase' | 'markup' | 'sale' | 'tonnes', label: string, placeholder?: string) =>
    <Field key={key} label={label} value={material[key]} onChange={value => change({[key]: value})} numeric={key !== 'name'} placeholder={placeholder}/>;
  return <fieldset className={styles.card}>
    <legend>Rad {index + 1}</legend>
    <div className={styles.grid}>
      {material.transportOnly ? <strong>Enbart transport</strong> : field('name', 'Material')}
      <label className={styles.field}>Runda<select value={material.roundId} onChange={event => change({roundId: event.target.value})}>
        {draft.rounds.map((round, i) => <option key={round.id} value={round.id}>{round.pickup || `Runda ${i + 1}`}</option>)}
      </select></label>
      <label className={styles.field}>Ekipage i offert<select value={material.vehicleId} onChange={event => change({vehicleId: event.target.value})}>
        {draft.vehicles.map(vehicle => <option key={vehicle.id} value={vehicle.id}>{vehicle.name}</option>)}
      </select></label>
      {field('tonnes', 'Mängd (ton)', 'Valfritt')}
    </div>
    {!material.transportOnly && <div className={styles.grid}>
      {field('listPrice', 'Listpris (kr/ton)')}{field('discount', 'Inköpsrabatt (%)')}
      {field('purchase', 'Inköpspris (kr/ton)', 'Beräknas från listpris')}
      {field('markup', 'Materialpåslag (%)')}{field('sale', 'Eget säljpris (kr/ton)', 'Beräknas från inköp')}
    </div>}
    <div className={styles.actions}>
      <label><input type="checkbox" checked={material.transportOnly} onChange={event => change({transportOnly: event.target.checked})}/> Enbart transport</label>
      {remove && <button type="button" className="secondary" onClick={remove}><Trash2 size={15}/> Ta bort rad</button>}
    </div>
  </fieldset>;
}

function replace<T extends {id: string}>(items: T[], id: string, patch: Partial<T>) {
  return items.map(item => item.id === id ? {...item, ...patch} : item);
}

export default function TonPriceWorkspace({draftKey}: {draftKey: string}) {
  const [draft, setDraft] = useState(initialTonPriceDraft);
  const [result, setResult] = useState<ReturnType<typeof calculateTonPrices>>();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  useEffect(() => {
    const timer = window.setTimeout(() => {
      try {
        const saved = window.localStorage.getItem(draftKey);
        if (saved) setDraft(JSON.parse(saved));
      } catch {
        // A blocked browser store does not prevent calculating a price.
      }
    }, 0);
    return () => window.clearTimeout(timer);
  }, [draftKey]);

  function change(patch: Partial<TonPriceDraft>) {
    const updated = {...draft, ...patch};
    setDraft(updated);
    setResult(undefined);
    setError('');
    try {
      window.localStorage.setItem(draftKey, JSON.stringify(updated));
    } catch {
      setError('Webbläsaren kunde inte spara utkastet.');
    }
  }

  async function calculate() {
    setBusy(true);
    setError('');
    try {
      const response = await recalculateTonPrices(draft);
      setResult(response.result);
      if (response.error) setError(response.error);
    } catch {
      setError('Kalkylen kunde inte beräknas. Försök igen.');
    } finally {
      setBusy(false);
    }
  }

  const complete = result && result.materials.length > 0 && result.materials.every(row => !row.status);
  return <div className={`content ${styles.workspace}`}>
    <form className={styles.controls} onSubmit={event => {event.preventDefault(); void calculate();}}>
      <fieldset disabled={busy} className={styles.form}>
        <section className="panel">
          <h2>Kund och projekt</h2>
          <div className={styles.grid}>
            <Field label="Kund" value={draft.customer} onChange={customer => change({customer})}/>
            <Field label="Projekt" value={draft.project} onChange={project => change({project})}/>
            <Field label="Giltig till" type="date" value={draft.validity} onChange={validity => change({validity})}/>
            <Field label="Offertvillkor" value={draft.terms} onChange={terms => change({terms})}/>
          </div>
          <small>Utkastet sparas i den här webbläsaren.</small>
        </section>
        <section className="panel">
          <h2>Rundor</h2>
          <p>Fyll i körsträcka och körtid för lastbil. Tom körtid räknas med schablonen.</p>
          {draft.rounds.map((round, index) => <RoundEditor key={round.id} round={round} index={index}
            change={patch => change({rounds: replace(draft.rounds, round.id, patch)})}
            remove={draft.rounds.length > 1 && !draft.materials.some(material => material.roundId === round.id)
              ? () => change({rounds: draft.rounds.filter(item => item.id !== round.id)}) : undefined}/>)}
          <button type="button" className="secondary" disabled={draft.rounds.length >= 30}
            onClick={() => change({rounds: [...draft.rounds, newRound(crypto.randomUUID())]})}><Plus size={16}/> Lägg till runda</button>
        </section>
        <section className="panel">
          <h2>Ekipage och vikt</h2>
          <p>Excel-lasterna är referensvärden. Fyll i lastvikt och totalvikt för både BK1 och BK4 för att jämföra körningen.</p>
          <div className={styles.vehicles}>
            {draft.vehicles.map(vehicle => <fieldset key={vehicle.id} className={styles.card}>
              <legend>{vehicle.name}</legend>
              <div className={styles.pair}>
                {([['hourly', 'Timpris (kr/h)'], ['referenceLoad', 'Excel-last (ton)'], ['bk1Load', 'BK1 last (ton)'],
                  ['bk1Gross', 'BK1 totalvikt (ton)'], ['bk4Load', 'BK4 last (ton)'], ['bk4Gross', 'BK4 totalvikt (ton)']] as const).map(([key, label]) =>
                  <Field key={key} label={label} value={vehicle[key]} numeric
                    onChange={value => change({vehicles: replace<Vehicle>(draft.vehicles, vehicle.id, {[key]: value})})}/>)}
              </div>
            </fieldset>)}
          </div>
          <label className={styles.field}>Viktunderlag för offert<select value={draft.profile}
            onChange={event => change({profile: event.target.value as TonPriceDraft['profile']})}>
            {profiles.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
          </select></label>
        </section>
        <section className="panel">
          <h2>Material och mängder</h2>
          {draft.materials.map((material, index) => <MaterialEditor key={material.id} material={material} index={index} draft={draft}
            change={patch => change({materials: replace(draft.materials, material.id, patch)})}
            remove={draft.materials.length > 1 ? () => change({materials: draft.materials.filter(item => item.id !== material.id)}) : undefined}/>)}
          <button type="button" className="secondary" disabled={draft.materials.length >= 100} onClick={() => change({
            materials: [...draft.materials, newMaterial(crypto.randomUUID(), draft.rounds[0].id, 'trailer')],
          })}><Plus size={16}/> Lägg till rad</button>
        </section>
        <div className={styles.actions}>
          <button type="submit" className={styles.primary}><Calculator size={17}/>{busy ? 'Beräknar…' : 'Beräkna tonpris'}</button>
          {complete && <button type="button" className="secondary" onClick={() => window.print()}><Printer size={16}/> Skriv ut offert / spara PDF</button>}
        </div>
        {error && <p role="alert">{error}</p>}
      </fieldset>
    </form>
    {result && <section className={`panel ${styles.internal}`} aria-live="polite">
      <h2>Internt kalkylunderlag</h2>
      <div className={styles.metrics}>
        {[[format(result.totals.trips), 'Lass'], [format(result.totals.miles), 'Mil'], [format(result.totals.hours), 'Timmar'],
          [format(result.totals.freightAmount), 'Frakt (kr)'], [format(result.totals.materialEarnings), 'Materialförtjänst (kr)'],
          [format(result.totals.amount), 'Kalkylvärde med mängd (kr)']].map(([value, label]) =>
          <div key={label}><span>{label}</span><strong>{value}</strong></div>)}
      </div>
      <p>Lass, mil och timmar inkluderar sista dellasset. Beloppen räknas med kalkylens decimaler. Offerten visar pris per ton i hela kronor.</p>
      {!complete && <p role="status">Totalsumman omfattar färdiga rader med angiven mängd.</p>}
      {result.rounds.map(({id, result: time}, index) => <p key={id}>
        <strong>{draft.rounds[index].pickup || `Runda ${index + 1}`}</strong> · {format(time?.miles)} mil · {format(time?.drive)} min körning · {format(time?.minutes)} min per lass
      </p>)}
      {result.materials.map((row, index) => <details key={row.id} open>
        <summary>{draft.materials[index].transportOnly ? 'Enbart transport' : draft.materials[index].name || `Rad ${index + 1}`}</summary>
        {row.status && <p role="status">{row.status}</p>}
        {row.price && <p>Inköp {format(row.price.purchase)} kr/ton · Materialpris {format(row.price.sale)} kr/ton</p>}
        <div className={styles.table}><table><thead><tr><th>Ekipage</th><th>Viktunderlag</th><th>Last (ton)</th><th>Totalvikt (ton)</th><th>Frakt kr/ton</th><th>Levererat kr/ton</th></tr></thead>
          <tbody>{row.options.flatMap((option, i) => profiles.map(([profile, label]) => {
            const price = option.prices[profile];
            return <tr key={`${option.id}-${profile}`}><td>{draft.vehicles[i].name}</td><td>{label}</td>
              <td>{format(price?.load)}</td><td>{format(price?.gross)}</td><td>{format(price?.freight)}</td><td>{format(price?.delivered)}</td></tr>;
          }))}</tbody></table></div>
      </details>)}
    </section>}
    {complete && <section className={`panel ${styles.offer}`}>
      <h2>Offert · material och transport</h2>
      {draft.customer && <p>Kund {draft.customer}</p>}
      {draft.project && <p>Projekt {draft.project}</p>}
      {draft.validity && <p>Giltig till {draft.validity}</p>}
      <div className={styles.table}><table><thead><tr><th>Material</th><th>Leveransplats</th><th>Ekipage</th><th>Pris kr/ton</th></tr></thead>
        <tbody>{draft.materials.map((material, index) => <tr key={material.id}>
          <td>{material.transportOnly ? 'Enbart transport' : material.name}</td>
          <td>{draft.rounds.find(round => round.id === material.roundId)?.delivery || '–'}</td>
          <td>{draft.vehicles.find(vehicle => vehicle.id === material.vehicleId)?.name}</td>
          <td>{whole.format(result.materials[index].selected!.delivered)}</td>
        </tr>)}</tbody>
      </table></div>
      {draft.terms && <p>{draft.terms}</p>}
    </section>}
  </div>;
}
