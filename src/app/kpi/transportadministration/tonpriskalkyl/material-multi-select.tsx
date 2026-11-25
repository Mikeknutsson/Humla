'use client';

import {Fragment, useId, useRef, useState} from 'react';
import {ChevronDown} from 'lucide-react';
import styles from './workspace.module.css';

type Option = {id: string; label: string; note?: string; group?: string; search?: string; disabled?: boolean};

function searchText(text: string) {
  return text.toLocaleLowerCase('sv-SE').replace(/\s*([–—−/-])\s*/g, '-').trim();
}

export default function MaterialMultiSelect({label, options, groups, selected, onToggle}: {
  label: string; options: Option[]; groups?: readonly string[]; selected: ReadonlySet<string>; onToggle: (id: string) => void;
}) {
  const [query, setQuery] = useState('');
  const search = useRef<HTMLInputElement>(null);
  const disclosure = useRef<HTMLDetailsElement>(null);
  const trigger = useRef<HTMLElement>(null);
  const nameId = useId();
  const labels = options.filter(option => selected.has(option.id)).map(option => option.label);
  const words = searchText(query).split(/\s+/).filter(Boolean);
  const visible = options.filter(option => {
    const value = searchText([option.label,option.note,option.group,option.search].join(' '));
    return words.every(word => value.includes(word));
  });
  const sections = groups ? groups.map(group => ({group,options:visible.filter(option => option.group === group)}))
    .filter(section => !words.length || section.options.length > 0 || words.every(word => searchText(section.group).includes(word))) :
    visible.length ? [{group:'',options:visible}] : [];

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
      <summary ref={trigger} aria-label={label + (labels.length ? ` · ${labels.length} valda` : '')}>
        <span>{labels.length ? `${labels.length} valda` : 'Välj material'}</span>
        <ChevronDown size={16} aria-hidden="true"/>
      </summary>
      <div className={styles.materialOptions} role="group" aria-labelledby={nameId}>
        <label className={styles.field}>Sök material<input ref={search} type="search" placeholder="Till exempel 0–32"
          value={query} onChange={event => setQuery(event.target.value)} onKeyDown={event => {
            if (event.key === 'Enter') event.preventDefault();
          }}/></label>
        <div className={styles.materialOptionList}>
          {sections.map(section => <Fragment key={section.group}>
            {section.group && <span className={styles.materialGroup}>{section.group}</span>}
            {section.options.map(option => <label key={option.id}>
              <input type="checkbox" checked={selected.has(option.id)} disabled={option.disabled} onChange={() => onToggle(option.id)}/>
              <span>{option.label}</span>{option.note && <small>{option.note}</small>}
            </label>)}
            {!section.options.length && <small>Inga material med aktivt tonpris.</small>}
          </Fragment>)}
          {!sections.length && <p>Inga material matchar sökningen.</p>}
        </div>
      </div>
    </details>
    {labels.length > 0 && <small>{labels.join(', ')}</small>}
  </div>;
}
