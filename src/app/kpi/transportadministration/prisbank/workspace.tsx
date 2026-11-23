'use client';

import {useRouter} from 'next/navigation';
import {useState, type FormEvent} from 'react';
import {GoogleAddressField} from '@/app/_components/google-address-field';
import {effectiveSiteRates, type MaterialPriceBank, type MaterialSite} from '@/lib/hub/material-price-bank';
import {savePriceBankEntry} from './actions';
import styles from '../tonpriskalkyl/workspace.module.css';

const kinds = {quarry:'Täkt / utlastning', tip:'Tipp / mottagning', both:'Utlastning och mottagning'};
const emptySite = {id:'', name:'', kind:'quarry', address:'', locationNote:'', addressSource:'', mapPlaceId:''} satisfies MaterialSite;
const currency = new Intl.NumberFormat('sv-SE', {maximumFractionDigits:4});

export default function PriceBankWorkspace({bank, today, canManage}: {bank: MaterialPriceBank; today: string; canManage: boolean}) {
  const router = useRouter();
  const [selected, select] = useState(bank.sites[0]?.id ?? '');
  const [date, setDate] = useState(today);
  const [all, setAll] = useState(false);
  const [edit, setEdit] = useState<MaterialSite>();
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState(false);
  const site = bank.sites.find(item => item.id === selected) ?? bank.sites[0];
  const rates = bank.rates.filter(rate => rate.siteId === site?.id);
  const shown = all ? rates : effectiveSiteRates(rates, date);

  async function save(event: FormEvent<HTMLFormElement>, kind: 'site' | 'rate', data: Record<string,string>) {
    event.preventDefault();
    const form = event.currentTarget;
    setBusy(true);
    setMessage('');
    try {
      const result = await savePriceBankEntry(kind, data);
      setMessage(result.error ?? 'Sparat i prisbanken.');
      if (result.saved) {
        if (kind === 'site') {
          select(result.id ?? selected);
          setEdit(undefined);
        } else form.reset();
        router.refresh();
      }
    } catch { setMessage('Prisbanken kunde inte spara ändringen.'); }
    finally { setBusy(false); }
  }

  return <div className={`content ${styles.workspace}`}>
    <section className="panel">
      <h2>Täkter och tippar</h2>
      <div className={styles.actions}>
        <label className={styles.field}>Plats<select value={site?.id ?? ''} onChange={event => {select(event.target.value); setEdit(undefined);}}>
          {bank.sites.length === 0 && <option value="">Inga platser</option>}
          {bank.sites.map(item => <option key={item.id} value={item.id}>{item.name} · {kinds[item.kind]}</option>)}
        </select></label>
        {canManage && <><button type="button" className="secondary" onClick={() => setEdit(emptySite)}>Lägg till plats</button>
          {site && <button type="button" className="secondary" onClick={() => setEdit(site)}>Redigera plats</button>}</>}
      </div>
      {site && <p>{site.address || `Infartsadress saknas${site.locationNote ? ` · ${site.locationNote}` : ''}`}{site.addressSource &&
        <> · <a href={site.addressSource} target="_blank" rel="noreferrer">Adresskälla</a></>}</p>}
      {edit && <form onSubmit={event => void save(event, 'site', edit)} className={styles.card}>
        <div className={styles.grid}>
          <label className={styles.field}>Platsnamn<input required maxLength={120} value={edit.name}
            onChange={event => setEdit({...edit,name:event.target.value})}/></label>
          <label className={styles.field}>Typ<select value={edit.kind} onChange={event => setEdit({...edit,kind:event.target.value as MaterialSite['kind']})}>
            {Object.entries(kinds).map(([key, label]) => <option value={key} key={key}>{label}</option>)}
          </select></label>
          <GoogleAddressField label="Infartsadress" value={edit.address} className={styles.field}
            onChange={(address, mapPlaceId) => setEdit({...edit,address,mapPlaceId:mapPlaceId ?? ''})}/>
        </div>
        <div className={styles.actions}><button className={styles.primary} disabled={busy}>Spara plats</button>
          <button type="button" className="secondary" onClick={() => setEdit(undefined)}>Stäng</button></div>
      </form>}
    </section>
    {site && canManage && <section className="panel">
      <h2>Prislista för {site.name}</h2>
      <div className={styles.actions}>
        <label className={styles.field}>Prisdatum<input type="date" value={date} onChange={event => setDate(event.target.value || today)}/></label>
        <label><input type="checkbox" checked={all} onChange={event => setAll(event.target.checked)}/> Visa alla versioner</label>
      </div>
      <div className={styles.table}><table><thead><tr><th>Material</th><th>Typ</th><th>Pris</th><th>Gäller från</th><th>Gäller t.o.m.</th><th>Källa</th></tr></thead>
        <tbody>{shown.map(rate => <tr key={rate.id}><td>{rate.material}</td><td>{rate.kind === 'tip' ? 'Tippavgift' : 'Materialpris'}</td>
          <td>{currency.format(rate.price)} kr/{rate.unit}</td><td>{rate.validFrom ?? '–'}</td><td>{rate.validTo ?? '–'}</td><td>{rate.source}</td></tr>)}</tbody>
      </table></div>
      {!shown.length && <p>Inga prisrader för urvalet.</p>}
      <details className={styles.card}>
        <summary>Lägg till prisrad</summary>
        <form key={site.id} onSubmit={event => {
          const data = Object.fromEntries([...new FormData(event.currentTarget)].map(([key, value]) => [key, String(value).trim()]));
          data.price = data.price.replace(',', '.');
          void save(event, 'rate', {...data, siteId:site.id});
        }}>
          <div className={styles.grid}>
            <label className={styles.field}>Material<input name="material" required maxLength={160}/></label>
            <label className={styles.field}>Typ<select name="kind">{site.kind !== 'tip' && <option value="purchase">Nettoinköp</option>}
              {site.kind !== 'quarry' && <option value="tip">Tippavgift</option>}</select></label>
            <label className={styles.field}>Pris (kr)<input name="price" required inputMode="decimal" pattern="-?[0-9]+([,.][0-9]{1,4})?"/></label>
            <label className={styles.field}>Enhet<select name="unit">{['ton','m³','lass','st'].map(unit => <option key={unit}>{unit}</option>)}</select></label>
            <label className={styles.field}>Gäller från<input name="validFrom" type="date" required defaultValue={today}/></label>
            <label className={styles.field}>Gäller t.o.m.<input name="validTo" type="date"/></label>
            <label className={styles.field}>Källa / prislista<input name="source" required maxLength={240}/></label>
          </div>
          <button className={styles.primary} disabled={busy}>Spara prisrad</button>
        </form>
      </details>
    </section>}
    {message && <p role="status">{message}</p>}
  </div>;
}
