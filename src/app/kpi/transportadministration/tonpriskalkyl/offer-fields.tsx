'use client';

import {useEffect, useId, useRef, useState} from 'react';
import {offerTermsMaxLength} from '@/lib/hub/ton-price';
import {loadWorkifyCustomers} from './actions';
import styles from './workspace.module.css';

type FieldProps = {value: string; onChange: (value: string) => void};

export function CustomerField({value,onChange}: FieldProps) {
  const listId = useId();
  const inputId = useId();
  const pending = useRef(false);
  const [customers,setCustomers] = useState<string[]>();
  const [status,setStatus] = useState('');
  const [open,setOpen] = useState(false);
  const [highlighted,setHighlighted] = useState(-1);
  const query = value.trim().toLocaleLowerCase('sv');
  const matches = customers?.filter(name => name.toLocaleLowerCase('sv').includes(query)).slice(0,25) ?? [];
  const showOptions = open && matches.length > 0;
  const selectedId = showOptions && highlighted >= 0 ? `${listId}-${highlighted}` : undefined;
  useEffect(() => {
    if (selectedId) document.getElementById(selectedId)?.scrollIntoView({block:'nearest'});
  },[selectedId]);

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

  function choose(name: string) {
    onChange(name);
    setOpen(false);
    setHighlighted(-1);
  }

  return <div className={styles.field}>
    <label htmlFor={inputId}>Kund</label>
    <input id={inputId} role="combobox" aria-autocomplete="list" aria-expanded={showOptions}
      aria-controls={showOptions ? listId : undefined} aria-activedescendant={selectedId}
      value={value} maxLength={240} autoComplete="off" placeholder="Sök eller skriv kundnamn"
      onFocus={() => {setOpen(true); void loadSuggestions();}}
      onBlur={() => {setOpen(false);setHighlighted(-1);}}
      onChange={event => {onChange(event.target.value);setOpen(true);setHighlighted(-1);}}
      onKeyDown={event => {
        if (event.key === 'Escape' && open) {
          event.preventDefault();
          setOpen(false);
          setHighlighted(-1);
        } else if ((event.key === 'ArrowDown' || event.key === 'ArrowUp') && matches.length) {
          event.preventDefault();
          setOpen(true);
          const step = event.key === 'ArrowDown' ? 1 : -1;
          setHighlighted(index => index < 0 ? (step === 1 ? 0 : matches.length-1) :
            Math.max(0,Math.min(matches.length-1,index+step)));
        } else if (event.key === 'Enter' && selectedId && matches[highlighted]) {
          event.preventDefault();
          choose(matches[highlighted]);
        }
      }}/>
    {showOptions && <ul className={styles.customerOptions} id={listId} role="listbox" aria-label="Workify-kunder">
      {matches.map((name,index) => <li key={name} role="presentation">
        <button type="button" role="option" id={`${listId}-${index}`} aria-selected={index === highlighted}
          tabIndex={-1} onMouseDown={event => event.preventDefault()} onClick={() => choose(name)}>{name}</button>
      </li>)}
    </ul>}
    {open && (status || (customers && !matches.length)) &&
      <small role="status">{status || 'Inga matchande Workify-kunder. Du kan skriva in ett namn.'}</small>}
  </div>;
}

export function OfferTermsField({value,onChange}: FieldProps) {
  return <label className={`${styles.field} ${styles.offerTerms}`}>Offertvillkor
    <textarea rows={9} maxLength={offerTermsMaxLength} value={value} onChange={event => onChange(event.target.value)}/>
  </label>;
}
