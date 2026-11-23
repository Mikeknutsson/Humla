'use client';

import {useState, type FormEvent} from 'react';
import {GoogleAddressField, googleRoadEstimate} from '@/app/_components/google-address-field';
import {useGoogleMapsKey} from '@/app/_components/google-maps-provider';
import {saveGoogleMapsKey} from './actions';
import styles from './page.module.css';

export default function MapsSettings({canManage}: {canManage: boolean}) {
  const browserKey = useGoogleMapsKey();
  const [key, setKey] = useState('');
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');
  const [point, setPoint] = useState<{address: string; id?: string}>({address:''});

  async function save(value: string | null) {
    setBusy(true);
    setMessage('');
    try {
      const result = await saveGoogleMapsKey(value);
      setMessage(result.error ?? (value ? 'Webbläsarnyckeln är sparad. Testa kartan och rutten nedan.' : 'Google Maps är avstängt i Humla.'));
      if (result.saved) {
        setKey('');
        setPoint({address:''});
        window.location.reload();
      }
    } catch {setMessage('Maps-inställningen kunde inte sparas. Försök igen.');}
    finally {setBusy(false);}
  }

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    void save(key);
  }

  async function testRoute() {
    if (!browserKey) return;
    setBusy(true);
    setMessage('');
    try {
      const estimate = await googleRoadEstimate(browserKey, {address:'56.0528, 14.5819'},
        point.address ? point : {address:'56.1714, 14.8624'});
      const formatter = new Intl.NumberFormat('sv-SE', {maximumFractionDigits:2});
      setMessage(`Google Routes svarar. Testrutt: ${formatter.format(Number(estimate.miles))} mil, ${formatter.format(Number(estimate.driveMinutes))} minuter.`);
    } catch {
      setMessage('Google kunde inte beräkna testrutten. Kontrollera nyckeln, faktureringen och att Routes API är aktiverat.');
    } finally {setBusy(false);}
  }

  return <>
    {canManage && <form className={styles.form} onSubmit={submit}>
      <label>Webbläsarnyckel för Google Maps
        <input type="password" spellCheck={false} autoComplete="off" maxLength={94} required value={key}
          onChange={event => setKey(event.target.value)}/>
      </label>
      <div className={styles.actions}>
        <button type="submit" disabled={busy || !key.trim()}>{browserKey ? 'Byt nyckel' : 'Spara nyckel i Hub'}</button>
        {browserKey && <button type="button" className="secondary" disabled={busy} onClick={() => void save(null)}>Stäng av i Humla</button>}
      </div>
    </form>}
    {canManage && browserKey && <div className={styles.form}>
      <GoogleAddressField label="Testa adressökning och kartnål" value={point.address} placeId={point.id} className={styles.point}
        onChange={(address,id) => setPoint({address,id})}/>
      <div className={styles.actions}><button type="button" disabled={busy} onClick={() => void testRoute()}>Testa ruttberäkning</button></div>
    </div>}
    {message && <p role="status">{message}</p>}
  </>;
}
