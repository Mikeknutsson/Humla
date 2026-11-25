'use client';

import {useId, useRef, useState} from 'react';
import {offerTermsMaxLength} from '@/lib/hub/ton-price';
import {loadWorkifyCustomers} from './actions';
import styles from './workspace.module.css';

type FieldProps = {value: string; onChange: (value: string) => void};

export function CustomerField({value,onChange}: FieldProps) {
  const listId = useId();
  const pending = useRef(false);
  const [customers,setCustomers] = useState<string[]>();
  const [status,setStatus] = useState('');

  async function loadSuggestions() {
    if (customers || pending.current) return;
    pending.current = true;
    setStatus('Hämtar Workify-kunder…');
    try {
      const names = await loadWorkifyCustomers();
      if (names === null) throw new Error('Kundlistan kunde inte hämtas.');
      setCustomers(names);
      setStatus(names.length === 0 ? 'Kundlistan är tom. Du kan skriva in ett namn.' : '');
    } catch {
      setStatus('Kundlistan kunde inte hämtas. Du kan skriva in ett namn.');
    } finally {
      pending.current = false;
    }
  }

  return <label className={styles.field}>Kund
    <input value={value} maxLength={240} list={listId} placeholder="Sök eller skriv kundnamn"
      onFocus={() => void loadSuggestions()} onChange={event => onChange(event.target.value)}/>
    <datalist id={listId}>{customers?.map(name => <option value={name} key={name}/>)}</datalist>
    {status && <small role="status">{status}</small>}
  </label>;
}

export function OfferTermsField({value,onChange}: FieldProps) {
  return <label className={`${styles.field} ${styles.offerTerms}`}>Offertvillkor
    <textarea rows={9} maxLength={offerTermsMaxLength} value={value} onChange={event => onChange(event.target.value)}/>
  </label>;
}
