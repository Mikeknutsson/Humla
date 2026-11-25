'use client';

import {useState, useTransition} from 'react';
import {useRouter} from 'next/navigation';
import {deleteArchivedOffer} from './actions';
import styles from './workspace.module.css';

export default function DeleteOfferButton({id,label,page,opened}: {
  id: string; label: string; page: number; opened: boolean;
}) {
  const [confirming,setConfirming] = useState(false);
  const [error,setError] = useState('');
  const [pending,startTransition] = useTransition();
  const router = useRouter();

  return <div className={styles.deleteOffer}>
    {confirming ? <>
      <p>Radera {label} och den interna leveransplanen permanent?</p>
      <div className={styles.actions}>
        <button type="button" className="secondary" disabled={pending} onClick={() => {
          setError('');
          startTransition(async () => {
            try {
              const result = await deleteArchivedOffer(id);
              if (result.error) setError(result.error);
              else if (opened) router.replace(`?offertSida=${page}#offertarkiv`);
            } catch {
              setError('Offerten kunde inte raderas. Försök igen.');
            }
          });
        }}>{pending ? 'Raderar…' : 'Radera permanent'}</button>
        <button type="button" className="secondary" disabled={pending} onClick={() => {
          setConfirming(false);
          setError('');
        }}>Avbryt</button>
      </div>
    </> : <button type="button" className="secondary" aria-label={`Radera ${label}`} onClick={() => setConfirming(true)}>Radera</button>}
    {error && <p role="alert">{error}</p>}
  </div>;
}
