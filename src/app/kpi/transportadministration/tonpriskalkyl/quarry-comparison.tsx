'use client';

import {useState} from 'react';
import {GoogleAddressField, googleRoadEstimate} from '@/app/_components/google-address-field';
import {useGoogleMapsKey} from '@/app/_components/google-maps-provider';
import {comparisonMaterial, type MaterialSite, type SiteRate} from '@/lib/hub/material-price-bank';
import type {QuarryComparison} from '@/lib/hub/quarry-comparison';
import {emptyReturnLoad, newRound, type Leg, type ReturnLoad, type TonPriceDraft} from '@/lib/hub/ton-price';
import MaterialMultiSelect from './material-multi-select';
import {calculateQuarryComparison} from './actions';
import styles from './workspace.module.css';

const kr = new Intl.NumberFormat('sv-SE',{minimumFractionDigits:2,maximumFractionDigits:2});
type Option = QuarryComparison[number]['options'][number];

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

export default function QuarryComparisonWorkspace({sites, rates, draft, date, onApply}: {
  sites: MaterialSite[]; rates: SiteRate[]; draft: TonPriceDraft; date: string; onApply:(options: Option[]) => void;
}) {
  const mapsKey = useGoogleMapsKey();
  const [destination,setDestination] = useState({address:'',id:undefined as string | undefined});
  const [selected,setSelected] = useState<string[]>([]);
  const [quantities,setQuantities] = useState<Record<string,string>>({});
  const [withoutReturn,setWithoutReturn] = useState<string[]>([]);
  const [returnLoad,setReturnLoad] = useState<ReturnLoad>();
  const [manual,setManual] = useState<Record<string,Leg>>({});
  const [result,setResult] = useState<QuarryComparison>();
  const [error,setError] = useState('');
  const [busy,setBusy] = useState(false);
  const [applied,setApplied] = useState(false);
  const purchase = rates.filter(rate => rate.kind === 'purchase');
  const names = [...new Set(purchase.map(comparisonMaterial))].sort((a,b) => a.localeCompare(b,'sv',{numeric:true}));
  const candidates = sites.filter(site => purchase.some(rate => rate.siteId === site.id && selected.includes(comparisonMaterial(rate))));
  const winners = result?.flatMap(row => row.options[0] ? [row.options[0]] : []) ?? [];

  function clearResult() {setResult(undefined);setApplied(false);setError('');}
  function toggle(name: string) {
    setSelected(selected.includes(name) ? selected.filter(item => item !== name) : [...selected,name]);
    clearResult();
  }

  async function compare() {
    setBusy(true);
    clearResult();
    try {
      const rounds = await Promise.all(candidates.map(async site => {
        let leg = manual[site.id];
        if (!leg?.miles && mapsKey && (site.address || site.mapPlaceId)) {
          try {
            const estimate = await googleRoadEstimate(mapsKey,{address:site.address,id:site.mapPlaceId},destination);
            leg = {miles:estimate.miles,driveMinutes:''};
          } catch { /* The result identifies sites without a usable route. */ }
        }
        return {...newRound(crypto.randomUUID()), pickup:site.address,pickupSiteId:site.id,pickupPlaceId:site.mapPlaceId,
          delivery:destination.address,deliveryPlaceId:destination.id,returnLoad:withoutReturn.includes(site.id) ? undefined : returnLoad,outbound:leg ?? {miles:'',driveMinutes:''}};
      }));
      const response = await calculateQuarryComparison(date,selected.map(name => ({name,tonnes:quantities[name] ?? ''})),rounds,draft);
      setResult(response.comparison);
      if (response.error) setError(response.error);
    } catch {setError('Jämförelsen kunde inte beräknas. Försök igen.');}
    finally {setBusy(false);}
  }

  return <section className="panel">
    <h2>Hitta billigaste täkt</h2>
    <fieldset disabled={busy} className={styles.form}>
      <div className={styles.grid}>
        <GoogleAddressField label="Projektets leveransadress" value={destination.address} placeId={destination.id} className={styles.field}
          onChange={(address,id) => {setDestination({address,id});setManual({});clearResult();}}/>
      </div>
      <MaterialMultiSelect label="Material att jämföra" options={names.map(name => ({id:name,label:name}))}
        selected={new Set(selected)} onToggle={toggle}/>
      {selected.length > 0 && <details><summary>Ange mängder för projektet</summary>
        <p>Med mängd räknas hela rundor, även om sista lasset blir ett dellass.</p>
        <div className={styles.grid}>{selected.map(name => <label className={styles.field} key={name}>{name} (ton)
          <input inputMode="decimal" value={quantities[name] ?? ''} onChange={event => {setQuantities({...quantities,[name]:event.target.value});clearResult();}}/>
        </label>)}</div>
      </details>}
      <ReturnLoadFields value={returnLoad} rates={rates} onChange={value => {setReturnLoad(value);clearResult();}}/>
      {returnLoad && candidates.length > 1 && <details><summary>Undantag för returlast</summary>
        {candidates.map(site => <label className={styles.field} key={site.id}>
          <span><input type="checkbox" checked={withoutReturn.includes(site.id)} onChange={event => {
            setWithoutReturn(event.target.checked ? [...withoutReturn,site.id] : withoutReturn.filter(id => id !== site.id));clearResult();
          }}/> Ingen returlast från rundan via {site.name}</span>
        </label>)}
      </details>}
      {candidates.length > 0 && <details open={!mapsKey || undefined}>
        <summary>Körsträcka och körtid per täkt</summary>
        <p>Humla använder 11 min/mil om du bara anger mil. Ange lastbilens körtid om den är känd.</p>
        {candidates.map(site => <div className={styles.grid} key={site.id}>
          <span>{site.name}{!site.address && !site.mapPlaceId && <small> · Infartsadress saknas</small>}</span>
          <label className={styles.field}>{site.name} · Enkel väg (mil)<input value={manual[site.id]?.miles ?? ''} inputMode="decimal"
            onChange={event => {setManual({...manual,[site.id]:{miles:event.target.value,driveMinutes:manual[site.id]?.driveMinutes ?? ''}});clearResult();}}/></label>
          <label className={styles.field}>{site.name} · Körtid (min)<input value={manual[site.id]?.driveMinutes ?? ''} inputMode="decimal"
            onChange={event => {setManual({...manual,[site.id]:{miles:manual[site.id]?.miles ?? '',driveMinutes:event.target.value}});clearResult();}}/></label>
        </div>)}
      </details>}
      <div className={styles.actions}>
        <button className={styles.primary} type="button" disabled={!destination.address.trim() || !selected.length || busy}
          onClick={() => void compare()}>{busy ? 'Jämför täkter…' : 'Jämför täkter'}</button>
        <span>Materialpris + frakt med bil + kärra</span>
      </div>
    </fieldset>
    {error && <p role="alert">{error}</p>}
    {result?.map(row => <section className={styles.card} key={row.material}>
      <h3>{row.material}</h3>
      {row.options[0] ? <strong>{row.missing.length ? 'Billigast av beräknade täkter' : 'Billigast'} · {row.options[0].site.name} · {kr.format(row.options[0].total)} kr/ton</strong>
        : <p>Inget komplett körunderlag för materialet.</p>}
      {row.missing.length > 0 && <p>Körunderlag saknas eller kan inte användas för {row.missing.join(', ')}.</p>}
      {row.options.length > 0 && <details>
        <summary>Visa jämförelse</summary>
        <div className={styles.table}><table><thead><tr><th>Täkt</th><th>Material i prislistan</th><th>Material kr/ton</th><th>Frakt kr/ton</th><th>Summa kr/ton</th><th>Priskälla</th></tr></thead>
          <tbody>{row.options.map(option => <tr key={option.rate.id}><td>{option.site.name}</td><td>{option.rate.material}</td>
            <td>{kr.format(option.rate.price)}</td><td>{kr.format(option.freight)}</td><td>{kr.format(option.total)}</td><td>{option.rate.source}</td></tr>)}</tbody></table></div>
      </details>}
    </section>)}
    {winners.length > 0 && <button type="button" className={styles.primary} disabled={applied}
      onClick={() => {onApply(winners);setApplied(true);}}>{applied ? 'Tillagt i kalkylen' : 'Använd billigaste täkter i kalkylen'}</button>}
  </section>;
}
