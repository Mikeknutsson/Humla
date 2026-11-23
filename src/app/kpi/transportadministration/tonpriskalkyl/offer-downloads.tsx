'use client';

import {useState} from 'react';
import {Download} from 'lucide-react';
import {offerPdfUrl} from './offer-pdf-url';
import styles from './workspace.module.css';

export default function OfferDownloads({disabled, create, onRetry}: {
  disabled: boolean;
  create: () => Promise<{id?: string; error?: string}>;
  onRetry?: () => void;
}) {
  const [id,setId] = useState<string>();
  const [busy,setBusy] = useState(false);
  const [error,setError] = useState('');

  async function saveOffer() {
    setBusy(true);
    setError('');
    try {
      const response = await create();
      if (!response.id) {
        setError(response.error ?? 'Offerten och leveransplanen kunde inte sparas.');
        return;
      }
      setId(response.id);
      const link = document.createElement('a');
      link.href = offerPdfUrl(response.id,'offert');
      link.download = '';
      document.body.append(link);
      link.click();
      link.remove();
    } catch {
      setError('Offerten och leveransplanen kunde inte sparas. Försök igen.');
    } finally {
      setBusy(false);
    }
  }

  return <>
    <div className={styles.actions}>
      {id ? <>
        <a href={offerPdfUrl(id,'offert')} download><Download size={16}/> Ladda ner offert som PDF</a>
        <a href={offerPdfUrl(id,'leveransplan')} download><Download size={16}/> Ladda ner intern leveransplan</a>
      </> : <button type="button" className={styles.primary} disabled={disabled || busy} onClick={() => void saveOffer()}>
        <Download size={16}/>{busy ? 'Sparar offert och leveransplan…' : 'Skapa och spara offert'}
      </button>}
    </div>
    {id && <p role="status">Offerten och leveransplanen är sparade i <a href="#offertarkiv">offertarkivet</a>.</p>}
    {error && <div className={styles.actions}><p role="alert">{error}</p>
      {onRetry && <button type="button" className="secondary" onClick={() => {setError('');onRetry();}}>Räkna om</button>}
    </div>}
  </>;
}
