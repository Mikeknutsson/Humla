'use client';

import {useEffect, useEffectEvent, useRef, useState} from 'react';
import Link from 'next/link';
import {offerLines, offerMoney, parseOfferMarkup, type OfferDetails} from '@/lib/hub/ton-price-offer';
import {GoogleAddressField, googleRoadEstimate} from '@/app/_components/google-address-field';
import {useGoogleMapsKey} from '@/app/_components/google-maps-provider';
import {comparisonMaterial, type MaterialSite, type SiteRate} from '@/lib/hub/material-price-bank';
import type {QuarryComparison} from '@/lib/hub/quarry-comparison';
import {emptyReturnLoad, newRound, type Leg, type ReturnLoad, type TonPriceDraft} from '@/lib/hub/ton-price';
import MaterialMultiSelect from './material-multi-select';
import {calculateQuarryComparison, downloadQuarryOffer} from './actions';
import OfferDownloads from './offer-downloads';
import styles from './workspace.module.css';

type Option = QuarryComparison[number]['options'][number];
const testAddress = 'Exempelvägen 1, Ronneby (fiktiv testadress)';

function directionsUrl(site: MaterialSite, destination: {address: string; id?: string}) {
  const query = new URLSearchParams({api:'1', origin:site.address || site.name, destination:destination.address, travelmode:'driving'});
  if (site.mapPlaceId) query.set('origin_place_id',site.mapPlaceId);
  if (destination.id) query.set('destination_place_id',destination.id);
  return `https://www.google.com/maps/dir/?${query}`;
}

export function ReturnLoadFields({value, rates, onChange}: {
  value?: ReturnLoad; rates: SiteRate[]; onChange:(value?: ReturnLoad) => void;
}) {
  const names = [...new Set(rates.map(rate => rate.material))];
  return <div className={styles.card}>
    <label><input type="checkbox" checked={!!value} onChange={event => onChange(event.target.checked ? emptyReturnLoad : undefined)}/> Räkna med returlast</label>
    {value && <>
      <div className={styles.grid}>
        <label className={styles.field}>Returmaterial<select value={value.material} onChange={event => onChange({...value,material:event.target.value})}>
          <option value="">Välj material om känt</option>
          {value.material && !names.includes(value.material) && <option>{value.material}</option>}
          {names.map(name => <option key={name}>{name}</option>)}
        </select></label>
        <label className={styles.field}>Rundor med returlast<select value={value.share} onChange={event => onChange({...value,share:event.target.value})}>
          {['100','75','50','25','0'].map(share => <option key={share} value={share}>{share} %</option>)}
        </select></label>
        {([['tonnes','Ton per returlass'],['contribution','Nettointäkt kr/ton'],['extraMiles','Extra mil per returlass'],['extraMinutes','Extra minuter per returlass']] as const)
          .map(([key,label]) => <label key={key} className={styles.field}>{label}
            <input value={value[key]} inputMode="decimal" onChange={event => onChange({...value,[key]:event.target.value})}/>
          </label>)}
      </div>
      <small>Nettointäkt efter material- och tippavgifter. Extra körning, lastning och lossning läggs på rundan.</small>
    </>}
  </div>;
}

export default function QuarryComparisonWorkspace({sites, rates, draft, date, onApply, onDetailsChange}: {
  sites: MaterialSite[]; rates: SiteRate[]; draft: TonPriceDraft; date: string; onApply:(options: Option[]) => void; onDetailsChange:(patch: Partial<OfferDetails>) => void;
}) {
  const mapsKey = useGoogleMapsKey();
  const [destination,setDestination] = useState({address:'',id:undefined as string | undefined});
  const [committed,setCommitted] = useState('');
  const [selected,setSelected] = useState<string[]>([]);
  const [quantities,setQuantities] = useState<Record<string,string>>({});
  const [withoutReturn,setWithoutReturn] = useState<string[]>([]);
  const [returnLoad,setReturnLoad] = useState<ReturnLoad>();
  const [manual,setManual] = useState<Record<string,Leg>>({});
  const [request,setRequest] = useState<{key: string; comparison?: QuarryComparison; rounds?: ReturnType<typeof newRound>[]; error?: string}>();
  const [retry,setRetry] = useState(0);
  const [applied,setApplied] = useState('');
  const [markup,setMarkup] = useState('');
  const routes = useRef(new Map<string,Promise<Leg>>());
  const purchase = rates.filter(rate => rate.kind === 'purchase');
  const names = [...new Set(purchase.map(comparisonMaterial))].sort((a,b) => a.localeCompare(b,'sv',{numeric:true}));
  const candidates = sites.filter(site => purchase.some(rate => rate.siteId === site.id && selected.includes(comparisonMaterial(rate))));
  const materials = selected.map(name => ({name,tonnes:quantities[name] ?? ''}));
  const routesAvailable = candidates.some(site => manual[site.id]?.miles.trim() || (mapsKey && destination.address !== testAddress && (site.address || site.mapPlaceId)));
  const hasAddress = Boolean(destination.address.trim());
  const isTestAddress = destination.address === testAddress;
  const addressConfirmed = hasAddress && committed === destination.address;
  const ready = Boolean(addressConfirmed && materials.length && routesAvailable);
  const inputKey = JSON.stringify([date,destination,materials,manual,returnLoad,withoutReturn,draft.profile,draft.vehicles,
    candidates.map(site => [site.id,site.address,site.mapPlaceId]),retry,Boolean(mapsKey)]);
  const current = request?.key === inputKey && ready ? request : undefined;
  const result = current?.comparison;
  const busy = ready && !current;
  const winners = result?.flatMap(row => row.options[0] ? [row.options[0]] : []) ?? [];
  const missingRoutes = current?.rounds?.some(round => !round.outbound.miles.trim());
  const needsManual = isTestAddress || !mapsKey || !routesAvailable || missingRoutes;
  const percent = parseOfferMarkup(markup);
  const lines = result && percent !== null ? offerLines(result,percent) : [];
  const complete = lines.length === materials.length && lines.length > 0 &&
    lines.every(line => Number.isFinite(line.unitPrice) && line.unitPrice >= 0);

  function changeDestination(address: string, id?: string) {
    setDestination({address,id});
    setCommitted(id || /^-?\d+(?:\.\d+)?,\s*-?\d+(?:\.\d+)?$/.test(address) ? address : '');
    setManual({});
    routes.current.clear();
  }

  function toggle(name: string) {
    setSelected(items => items.includes(name) ? items.filter(item => item !== name) : [...items,name]);
  }

  const compare = useEffectEvent(async (key: string, signal: AbortSignal) => {
    try {
      const rounds = await Promise.all(candidates.map(async site => {
        let leg = manual[site.id];
        if (!leg?.miles && mapsKey && !isTestAddress && (site.address || site.mapPlaceId)) {
          const routeKey = JSON.stringify([mapsKey,site.address,site.mapPlaceId,destination]);
          let lookup = routes.current.get(routeKey);
          if (!lookup) {
            lookup = googleRoadEstimate(mapsKey,{address:site.address,id:site.mapPlaceId},destination)
              .then(estimate => ({miles:estimate.miles,driveMinutes:''}));
            routes.current.set(routeKey,lookup);
          }
          try {leg = await lookup;} catch {
            if (routes.current.get(routeKey) === lookup) routes.current.delete(routeKey);
          }
        }
        return {...newRound(crypto.randomUUID()), pickup:site.address,pickupSiteId:site.id,pickupPlaceId:site.mapPlaceId,
          delivery:destination.address,deliveryPlaceId:destination.id,returnLoad:withoutReturn.includes(site.id) ? undefined : returnLoad,outbound:leg ?? {miles:'',driveMinutes:''}};
      }));
      if (signal.aborted) return;
      const response = await calculateQuarryComparison(date,materials,rounds,draft);
      if (!signal.aborted) setRequest({key,rounds,comparison:response.comparison,error:response.error});
    } catch {
      if (!signal.aborted) setRequest({key,error:'Jämförelsen kunde inte beräknas. Försök igen.'});
    }
  });
  useEffect(() => {
    if (!ready) return;
    const controller = new AbortController();
    const timer = window.setTimeout(() => void compare(inputKey,controller.signal),300);
    return () => {window.clearTimeout(timer);controller.abort();};
  },[ready,inputKey]);

  return <section className={`panel ${styles.quickFlow}`}>
    <h2>Leverans och material</h2>
    <fieldset className={styles.form}>
      <div className={styles.grid}>
        <GoogleAddressField label="Projektets leveransadress" value={destination.address} placeId={destination.id} className={styles.field}
          placeholder="Gatuadress och ort" onChange={changeDestination} onCommit={setCommitted}/>
      </div>
      {!mapsKey && !hasAddress && <div className={styles.actions}>
        <button type="button" className="secondary" onClick={() => {
          changeDestination(testAddress);
          setCommitted(testAddress);
        }}>Använd testadress i Ronneby</button>
      </div>}
      <MaterialMultiSelect label="Material att jämföra" options={names.map(name => ({id:name,label:name}))}
        selected={new Set(selected)} onToggle={toggle}/>
      <details><summary>Mängder och returlast</summary>
      {selected.length > 0 && <details><summary>Ange mängder för projektet</summary>
        <p>Med mängd räknas hela rundor, även om sista lasset blir ett dellass.</p>
        <div className={styles.grid}>{selected.map(name => <label className={styles.field} key={name}>{name} (ton)
          <input inputMode="decimal" value={quantities[name] ?? ''} onChange={event => setQuantities({...quantities,[name]:event.target.value})}/>
        </label>)}</div>
      </details>}
      <ReturnLoadFields value={returnLoad} rates={rates} onChange={setReturnLoad}/>
      {returnLoad && candidates.length > 1 && <details><summary>Undantag för returlast</summary>
        {candidates.map(site => <label className={styles.field} key={site.id}>
          <span><input type="checkbox" checked={withoutReturn.includes(site.id)} onChange={event => {
            setWithoutReturn(event.target.checked ? [...withoutReturn,site.id] : withoutReturn.filter(id => id !== site.id));
          }}/> Ingen returlast från rundan via {site.name}</span>
        </label>)}
      </details>}
      </details>
      {hasAddress && candidates.length > 0 && <details open={needsManual || undefined}>
        <summary>{needsManual ? 'Ange körsträcka per täkt' : 'Justera körsträcka eller körtid'}</summary>
        {isTestAddress ? <p>För testadressen kan du ange ett exempelavstånd, till exempel 2,5 mil enkel väg.</p>
          : !mapsKey ? <p>Adress och material är valda. Automatisk körsträcka kräver en Google Maps-nyckel.
          {' '}<Link href="/integrationer/google">Öppna Google-inställningar</Link></p> :
          missingRoutes ? <p>Google kunde inte hämta alla rutter. Lägg till körsträckan för de täkter som saknas.</p> : null}
        <p>Ange mil enkel väg. Om körtiden lämnas tom räknar Humla med 11 min/mil.</p>
        {candidates.map(site => {
          const route = current?.rounds?.find(round => round.pickupSiteId === site.id)?.outbound;
          return <div className={`${styles.grid} ${styles.routeRow}`} key={site.id}>
            <div><strong>{site.name}</strong>
              {!isTestAddress && (site.address || site.mapPlaceId ? <a href={directionsUrl(site,destination)} target="_blank" rel="noreferrer">Visa vägen i Google Maps</a> :
                <small>Infartsadress saknas i Prisbanken.</small>)}
            </div>
            <label className={styles.field}>Enkel väg (mil)<input aria-label={`${site.name} · Enkel väg (mil)`}
              value={manual[site.id]?.miles ?? ''} placeholder={route?.miles || 't.ex. 2,5'} inputMode="decimal"
              onChange={event => setManual({...manual,[site.id]:{miles:event.target.value,driveMinutes:manual[site.id]?.driveMinutes ?? ''}})}/></label>
            <label className={styles.field}>Körtid (min, valfritt)<input aria-label={`${site.name} · Körtid (min)`}
              value={manual[site.id]?.driveMinutes ?? ''} placeholder={route?.driveMinutes || '11 min/mil'} inputMode="decimal"
              onChange={event => setManual({...manual,[site.id]:{miles:manual[site.id]?.miles || route?.miles || '',driveMinutes:event.target.value}})}/></label>
          </div>;
        })}
      </details>}
      {hasAddress && materials.length > 0 && routesAvailable && !addressConfirmed &&
        <button type="button" className={styles.primary} onClick={() => setCommitted(destination.address)}>Beräkna levererat pris</button>}
    </fieldset>
    <div className={styles.progress} role="status">
      {!hasAddress ? 'Ange leveransadress för projektet.' :
        !materials.length ? 'Välj material för att fortsätta.' :
        !candidates.length ? 'Prisbanken saknar en täkt för de valda materialen på prisdatumet.' :
        !routesAvailable ? 'Ange körsträcka för minst en täkt för att räkna fram priset.' :
        !addressConfirmed ? 'Bekräfta adressen med Enter eller Beräkna levererat pris.' :
        busy ? 'Jämför materialpris och frakt med bil + kärra…' : null}
    </div>
    {current?.error && <div className={styles.actions}><p role="alert">{current.error}</p>
      <button type="button" className="secondary" onClick={() => setRetry(value => value+1)}>Försök igen</button></div>}
    {result && <section className={styles.quickOffer} aria-label="Offertpris">
      <h3>Offertpris</h3>
      <label className={styles.field}>Påslag på material (%)
        <input inputMode="decimal" placeholder="Ange påslag" value={markup} onChange={event => setMarkup(event.target.value)}/>
      </label>
      {markup.trim() && percent === null && <p role="status">Ange ett påslag mellan 0 och 1 000 %.</p>}
      <div className={styles.table}><table>
        <thead><tr><th>Fraktion</th><th>Levererat pris (kr/ton)</th></tr></thead>
        <tbody>{result.map(row => {
          const line = lines.find(item => item.material === row.material);
          return <tr key={row.material}><td>{row.material}</td>
            <td>{line ? <strong>{offerMoney.format(line.unitPrice)}</strong> : row.options[0]
              ? <>{offerMoney.format(row.options[0].total)} <small>före påslag</small></> : 'Körunderlag saknas'}</td></tr>;
        })}</tbody>
      </table></div>
      {result.some(row => row.missing.length > 0) && <p role="status">Jämförelsen omfattar täkter med tillgängligt körunderlag. Se vilka som saknas nedan.</p>}
      <details>
        <summary>Kund, projekt och offertvillkor</summary>
        <fieldset className={styles.grid}>
          {([['customer','Kund'],['project','Projekt'],['validity','Giltig till'],['terms','Offertvillkor']] as const).map(([key,label]) =>
            <label key={key} className={styles.field}>{label}<input type={key === 'validity' ? 'date' : 'text'} maxLength={240}
              value={draft[key]} onChange={event => onDetailsChange({[key]:event.target.value})}/></label>)}
        </fieldset>
      </details>
      <OfferDownloads key={JSON.stringify([inputKey,markup,draft.customer,draft.project,draft.validity,draft.terms])}
        disabled={!complete || !current?.rounds} onRetry={() => setRetry(value => value+1)}
        create={() => downloadQuarryOffer(date,materials,current!.rounds!,draft,destination.address,markup,lines.map(line => line.unitPrice),
          {customer:draft.customer,project:draft.project,validity:draft.validity,terms:draft.terms})}/>
      {!complete && percent !== null && <p>Samtliga valda material behöver ett giltigt pris för att skapa offerten.</p>}
    </section>}
    {result && <details><summary>Visa täktjämförelse</summary>
    {result.map(row => <section className={styles.card} key={row.material}>
      <h3>{row.material}</h3>
      {row.options[0] ? <strong>{row.missing.length ? 'Billigast av beräknade täkter' : 'Billigast'} · {row.options[0].site.name} · {offerMoney.format(row.options[0].total)} kr/ton</strong>
        : <p>Inget komplett körunderlag för materialet.</p>}
      {row.missing.length > 0 && <p>Körunderlag saknas eller kan inte användas för {row.missing.join(', ')}.</p>}
      {row.options.length > 0 && <details>
        <summary>Visa jämförelse</summary>
        <div className={styles.table}><table><thead><tr><th>Täkt</th><th>Material i prislistan</th><th>Material kr/ton</th><th>Frakt kr/ton</th><th>Summa kr/ton</th><th>Priskälla</th></tr></thead>
          <tbody>{row.options.map(option => <tr key={option.rate.id}><td>{option.site.name}</td><td>{option.rate.material}</td>
            <td>{offerMoney.format(option.rate.price)}</td><td>{offerMoney.format(option.freight)}</td><td>{offerMoney.format(option.total)}</td><td>{option.rate.source}</td></tr>)}</tbody></table></div>
      </details>}
    </section>)}
    {winners.length > 0 && <button type="button" className={styles.primary} disabled={applied === inputKey}
      onClick={() => {onApply(winners);setApplied(inputKey);}}>{applied === inputKey ? 'Tillagt i kalkylen' : 'Använd billigaste täkter i kalkylen'}</button>}
    </details>}
  </section>;
}
