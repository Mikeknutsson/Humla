'use client';

import {useId, useRef, useState} from 'react';
import {ChevronDown} from 'lucide-react';
import styles from './workspace.module.css';

type Option = {id: string; label: string; note?: string};

function searchText(text: string) {
  return text.toLocaleLowerCase('sv-SE').replace(/[–—/]/g, '-').trim();
}

export default function MaterialMultiSelect({label, options, selected, onToggle}: {
  label: string; options: Option[]; selected: ReadonlySet<string>; onToggle: (id: string) => void;
}) {
  const [query, setQuery] = useState('');
  const search = useRef<HTMLInputElement>(null);
  const disclosure = useRef<HTMLDetailsElement>(null);
  const trigger = useRef<HTMLElement>(null);
  const nameId = useId();
  const labels = options.filter(option => selected.has(option.id)).map(option => option.label);
  const visible = options.filter(option => searchText(option.label + ' ' + (option.note ?? '')).includes(searchText(query)));

  return <div className={styles.materialPicker}>
    <span id={nameId}>{label}</span>
    <details ref={disclosure} onToggle={event => {
      if (event.currentTarget.open) search.current?.focus();
    }} onKeyDown={event => {
      if (event.key === 'Escape' && disclosure.current?.open) {
        disclosure.current.open = false;
        trigger.current?.focus();
      }
    }}>
      <summary ref={trigger}>
        <span>{labels.length ? `${labels.length} valda` : 'Välj material'}</span>
        <ChevronDown size={16} aria-hidden="true"/>
      </summary>
      <div className={styles.materialOptions} role="group" aria-labelledby={nameId}>
        <label className={styles.field}>Sök material<input ref={search} type="search" placeholder="Till exempel 0–32"
          value={query} onChange={event => setQuery(event.target.value)} onKeyDown={event => {
            if (event.key === 'Enter') event.preventDefault();
          }}/></label>
        <div className={styles.materialOptionList}>
          {visible.map(option => <label key={option.id}>
            <input type="checkbox" checked={selected.has(option.id)} onChange={() => onToggle(option.id)}/>
            <span>{option.label}</span>{option.note && <small>{option.note}</small>}
          </label>)}
          {!visible.length && <p>Inga material matchar sökningen.</p>}
        </div>
      </div>
    </details>
    {labels.length > 0 && <small>{labels.join(', ')}</small>}
  </div>;
}
