'use client';

import {useEffect, useEffectEvent, useRef, useState} from 'react';
import Link from 'next/link';
import {offerMoney, priceQuarryOffer, type OfferDetails, type QuarryPricing, type WorkifyOfferPrice} from '@/lib/hub/ton-price-offer';
import {GoogleAddressField, googleReturnRouteMatrix, googleRoadEstimate, googleRouteMatrix, type Point} from '@/app/_components/google-address-field';
import {useGoogleMapsKey} from '@/app/_components/google-maps-provider';
import {compareMaterialFractions, materialGroups, standardMaterial, standardMaterialNames, type MaterialSite, type SiteRate} from '@/lib/hub/material-price-bank';
import type {QuarryComparison} from '@/lib/hub/quarry-comparison';
import {emptyReturnLoad, newRound, type Leg, type ReturnLoad, type TonPriceDraft} from '@/lib/hub/ton-price';
import MaterialMultiSelect from './material-multi-select';
import {calculateQuarryComparison, downloadQuarryOffer} from './actions';
import OfferDownloads from './offer-downloads';
import {CustomerField, OfferTermsField} from './offer-fields';
import styles from './workspace.module.css';

type Option = QuarryComparison[number]['options'][number];
type Direction = 'outbound' | 'inbound';
type Destination = {address: string; id?: string; point?: Point};
const emptyLeg: Leg = {miles:'',driveMinutes:''};
const directions = [['outbound','Till projektet'],['inbound','Tillbaka till täkten']] as const;
const testAddress = 'Exempelvägen 1, Ronneby (fiktiv testadress)';

function directionsUrl(site: MaterialSite, destination: Destination) {
  const endpoint = destination.point ? `${destination.point.lat},${destination.point.lng}` : destination.address;
  const query = new URLSearchParams({api:'1', origin:site.address || site.name, destination:endpoint, travelmode:'driving'});
  if (site.mapPlaceId) query.set('origin_place_id',site.mapPlaceId);
  if (destination.id) query.set('destination_place_id',destination.id);
  return `https://www.google.com/maps/dir/?${query}`;
}

export function ReturnLoadFields({value, rates, onChange}: {
  value?: ReturnLoad; rates: SiteRate[]; onChange:(value?: ReturnLoad) => void;
}) {
  const names = [...new Set(rates.map(rate => standardMaterial(rate).name))].sort(compareMaterialFractions);
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

export default function QuarryComparisonWorkspace({sites, rates, workifyPrices, draft, date, onApply, onDetailsChange}: {
  sites: MaterialSite[]; rates: SiteRate[]; draft: TonPriceDraft; date: string; onApply:(options: Option[]) => void; onDetailsChange:(patch: Partial<OfferDetails>) => void;
  workifyPrices: WorkifyOfferPrice[];
}) {
  const mapsKey = useGoogleMapsKey();
  const [destination,setDestination] = useState<Destination>({address:''});
  const [committed,setCommitted] = useState('');
  const [selected,setSelected] = useState<string[]>([]);
  const [quantities,setQuantities] = useState<Record<string,string>>({});
  const [withoutReturn,setWithoutReturn] = useState<string[]>([]);
  const [returnLoad,setReturnLoad] = useState<ReturnLoad>();
  const [manual,setManual] = useState<Record<string,Partial<Record<Direction,Leg>>>>({});
  const [request,setRequest] = useState<{key: string; comparison?: QuarryComparison; rounds?: ReturnType<typeof newRound>[]; error?: string}>();
  const [retry,setRetry] = useState(0);
  const [applied,setApplied] = useState('');
  const [pricing,setPricing] = useState<QuarryPricing>({mode:'markup',markup:'0',overrides:{}});
  const routes = useRef(new Map<string,Promise<Leg>>());
  const quarrySites = sites.filter(site => site.kind !== 'tip');
  const quarryIds = new Set(quarrySites.map(site => site.id));
  const purchase = rates.filter(rate => rate.kind === 'purchase' && rate.unit === 'ton' && quarryIds.has(rate.siteId))
    .map(rate => ({rate,...standardMaterial(rate)}));
  const materialOptions = new Map<string,{id: string; label: string; group: typeof materialGroups[number]; aliases: Set<string>}>();
  for (const name of standardMaterialNames) {
    materialOptions.set(name,{id:name,label:name === '0-125/150' ? 'Förstärkningslager 0-125/150' : name,
      group:'Standard',aliases:new Set()});
  }
  for (const {name,group,rate} of purchase) {
    const option = materialOptions.get(name) ?? {id:name,label:name,group,aliases:new Set<string>()};
    option.aliases.add(rate.material);
    materialOptions.set(name,option);
  }
  const options = [...materialOptions.values()].sort((a,b) => materialGroups.indexOf(a.group)-materialGroups.indexOf(b.group) ||
    (a.group === 'Standard' ? standardMaterialNames.indexOf(a.id)-standardMaterialNames.indexOf(b.id) :
      compareMaterialFractions(a.label,b.label))).map(option => ({
    id:option.id,label:option.label,group:option.group,search:[...option.aliases].join(' '),
    note:option.aliases.size ? undefined : 'Tonpris saknas',
    disabled:!option.aliases.size && !selected.includes(option.id),
  }));
  const candidates = quarrySites.filter(site => purchase.some(({rate,name}) => rate.siteId === site.id && selected.includes(name)));
  const materials = selected.map(name => ({name,tonnes:quantities[name] ?? ''}));
  const routesAvailable = candidates.some(site => manual[site.id]?.outbound?.miles.trim() || (mapsKey && destination.address !== testAddress && (site.address || site.mapPlaceId)));
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
  const missingRoutes = current?.rounds?.some(round => !round.outbound.miles.trim() || (!round.mirror && !round.inbound.miles.trim()));
  const needsManual = isTestAddress || !mapsKey || !routesAvailable || missingRoutes;
  const activePricing = {...pricing,overrides:Object.fromEntries(Object.entries(pricing.overrides)
    .filter(([name]) => selected.includes(name)))};
  const priced = result ? priceQuarryOffer(result,activePricing,workifyPrices) : [];
  const lines = priced.flatMap(row => row.line ? [row.line] : []);
  const complete = lines.length === materials.length && lines.length > 0 &&
    lines.every(line => Number.isFinite(line.unitPrice) && line.unitPrice >= 0);

  function changeRowPricing(material: string, patch: Partial<QuarryPricing['overrides'][string]>) {
    setPricing(previous => ({
      ...previous,
      overrides:{...previous.overrides,[material]:{...(previous.overrides[material] ?? {source:'',markup:''}),...patch}},
    }));
  }

  function changeDestination(address: string, id?: string, point?: Point) {
    setDestination({address,id,point});
    setCommitted(id || point || /^-?\d+(?:\.\d+)?,\s*-?\d+(?:\.\d+)?$/.test(address) ? address : '');
    setManual({});
    routes.current.clear();
  }

  function toggle(name: string) {
    setSelected(items => items.includes(name) ? items.filter(item => item !== name) : [...items,name]);
  }

  function updateManual(siteId: string, direction: Direction, patch: Partial<Leg>) {
    setManual(previous => ({...previous,[siteId]:{...previous[siteId],
      [direction]:{...(previous[siteId]?.[direction] ?? emptyLeg),...patch}}}));
  }

  const compare = useEffectEvent(async (key: string, signal: AbortSignal) => {
    try {
      const routeKey = (site: MaterialSite, direction: Direction) => JSON.stringify([mapsKey,direction,site.address,site.mapPlaceId,destination]);
      if (mapsKey && !isTestAddress) {
        for (const [direction] of directions) {
          const pending = new Map(candidates.filter(site => !manual[site.id]?.[direction]?.miles.trim() &&
            (site.address || site.mapPlaceId) && !routes.current.has(routeKey(site,direction)))
            .map(site => [routeKey(site,direction),{address:site.address,id:site.mapPlaceId}]));
          const entries = [...pending];
          // The project waypoint leaves room for 49 address- or Place-based quarry waypoints.
          for (let start = 0; start < entries.length; start += 49) {
            const batch = entries.slice(start,start+49);
            const quarries = batch.map(([, quarry]) => quarry);
            const matrix = direction === 'outbound' ? googleRouteMatrix(mapsKey,quarries,destination) :
              googleReturnRouteMatrix(mapsKey,destination,quarries);
            batch.forEach(([route, quarry], index) => {
              const fallback = () => direction === 'outbound' ? googleRoadEstimate(mapsKey,quarry,destination) :
                googleRoadEstimate(mapsKey,destination,quarry);
              routes.current.set(route,matrix.then(estimates => estimates[index] ?? fallback(),fallback));
            });
          }
        }
      }
      async function resolveLeg(site: MaterialSite, direction: Direction): Promise<Leg> {
        const override = manual[site.id]?.[direction];
        if (override?.miles.trim()) return override;
        const route = routeKey(site,direction);
        const lookup = routes.current.get(route);
        if (!lookup) return emptyLeg;
        try {
          const estimate = await lookup;
          return {...estimate,driveMinutes:override?.driveMinutes.trim() ? override.driveMinutes : estimate.driveMinutes};
        } catch {
          if (routes.current.get(route) === lookup) routes.current.delete(route);
          return emptyLeg;
        }
      }
      const rounds = await Promise.all(candidates.map(async site => {
        const [outbound,inbound] = await Promise.all([resolveLeg(site,'outbound'),resolveLeg(site,'inbound')]);
        const canRoute = mapsKey && !isTestAddress && (site.address || site.mapPlaceId);
        const mirror = !canRoute && !inbound.miles.trim();
        return {...newRound(crypto.randomUUID()), pickup:site.address,pickupSiteId:site.id,pickupPlaceId:site.mapPlaceId,
          delivery:destination.address,deliveryPlaceId:destination.id,deliveryPoint:destination.point,
          returnLoad:withoutReturn.includes(site.id) ? undefined : returnLoad,
          outbound,inbound,mirror};
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
        <GoogleAddressField label="Projektets leveransadress" value={destination.address} placeId={destination.id} point={destination.point} className={styles.field}
          placeholder="Gatuadress och ort" autocomplete onChange={changeDestination} onCommit={setCommitted}/>
      </div>
      {!mapsKey && !hasAddress && <div className={styles.actions}>
        <button type="button" className="secondary" onClick={() => {
          changeDestination(testAddress);
          setCommitted(testAddress);
        }}>Använd testadress i Ronneby</button>
      </div>}
      <MaterialMultiSelect label="Material att jämföra" options={options} groups={materialGroups.slice(0,-1)}
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
          missingRoutes ? <p>Google kunde inte hämta alla rutter. Ange körsträckan för den riktning som saknas.</p> : null}
        <p>Google uppskattar körsträcka och körtid för bil i båda riktningarna. Vid manuell sträcka utan körtid används 11 min/mil. För täkter utan kartuppgifter kan samma manuella sträcka användas åt båda håll.</p>
        {candidates.map(site => {
          const round = current?.rounds?.find(round => round.pickupSiteId === site.id);
          return <div className={styles.routeRow} key={site.id}>
            <div><strong>{site.name}</strong>
              {!isTestAddress && (site.address || site.mapPlaceId ? <a href={directionsUrl(site,destination)} target="_blank" rel="noreferrer">Visa vägen i Google Maps</a> :
                <small>Infartsadress saknas i Prisbanken.</small>)}
            </div>
            {directions.map(([direction,label]) => {
              const route = direction === 'inbound' && round?.mirror ? round.outbound : round?.[direction];
              const input = manual[site.id]?.[direction];
              return <fieldset className={styles.grid} key={direction}>
                <legend>{label}</legend>
                <label className={styles.field}>Körsträcka (mil)<input aria-label={`${site.name} · ${label} · Körsträcka (mil)`}
                  value={input?.miles ?? ''} placeholder={route?.miles || 't.ex. 2,5'} inputMode="decimal"
                  onChange={event => updateManual(site.id,direction,{miles:event.target.value})}/></label>
                <label className={styles.field}>Körtid (min, valfritt)<input aria-label={`${site.name} · ${label} · Körtid (min)`}
                  value={input?.driveMinutes ?? ''} placeholder={route?.driveMinutes || '11 min/mil'} inputMode="decimal"
                  onChange={event => updateManual(site.id,direction,{driveMinutes:event.target.value})}/></label>
              </fieldset>;
            })}
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
        !addressConfirmed ? 'Välj ett adressförslag, sätt en kartnål eller klicka på Beräkna levererat pris.' :
        busy ? 'Jämför materialpris och frakt med bil + kärra…' : null}
    </div>
    {current?.error && <div className={styles.actions}><p role="alert">{current.error}</p>
      <button type="button" className="secondary" onClick={() => setRetry(value => value+1)}>Försök igen</button></div>}
    {result && <section className={styles.quickOffer} aria-label="Offertpris">
      <h3>Offertpris</h3>
      <div className={styles.grid}>
        <label className={styles.field}>Prisgrund för offerten
          <select value={pricing.mode} onChange={event => setPricing({...pricing,mode:event.target.value as QuarryPricing['mode']})}>
            <option value="markup">Generellt materialpåslag</option>
            <option value="workify">Workify standardpris</option>
          </select>
        </label>
        <label className={styles.field}>Generellt påslag på material (%)
          <input inputMode="decimal" value={pricing.markup} onChange={event => setPricing({...pricing,markup:event.target.value})}/>
        </label>
      </div>
      <small>Påslag gäller materialet. Workify-priser inklusive transport används som levererat pris.</small>
      <div className={styles.table}><table>
        <thead><tr><th>Fraktion</th><th>Prisgrund per fraktion</th><th>Levererat pris (kr/ton)</th></tr></thead>
        <tbody>{result.map((row,index) => {
          const entry = priced[index];
          const override = pricing.overrides[row.material];
          const matches = workifyPrices.filter(rate => rate.material === row.material);
          return <tr key={row.material}><td>{row.material}</td>
            <td className={styles.field}>
              <select aria-label={`Prisgrund för ${row.material}`} value={override?.source ?? ''}
                onChange={event => changeRowPricing(row.material,{source:event.target.value})}>
                <option value="">{pricing.mode === 'workify' ? 'Workify standardpris' : 'Generellt påslag'}</option>
                <option value="markup">Eget påslag (%)</option>
                {matches.map(rate => <option key={rate.article} value={`workify:${rate.article}`}>
                  {rate.article} · {offerMoney.format(rate.price)} kr/ton · {rate.includesFreight ? 'inkl. transport' : 'material'}
                </option>)}
              </select>
              {override?.source === 'markup' && <input aria-label={`Påslag för ${row.material}`} inputMode="decimal"
                value={override.markup} placeholder={pricing.markup || 'Generellt påslag'}
                onChange={event => changeRowPricing(row.material,{markup:event.target.value})}/>}
            </td>
            <td>{entry.line ? <strong>{offerMoney.format(entry.line.unitPrice)}</strong> : entry.error}</td>
          </tr>;
        })}</tbody>
      </table></div>
      {result.some(row => row.missing.length > 0) && <p role="status">Jämförelsen omfattar täkter med tillgängligt körunderlag. Se vilka som saknas nedan.</p>}
      <details>
        <summary>Kund, projekt och offertvillkor</summary>
        <fieldset className={styles.grid}>
          <CustomerField value={draft.customer} onChange={customer => onDetailsChange({customer})}/>
          {([['project','Projekt'],['validity','Giltig till']] as const).map(([key,label]) =>
            <label key={key} className={styles.field}>{label}<input type={key === 'validity' ? 'date' : 'text'} maxLength={240}
              value={draft[key]} onChange={event => onDetailsChange({[key]:event.target.value})}/></label>)}
          <OfferTermsField value={draft.terms} onChange={terms => onDetailsChange({terms})}/>
        </fieldset>
      </details>
      <OfferDownloads key={JSON.stringify([inputKey,activePricing,draft.customer,draft.project,draft.validity,draft.terms])}
        disabled={!complete || !current?.rounds} onRetry={() => setRetry(value => value+1)}
        create={() => downloadQuarryOffer(date,materials,current!.rounds!,draft,destination.address,activePricing,lines.map(line => line.unitPrice),
          {customer:draft.customer,project:draft.project,validity:draft.validity,terms:draft.terms})}/>
      {!complete && <p>Samtliga valda material behöver ett giltigt pris för att skapa offerten.</p>}
    </section>}
    {result && <details><summary>Visa täktjämförelse</summary>
    <p>Tiden per runda inkluderar körning i båda riktningarna och 30 minuter för lastning och lossning.</p>
    {result.map(row => <section className={styles.card} key={row.material}>
      <h3>{row.material}</h3>
      {row.options[0] ? <strong>{row.missing.length ? 'Billigast av beräknade täkter' : 'Billigast'} · {row.options[0].site.name} · {offerMoney.format(row.options[0].total)} kr/ton</strong>
        : <p>Inget komplett körunderlag för materialet.</p>}
      {row.missing.length > 0 && <p>Körunderlag saknas eller kan inte användas för {row.missing.join(', ')}.</p>}
      {row.options.length > 0 && <details>
        <summary>Visa jämförelse</summary>
        <div className={styles.table}><table><thead><tr><th>Täkt</th><th>Material i prislistan</th><th>Material kr/ton</th><th>Mil till projekt</th><th>Mil tillbaka</th><th>Min per runda</th><th>Frakt kr/ton</th><th>Summa kr/ton</th><th>Priskälla</th></tr></thead>
          <tbody>{row.options.map(option => <tr key={option.rate.id}><td>{option.site.name}</td><td>{option.rate.material}</td>
            <td>{offerMoney.format(option.rate.price)}</td><td>{option.round.outbound.miles}</td>
            <td>{option.round.mirror ? option.round.outbound.miles : option.round.inbound.miles}</td>
            <td>{offerMoney.format(option.time.minutes)}</td><td>{offerMoney.format(option.freight)}</td>
            <td>{offerMoney.format(option.total)}</td><td>{option.rate.source}</td></tr>)}</tbody></table></div>
      </details>}
    </section>)}
    {winners.length > 0 && <button type="button" className={styles.primary} disabled={applied === inputKey}
      onClick={() => {onApply(winners);setApplied(inputKey);}}>{applied === inputKey ? 'Tillagt i kalkylen' : 'Använd billigaste täkter i kalkylen'}</button>}
    </details>}
  </section>;
}
