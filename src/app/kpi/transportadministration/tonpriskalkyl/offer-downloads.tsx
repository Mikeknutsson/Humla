'use client';

import {useState} from 'react';
import {Download} from 'lucide-react';
import styles from './workspace.module.css';

function download(content: string, filename: string) {
  const bytes = Uint8Array.from(atob(content), character => character.charCodeAt(0));
  const url = URL.createObjectURL(new Blob([bytes],{type:'application/pdf'}));
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  document.body.append(link);
  link.click();
  link.remove();
  window.setTimeout(() => URL.revokeObjectURL(url),30_000);
}

export default function OfferDownloads({date, disabled, create, onRetry}: {
  date: string; disabled: boolean;
  create: () => Promise<{pdf?: string; deliveryPlan?: string; error?: string}>;
  onRetry?: () => void;
}) {
  const [documents,setDocuments] = useState<{pdf: string; deliveryPlan: string}>();
  const [busy,setBusy] = useState(false);
  const [error,setError] = useState('');

  async function saveOffer() {
    if (documents) {
      download(documents.pdf,`Offert-material-${date}.pdf`);
      return;
    }
    setBusy(true);
    setError('');
    try {
      const response = await create();
      if (!response.pdf || !response.deliveryPlan) {
        setError(response.error ?? 'Offerten och leveransplanen kunde inte skapas.');
        return;
      }
      setDocuments({pdf:response.pdf,deliveryPlan:response.deliveryPlan});
      download(response.pdf,`Offert-material-${date}.pdf`);
    } catch {
      setError('Offerten och leveransplanen kunde inte skapas. Försök igen.');
    } finally {
      setBusy(false);
    }
  }

  return <>
    <div className={styles.actions}>
      <button type="button" className={styles.primary} disabled={disabled || busy} onClick={() => void saveOffer()}>
        <Download size={16}/>{busy ? 'Skapar offert och leveransplan…' : 'Ladda ner offert som PDF'}
      </button>
      {documents && <button type="button" className="secondary" disabled={disabled}
        onClick={() => download(documents.deliveryPlan,`Leveransplan-${date}.pdf`)}>
        <Download size={16}/> Ladda ner intern leveransplan
      </button>}
    </div>
    {error && <div className={styles.actions}><p role="alert">{error}</p>
      {onRetry && <button type="button" className="secondary" onClick={() => {setError('');onRetry();}}>Räkna om</button>}
    </div>}
  </>;
}
