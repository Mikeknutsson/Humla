'use client';

import {useState, useTransition} from 'react';
import {useRouter} from 'next/navigation';
import {changeArchivedOffer} from './actions';
import styles from './workspace.module.css';

type Action = Parameters<typeof changeArchivedOffer>[1];
const statuses = {created:'Skapad',sent:'Skickad',accepted:'Accepterad'};

export default function OfferArchiveControls({id,label,status,trash,back}: {
  id: string; label: string; status: keyof typeof statuses; trash: boolean; back?: string;
}) {
  const [confirming,setConfirming] = useState(false);
  const [error,setError] = useState('');
  const [pending,startTransition] = useTransition();
  const router = useRouter();

  function change(action: Action) {
    setError('');
    startTransition(async () => {
      try {
        const result = await changeArchivedOffer(id,action);
        if (result.error) setError(result.error);
        else if (back && action === 'trash') router.replace(back);
      } catch {
        setError('Offerten kunde inte uppdateras. Försök igen.');
      }
    });
  }

  return <div className={styles.deleteOffer}>
    {trash ? <button type="button" className="secondary" disabled={pending} onClick={() => change('restore')}>Återställ</button> : <>
      <div className={styles.actions}>
        <label className={styles.field}>Status
          <select aria-label={`Status för ${label}`} value={status} disabled={pending}
            onChange={event => change(event.target.value as keyof typeof statuses)}>
            {Object.entries(statuses).map(([value,name]) => <option key={value} value={value}>{name}</option>)}
          </select>
        </label>
        {!confirming && <button type="button" className="secondary" aria-label={`Flytta ${label} till papperskorgen`}
          disabled={pending} onClick={() => setConfirming(true)}>Radera</button>}
      </div>
      {confirming && <>
        <p>Flytta offerten och leveransplanen till papperskorgen?</p>
        <div className={styles.actions}>
          <button type="button" className="secondary" disabled={pending} onClick={() => change('trash')}>Flytta till papperskorgen</button>
          <button type="button" className="secondary" disabled={pending} onClick={() => {
            setConfirming(false);
            setError('');
          }}>Avbryt</button>
        </div>
      </>}
    </>}
    {pending && <p role="status">Sparar…</p>}
    {error && <p role="alert">{error}</p>}
  </div>;
}
