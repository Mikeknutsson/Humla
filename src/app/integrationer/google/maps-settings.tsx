'use client';

import {useState, type FormEvent} from 'react';
import {GoogleAddressField, googleRoadEstimate, googleRouteMatrix, validateGoogleAddress} from '@/app/_components/google-address-field';
import {useGoogleMapsKey} from '@/app/_components/google-maps-provider';
import {saveGoogleMapsKey, testGoogleRouteOptimization} from './actions';
import styles from './page.module.css';

export default function MapsSettings({canManage, optimizationConfigured}: {canManage: boolean; optimizationConfigured: boolean}) {
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

  async function runTest(test: () => Promise<string>, failure: string) {
    setBusy(true);
    setMessage('');
    try {setMessage(await test());}
    catch {setMessage(failure);}
    finally {setBusy(false);}
  }

  const origin = {address:'56.0528, 14.5819'};
  const destination = {address:'56.1714, 14.8624'};

  function testRoute(key: string) {
    return runTest(async () => {
      const estimate = await googleRoadEstimate(key,origin,point.address ? point : destination);
      const formatter = new Intl.NumberFormat('sv-SE',{maximumFractionDigits:2});
      return `Google Routes svarar. Testrutt: ${formatter.format(Number(estimate.miles))} mil, ${formatter.format(Number(estimate.driveMinutes))} minuter.`;
    }, 'Google kunde inte beräkna testrutten. Kontrollera nyckeln, faktureringen och att Routes API är aktiverat.');
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
      <div className={styles.actions}><button type="button" disabled={busy} onClick={() => void testRoute(browserKey)}>Testa ruttberäkning</button>
        <button type="button" disabled={busy} onClick={() => void runTest(async () => {
          const estimates = await googleRouteMatrix(browserKey,[origin,{address:'56.211, 15.278'}],destination);
          return `Route Matrix gav mil och körtid för ${estimates.filter(Boolean).length} av ${estimates.length} teststräckor.`;
        },'Route Matrix svarade inte. Kontrollera att Routes API är aktiverat och tillåtet för webbläsarnyckeln.')}>Testa Route Matrix</button>
        <button type="button" disabled={busy} onClick={() => void runTest(async () => {
          const result = await validateGoogleAddress(browserKey,'Vasagatan 1, 111 20 Stockholm');
          return result.formattedAddress
            ? `Address Validation svarar. ${result.confirmed ? 'Bekräftad testadress' : 'Testadress att granska'}: ${result.formattedAddress}.`
            : 'Address Validation svarade utan en formaterad testadress.';
        },'Address Validation svarade inte. Kontrollera att Address Validation API är aktiverat och tillåtet för webbläsarnyckeln.')}>Testa Address Validation</button>
      </div>
    </div>}
    <div className={styles.actions}>
      <button type="button" disabled={busy || !optimizationConfigured} onClick={() => void runTest(async () => {
        const result = await testGoogleRouteOptimization();
        return result.error ?? result.message ?? 'Route Optimization svarade utan resultat.';
      },'Route Optimization kunde inte testas.')}>Testa Route Optimization</button>
      {!optimizationConfigured && <p className="mutedcopy">Route Optimization väntar på ett tjänstkonto i Humlas serverinställningar.</p>}
    </div>
    {message && <p role="status">{message}</p>}
  </>;
}
