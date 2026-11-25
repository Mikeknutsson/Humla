'use client';

import {useState} from 'react';
import {useRouter} from 'next/navigation';

export default function FortnoxSawSync({from,to}: {from: string; to: string}) {
  const [busy,setBusy] = useState(false);
  const [message,setMessage] = useState('');
  const [failed,setFailed] = useState(false);
  const router = useRouter();

  async function sync() {
    setBusy(true);
    setMessage('');
    setFailed(false);
    try {
      const response = await fetch('/api/integrationer/fortnox/sync/saw',{
        method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({from,to}),
      });
      const result = await response.json();
      if (!response.ok) throw Error(result.error || 'Fakturaraderna kunde inte hämtas.');
      setMessage('Fortnox-underlaget är uppdaterat.');
      router.refresh();
    } catch (error) {
      setFailed(true);
      setMessage(error instanceof Error ? error.message : 'Fakturaraderna kunde inte hämtas.');
    } finally {
      setBusy(false);
    }
  }
  return <div>
    <button type="button" className="secondary" disabled={busy} onClick={() => void sync()}>{busy ? 'Hämtar fakturarader…' : 'Hämta fakturarader från Fortnox'}</button>
    {message && <p role={failed ? 'alert' : 'status'}>{message}</p>}
  </div>;
}
