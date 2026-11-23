'use client';

import Link from 'next/link';
import {useEffect, useRef, useState, type ReactNode} from 'react';
import {Calculator, ExternalLink, Plus, Trash2} from 'lucide-react';
import {initialTonPriceDraft, newMaterial, newRound, type calculateTonPrices, type Material, type Round, type TonPriceDraft, type Vehicle} from '@/lib/hub/ton-price';
import {GoogleAddressField, googleRoadEstimate} from '@/app/_components/google-address-field';
import {useGoogleMapsKey} from '@/app/_components/google-maps-provider';
import {materialPriceBankPath} from '@/app/_components/kpi-transport-administration-nav';
import {effectiveSiteRates, type MaterialPriceBank, type MaterialSite, type SiteRate} from '@/lib/hub/material-price-bank';
import type {QuarryComparison} from '@/lib/hub/quarry-comparison';
import QuarryComparisonWorkspace, {ReturnLoadFields} from './quarry-comparison';
import MaterialMultiSelect from './material-multi-select';
import {advancedOfferLines, offerMoney, truckSupplementArticles} from '@/lib/hub/ton-price-offer';
import {downloadAdvancedOffer, recalculateTonPrices} from './actions';
import OfferDownloads from './offer-downloads';
import styles from './workspace.module.css';

const decimals = new Intl.NumberFormat('sv-SE', {maximumFractionDigits: 2});
const format = (value: number | undefined | null) => value == null ? '–' : decimals.format(value);
const formatPrice = (value: number | undefined | null) => value == null ? '–' : offerMoney.format(value);
const profiles = [['reference', 'Excel-last'], ['bk1', 'BK1'], ['bk4', 'BK4']] as const;

function Field({label, value, onChange, numeric = false, placeholder, type = 'text'}: {
  label: string; value: string; onChange: (value: string) => void; numeric?: boolean; placeholder?: string; type?: string;
}) {
  return <label className={styles.field}>{label}
    <input type={type} value={value} maxLength={numeric ? 16 : 240} inputMode={numeric ? 'decimal' : undefined}
      onChange={event => onChange(event.target.value)} placeholder={placeholder}/>
  </label>;
}

function mapLink(origin: string, destination: string, originId?: string, destinationId?: string) {
  const query = new URLSearchParams({api: '1', origin, destination, travelmode: 'driving'});
  if (originId) query.set('origin_place_id', originId);
  if (destinationId) query.set('destination_place_id', destinationId);
  return `https://www.google.com/maps/dir/?${query}`;
}

function RoundEditor({round, index, sites, rates, checked, toggleRate, change, remove}: {
  round: Round; index: number; sites: MaterialSite[]; rates: SiteRate[]; checked: Set<string>;
  toggleRate: (rate: SiteRate) => void; change: (patch: Partial<Round>) => void; remove?: () => void;
}) {
  const field = (key: 'minutesPerMile' | 'loading' | 'unloading' | 'waiting', label: string) =>
    <Field key={key} label={label} value={round[key]} onChange={value => change({[key]: value})} numeric/>;
  const mapsKey = useGoogleMapsKey();
  const returnTo = round.returnTo.trim() || round.pickup.trim();
  const [fetching, setFetching] = useState(false);
  const [routeStatus, setRouteStatus] = useState('');
  async function estimateRoute() {
    if (!mapsKey) return;
    setFetching(true);
    setRouteStatus('');
    const pickup = {address:round.pickup,id:round.pickupPlaceId};
    const delivery = {address:round.delivery,id:round.deliveryPlaceId};
    try {
      const [outbound, inbound] = await Promise.all([googleRoadEstimate(mapsKey,pickup,delivery),
        round.mirror ? null : googleRoadEstimate(mapsKey,delivery,{address:returnTo,id:round.returnTo ? round.returnPlaceId : round.pickupPlaceId})]);
      change({outbound, ...(inbound ? {inbound} : {})});
      setRouteStatus('Google Maps bilrutt. Justera mil och körtid vid behov för lastbil.');
    } catch {
      setRouteStatus('Google Maps kunde inte hämta rutten. Fyll i mil och körtid manuellt.');
    } finally {setFetching(false);}
  }
  const resetDistance = {outbound:{miles:'',driveMinutes:''}, inbound:{miles:'',driveMinutes:''}};
  const selectSite = (role: 'pickup' | 'delivery', id: string) => {
    const site = sites.find(item => item.id === id);
    const address = site?.address || '';
    if (role === 'pickup') change({pickupSiteId:id,pickup:address,pickupPlaceId:site?.mapPlaceId,...resetDistance});
    else change({deliverySiteId:id,delivery:address,deliveryPlaceId:site?.mapPlaceId,...resetDistance});
  };
  return <fieldset className={styles.card} disabled={fetching}>
    <legend>Runda {index + 1}</legend>
    <div className={styles.grid}>
      <label className={styles.field}>Hämta från<select value={round.pickupSiteId ?? ''} onChange={event => selectSite('pickup',event.target.value)}>
        <option value="">Välj täkt eller egen plats</option>
        {sites.filter(site => site.kind !== 'tip').map(site => <option value={site.id} key={site.id}>{site.name}</option>)}
      </select></label>
      <label className={styles.field}>Lämna på<select value={round.deliverySiteId ?? ''} onChange={event => selectSite('delivery',event.target.value)}>
        <option value="">Projektadress / egen plats</option>
        {sites.filter(site => site.kind !== 'quarry').map(site => <option value={site.id} key={site.id}>{site.name}</option>)}
      </select></label>
    </div>
    <div className={styles.grid}>
      {round.pickup && round.pickupSiteId ? <p>{round.pickup}</p> :
        <GoogleAddressField label="Hämtningsadress" value={round.pickup} placeId={round.pickupPlaceId} className={styles.field}
          onChange={(pickup, pickupPlaceId) => change({pickup,pickupPlaceId,...resetDistance})}/>}
      {round.delivery && round.deliverySiteId ? <p>{round.delivery}</p> :
        <GoogleAddressField label="Leveransadress" value={round.delivery} placeId={round.deliveryPlaceId} className={styles.field}
          onChange={(delivery, deliveryPlaceId) => change({delivery,deliveryPlaceId,...resetDistance})}/>}
      <Field label="Körsträcka dit (mil)" value={round.outbound.miles} numeric
        onChange={miles => change({outbound:{...round.outbound,miles}})}/>
    </div>
    <div className={styles.actions}>
      {mapsKey && round.pickup.trim() && round.delivery.trim() && <button type="button" className="secondary"
        onClick={() => void estimateRoute()}>{fetching ? 'Hämtar rutt…' : 'Hämta mil och körtid från Google Maps'}</button>}
      {round.pickup.trim() && round.delivery.trim() && <a href={mapLink(round.pickup, round.delivery, round.pickupPlaceId, round.deliveryPlaceId)}
        target="_blank" rel="noreferrer"><ExternalLink size={14}/> Visa rutt i Google Maps</a>}
    </div>
    {routeStatus && <small role="status">{routeStatus}</small>}
    {(round.pickupSiteId || round.deliverySiteId) && (rates.length === 0 ? <p>Inga tonpriser för vald plats och datum.</p> :
      <MaterialMultiSelect label="Material och tippavgifter" selected={checked} options={rates.map(rate => ({
        id:rate.id, label:rate.material, note:`${rate.kind === 'tip' ? 'Tippavgift · ' : ''}${formatPrice(rate.price)} kr/ton`,
      }))} onToggle={id => {const rate = rates.find(item => item.id === id); if (rate) toggleRate(rate);}}/>)}
    <details>
      <summary>Ställ in körtid, retur och tid på plats</summary>
      <div className={styles.actions}>
        <label><input type="checkbox" checked={round.mirror} onChange={event => change({mirror:event.target.checked})}/> Samma sträcka och körtid på returen</label>
        {!round.mirror && round.delivery.trim() && returnTo && <a href={mapLink(round.delivery, returnTo, round.deliveryPlaceId, round.returnPlaceId || round.pickupPlaceId)}
          target="_blank" rel="noreferrer"><ExternalLink size={14}/> Karta retur</a>}
      </div>
      <div className={styles.grid}>
        <Field label="Körtid dit (min)" value={round.outbound.driveMinutes} numeric placeholder="Använd schablon"
          onChange={driveMinutes => change({outbound:{...round.outbound,driveMinutes}})}/>
        {!round.mirror && <>
          <GoogleAddressField label="Returadress (valfri)" value={round.returnTo} placeId={round.returnPlaceId} className={styles.field}
            onChange={(returnTo,returnPlaceId) => change({returnTo,returnPlaceId,inbound:resetDistance.inbound})}/>
          <Field label="Retur (mil)" value={round.inbound.miles} numeric onChange={miles => change({inbound:{...round.inbound,miles}})}/>
          <Field label="Körtid retur (min)" value={round.inbound.driveMinutes} numeric placeholder="Använd schablon"
            onChange={driveMinutes => change({inbound:{...round.inbound,driveMinutes}})}/>
        </>}
        {field('minutesPerMile', 'Schablon (min/mil)')}{field('loading', 'Lastning (min)')}
        {field('unloading', 'Lossning (min)')}{field('waiting', 'Väntetid (min)')}
      </div>
    </details>
    <details><summary>Returlast för rundan</summary>
      <ReturnLoadFields value={round.returnLoad} rates={rates} onChange={returnLoad => change({returnLoad})}/>
    </details>
    {remove && <button type="button" className="secondary" onClick={remove}><Trash2 size={15}/> Ta bort runda</button>}
  </fieldset>;
}

function MaterialEditor({material, index, draft, change, remove, expired}: {
  material: Material; index: number; draft: TonPriceDraft; change: (patch: Partial<Material>) => void; remove?: () => void; expired: boolean;
}) {
  const field = (key: 'name' | 'listPrice' | 'discount' | 'purchase' | 'markup' | 'sale' | 'tonnes', label: string, placeholder?: string) =>
    <Field key={key} label={label} value={material[key]} onChange={value => change({[key]: value})} numeric={key !== 'name'} placeholder={placeholder}/>;
  return <fieldset className={styles.card}>
    <legend>Rad {index + 1}</legend>
    <div className={styles.grid}>
      {material.transportOnly ? <strong>Enbart transport</strong> : material.bankRateId ? <strong>{material.name}</strong> : field('name', 'Material')}
      {!material.bankRateId && draft.rounds.length > 1 && <label className={styles.field}>Runda<select value={material.roundId} onChange={event => change({roundId: event.target.value})}>
        {draft.rounds.map((round, i) => <option key={round.id} value={round.id}>{round.pickup || `Runda ${i + 1}`}</option>)}
      </select></label>}
      <label className={styles.field}>Ekipage i offert<select value={material.vehicleId} onChange={event => change({vehicleId: event.target.value})}>
        {draft.vehicles.filter(vehicle => vehicle.id !== 'cassette' || draft.specialCassette || material.vehicleId === 'cassette').map(vehicle => <option key={vehicle.id} value={vehicle.id}>{vehicle.name}</option>)}
      </select></label>
      {field('tonnes', 'Mängd (ton)', 'Valfritt')}
    </div>
    {expired && <p role="status">Prisraden hör till en annan plats eller prisversion. Ta bort raden och välj materialet igen.</p>}
    {!material.transportOnly && <details><summary>Prisinställningar</summary><div className={styles.grid}>
      {!material.bankRateId && <>{field('listPrice', 'Listpris (kr/ton)')}{field('discount', 'Inköpsrabatt (%)')}
      {field('purchase', 'Inköpspris (kr/ton)', 'Beräknas från listpris')}</>}
      {material.bankRateId && <span>Prisbanken {formatPrice(Number(material.purchase))} kr/ton</span>}
      {field('markup', 'Materialpåslag (%)')}{field('sale', 'Eget säljpris (kr/ton)', 'Beräknas från inköp')}
    </div></details>}
    <div className={styles.actions}>
      {!material.bankRateId && <label><input type="checkbox" checked={material.transportOnly} onChange={event => change({transportOnly: event.target.checked})}/> Enbart transport</label>}
      {remove && <button type="button" className="secondary" onClick={remove}><Trash2 size={15}/> Ta bort rad</button>}
    </div>
  </fieldset>;
}

function replace<T extends {id: string}>(items: T[], id: string, patch: Partial<T>) {
  return items.map(item => item.id === id ? {...item, ...patch} : item);
}

export default function TonPriceWorkspace({draftKey, bank, today, children}: {draftKey: string; bank: MaterialPriceBank | null; today: string; children: ReactNode}) {
  const [draft, setDraft] = useState<TonPriceDraft>(() => ({...initialTonPriceDraft, priceDate:today, materials:[]}));
  const latestDraft = useRef(draft);
  const activeRates = effectiveSiteRates(bank?.rates ?? [], draft.priceDate || today).filter(rate => rate.unit === 'ton');
  const specialCassette = Boolean(draft.specialCassette || draft.materials.some(item => item.vehicleId === 'cassette'));
  const showBk4 = Boolean(draft.showBk4 || draft.profile === 'bk4');
  const visibleProfiles = showBk4 ? profiles : profiles.filter(([profile]) => profile !== 'bk4');
  const roundById = new Map(draft.rounds.map(round => [round.id,round]));
  const ratesById = new Map(activeRates.map(rate => [rate.id,rate]));
  const staleRate = (material: Material) => {
    if (!material.bankRateId) return false;
    const round = roundById.get(material.roundId);
    const rate = ratesById.get(material.bankRateId);
    return !rate || rate.siteId !== (rate.kind === 'tip' ? round?.deliverySiteId : round?.pickupSiteId);
  };
  const [result, setResult] = useState<ReturnType<typeof calculateTonPrices>>();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  useEffect(() => {
    const timer = window.setTimeout(() => {
      try {
        const saved = window.localStorage.getItem(draftKey);
        if (saved) {
          latestDraft.current = JSON.parse(saved);
          setDraft(latestDraft.current);
        }
      } catch {
        // A blocked browser store does not prevent calculating a price.
      }
    }, 0);
    return () => window.clearTimeout(timer);
  }, [draftKey]);

  function change(patch: Partial<TonPriceDraft>) {
    const updated = {...latestDraft.current, ...patch};
    applyDraft(updated);
  }

  function applyDraft(updated: TonPriceDraft) {
    latestDraft.current = updated;
    setDraft(updated);
    setResult(undefined);
    setError('');
    try {
      window.localStorage.setItem(draftKey, JSON.stringify(updated));
    } catch {
      setError('Webbläsaren kunde inte spara utkastet.');
    }
  }

  function toggleRate(round: Round, rate: SiteRate) {
    const exists = draft.materials.some(row => row.roundId === round.id && row.bankRateId === rate.id);
    change({materials: exists
      ? draft.materials.filter(row => row.roundId !== round.id || row.bankRateId !== rate.id)
      : [...draft.materials.filter(row => row.bankRateId || row.transportOnly || row.name || row.tonnes || row.purchase || row.listPrice || row.sale), {
        ...newMaterial(crypto.randomUUID(), round.id, 'trailer'),
        bankRateId:rate.id, bankSiteId:rate.siteId, bankKind:rate.kind, name:rate.material,
        purchase:String(rate.price), markup:rate.kind === 'tip' ? '0' : '10',
      }]});
  }

  function useCheapest(options: QuarryComparison[number]['options']) {
    const rounds = [...new Map(options.map(option => [option.site.id,option.round])).values()];
    const bySite = new Map(rounds.map(round => [round.pickupSiteId,round.id]));
    const referencedRounds = new Set(draft.materials.map(row => row.roundId));
    const previousRounds = draft.rounds.filter(round => referencedRounds.has(round.id) || round.pickup || round.delivery || round.outbound.miles);
    const materials = options.map(option => ({
      ...newMaterial(crypto.randomUUID(),bySite.get(option.site.id)!,'trailer'), bankRateId:option.rate.id,
      bankSiteId:option.site.id,bankKind:option.rate.kind,name:option.rate.material,purchase:String(option.rate.price),tonnes:option.tonnes,
    }));
    change({rounds:[...previousRounds,...rounds],materials:[...draft.materials,...materials]});
  }

  async function calculate() {
    setBusy(true);
    setError('');
    try {
      const response = await recalculateTonPrices(draft);
      if (latestDraft.current === draft) setResult(response.result);
      if (response.error) setError(response.error);
    } catch {
      setError('Kalkylen kunde inte beräknas. Försök igen.');
    } finally {
      setBusy(false);
    }
  }

  const complete = result && result.materials.length > 0 && result.materials.every(row => !row.status);
  const offer = complete ? advancedOfferLines(draft,result) : [];
  return <div className={`content ${styles.workspace}`}>
    <div className={styles.actions}><a href="#offertarkiv">Öppna offertarkivet</a></div>
    {bank && <QuarryComparisonWorkspace sites={bank.sites} rates={activeRates} draft={draft}
      date={draft.priceDate || today} onApply={useCheapest} onDetailsChange={change}/>}
    <details className={styles.advanced}>
      <summary>Avancerad kalkyl och inställningar</summary>
    <form className={styles.controls} onSubmit={event => {event.preventDefault(); void calculate();}}>
      <fieldset disabled={busy} className={styles.form}>
        <section className="panel">
          <h2>Kalkyl</h2>
          <div className={styles.grid}>
            <Field label="Kund" value={draft.customer} onChange={customer => change({customer})}/>
            <Field label="Projekt" value={draft.project} onChange={project => change({project})}/>
            <Field label="Prisdatum" type="date" value={draft.priceDate || today} onChange={priceDate => change({priceDate})}/>
          </div>
          <details>
            <summary>Offertvillkor</summary>
            <div className={styles.grid}>
              <Field label="Giltig till" type="date" value={draft.validity} onChange={validity => change({validity})}/>
              <Field label="Villkor" value={draft.terms} onChange={terms => change({terms})}/>
            </div>
          </details>
        </section>
        <section className="panel">
          <div className={styles.actions}><h2>Platser och material</h2><Link href={materialPriceBankPath}>Öppna prisbanken</Link></div>
          {!bank && <p role="status">Prisbanken kunde inte hämtas. Manuell kalkyl är tillgänglig.</p>}
          {draft.rounds.map((round, index) => <RoundEditor key={round.id} round={round} index={index}
            sites={bank?.sites ?? []}
            rates={activeRates.filter(rate => rate.kind === 'purchase' && rate.siteId === round.pickupSiteId ||
              rate.kind === 'tip' && rate.siteId === round.deliverySiteId)}
            checked={new Set(draft.materials.filter(row => row.roundId === round.id).map(row => row.bankRateId ?? ''))}
            toggleRate={rate => toggleRate(round, rate)}
            change={patch => change({rounds: replace(latestDraft.current.rounds, round.id, patch)})}
            remove={draft.rounds.length > 1 && !draft.materials.some(material => material.roundId === round.id)
              ? () => change({rounds: draft.rounds.filter(item => item.id !== round.id)}) : undefined}/>)}
          <button type="button" className="secondary" disabled={draft.rounds.length >= 30}
            onClick={() => change({rounds: [...draft.rounds, newRound(crypto.randomUUID())]})}><Plus size={16}/> Lägg till runda</button>
        </section>
        <section className="panel">
          <details><summary><strong>Ekipage och vikt</strong> · Bil + kärra som standard</summary>
          <label><input type="checkbox" checked={specialCassette} onChange={event => change({
            specialCassette:event.target.checked,
            materials:event.target.checked ? draft.materials : draft.materials.map(row => row.vehicleId === 'cassette' ? {...row,vehicleId:'trailer'} : row),
          })}/> Visa kassett för specialkörning</label>
          <label><input type="checkbox" checked={showBk4} onChange={event => change({
            showBk4:event.target.checked,profile:!event.target.checked && draft.profile === 'bk4' ? 'reference' : draft.profile,
          })}/> Visa BK4</label>
          <p>Excel-lasterna är referensvärden. Fyll i ekipagets lastvikt och totalvikt om du väljer ett alternativt viktunderlag.</p>
          <div className={styles.vehicles}>
            {draft.vehicles.filter(vehicle => vehicle.id !== 'cassette' || specialCassette).map(vehicle => <fieldset key={vehicle.id} className={styles.card}>
              <legend>{vehicle.name}</legend>
              <div className={styles.pair}>
                {([['hourly', 'Timpris (kr/h)'], ['referenceLoad', 'Excel-last (ton)'], ['bk1Load', 'BK1 last (ton)'],
                  ['bk1Gross', 'BK1 totalvikt (ton)'], ['bk4Load', 'BK4 last (ton)'], ['bk4Gross', 'BK4 totalvikt (ton)']] as const).filter(([key]) => showBk4 || !key.startsWith('bk4')).map(([key, label]) =>
                  <Field key={key} label={label} value={vehicle[key]} numeric
                    onChange={value => change({vehicles: replace<Vehicle>(draft.vehicles, vehicle.id, {[key]: value})})}/>)}
              </div>
            </fieldset>)}
          </div>
          <label className={styles.field}>Viktunderlag för offert<select value={draft.profile}
            onChange={event => change({profile: event.target.value as TonPriceDraft['profile']})}>
            {visibleProfiles.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
          </select></label></details>
        </section>
        <section className="panel">
          <h2>Valda material och mängder</h2>
          {draft.materials.map((material, index) => <MaterialEditor key={material.id} material={material} index={index} draft={{...draft,specialCassette}} expired={staleRate(material)}
            change={patch => change({materials: replace(draft.materials, material.id, patch)})}
            remove={() => change({materials: draft.materials.filter(item => item.id !== material.id)})}/>)}
          <button type="button" className="secondary" disabled={draft.materials.length >= 100} onClick={() => change({
            materials: [...draft.materials, newMaterial(crypto.randomUUID(), draft.rounds[0].id, 'trailer')],
          })}><Plus size={16}/> Lägg till manuell rad</button>
        </section>
        <div className={styles.actions}>
          <button type="submit" className={styles.primary} disabled={!draft.materials.length || draft.materials.some(staleRate)}><Calculator size={17}/>{busy ? 'Beräknar…' : 'Beräkna tonpris'}</button>

        </div>
        {complete && <OfferDownloads disabled={busy}
          create={() => downloadAdvancedOffer(draft,offer.map(line => line.unitPrice))} onRetry={() => void calculate()}/>}
        {error && <p role="alert">{error}</p>}
      </fieldset>
    </form>
    {result && <section className={`panel ${styles.internal}`} aria-live="polite">
      <h2>Internt kalkylunderlag</h2>
      <div className={styles.metrics}>
        {[[format(result.totals.trips), 'Lass'], [format(result.totals.miles), 'Mil'], [format(result.totals.hours), 'Timmar'],
          ...(result.totals.returnTonnes ? [[format(result.totals.returnTonnes), 'Returlast (ton)']] : []),
          [formatPrice(result.totals.freightAmount), 'Frakt (kr)'], [formatPrice(result.totals.materialEarnings), 'Materialförtjänst (kr)'],
          [formatPrice(result.totals.amount), 'Kalkylvärde med mängd (kr)']].map(([value, label]) =>
          <div key={label}><span>{label}</span><strong>{value}</strong></div>)}
      </div>
      <p>Lass, mil och timmar inkluderar sista dellasset. Beloppen räknas med kalkylens decimaler. Offerten visar pris per ton.</p>
      {!complete && <p role="status">Totalsumman omfattar färdiga rader med angiven mängd.</p>}
      {result.rounds.map(({id, result: time}, index) => <p key={id}>
        <strong>{draft.rounds[index].pickup || `Runda ${index + 1}`}</strong> · {format(time?.miles)} mil · {format(time?.minutes)} min per runda
        {time?.returnTonnes ? <> · {format(time.returnTonnes)} ton returlast i snitt · {formatPrice(time.returnCredit)} kr nettointäkt per runda</> : null}
      </p>)}
      {result.materials.map((row, index) => <details key={row.id} open>
        <summary>{draft.materials[index].transportOnly ? 'Enbart transport' : draft.materials[index].name || `Rad ${index + 1}`}</summary>
        {row.status && <p role="status">{row.status}</p>}
        {row.price && <p>Inköp {formatPrice(row.price.purchase)} kr/ton · Materialpris {formatPrice(row.price.sale)} kr/ton</p>}
        <div className={styles.table}><table><thead><tr><th>Ekipage</th><th>Viktunderlag</th><th>Last (ton)</th><th>Totalvikt (ton)</th><th>Frakt kr/ton</th><th>Levererat kr/ton</th></tr></thead>
          <tbody>{row.options.flatMap((option, i) => (option.id === 'cassette' && !specialCassette ? [] : visibleProfiles).map(([profile, label]) => {
            const price = option.prices[profile];
            return <tr key={`${option.id}-${profile}`}><td>{draft.vehicles[i].name}</td><td>{label}</td>
              <td>{format(price?.load)}</td><td>{format(price?.gross)}</td><td>{formatPrice(price?.freight)}</td><td>{formatPrice(price?.delivered)}</td></tr>;
          }))}</tbody></table></div>
      </details>)}
    </section>}
    </details>
    {complete && <section className={`panel ${styles.offer}`}>
      <h2>Offert · material och transport</h2>
      {draft.customer && <p>Kund {draft.customer}</p>}
      {draft.project && <p>Projekt {draft.project}</p>}
      {draft.validity && <p>Giltig till {draft.validity}</p>}
      <div className={styles.table}><table><thead><tr><th>Fraktion</th><th>Pris kr/ton</th></tr></thead>
        <tbody>{offer.map((line,index) => <tr key={draft.materials[index].id}>
          <td>{line.material}{line.quotedVehicle && <small> · {line.quotedVehicle}</small>}</td><td>{offerMoney.format(line.unitPrice)}</td>
        </tr>)}
        {truckSupplementArticles(offer).map(article => <tr key={article.key}>
          <td>Tillägg enkelbil{article.label && <small> · {article.label}</small>}</td>
          <td>{article.price === null ? 'Beräknas separat' : offerMoney.format(article.price)}</td>
        </tr>)}</tbody>
      </table></div>
      {draft.terms && <p>{draft.terms}</p>}
    </section>}
    {children}
  </div>;
}
