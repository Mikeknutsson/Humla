'use client';

import {useEffect, useId, useRef, useState} from 'react';
import {ChevronDown} from 'lucide-react';
import styles from './workspace.module.css';

export type Choice = {value: string; label: string; id?: string; group?: string; keywords?: string};

function searchable(value: string) {
  return value.toLocaleLowerCase('sv').normalize('NFD').replace(/\p{M}/gu,'');
}

export function SearchField<T extends Choice>({label,value,choices,onSelect,onChange,placeholder,required,maxLength}: {
  label: string; value: string; choices: readonly T[]; onSelect: (choice: T) => void;
  onChange?: (value: string) => void; placeholder?: string; required?: boolean; maxLength?: number;
}) {
  const id = useId();
  const input = useRef<HTMLInputElement>(null);
  const list = useRef<HTMLDivElement>(null);
  const [open,setOpen] = useState(false);
  const [query,setQuery] = useState<string | null>(null);
  const [active,setActive] = useState(-1);
  const terms = searchable(query ?? '').trim().split(/\s+/).filter(Boolean);
  const matches = open ? choices.filter(choice => {
    const text = searchable([choice.value,choice.label,choice.keywords].join(' '));
    const compact = choice.value.toLowerCase().replace(/[^a-z0-9*]/g,'');
    return terms.every(term => text.includes(term) || compact.includes(term));
  }) : [];
  const groups = new Map<string,{choice:T; index:number}[]>();
  matches.forEach((choice,index) => {
    const group = choice.group ?? '';
    const items = groups.get(group) ?? [];
    items.push({choice,index});
    groups.set(group,items);
  });
  const selectedId = open && matches[active] ? `${id}-${active}` : undefined;
  const exactMatch = query ? matches.find(match =>
    searchable(match.value).replace(/\s+/g,'') === searchable(query.trim()).replace(/\s+/g,'')) : undefined;

  useEffect(() => {
    if (selectedId) document.getElementById(selectedId)?.scrollIntoView({block:'nearest'});
  },[selectedId]);

  function close() {
    setOpen(false);
    setQuery(null);
    setActive(-1);
  }

  function choose(choice: T) {
    onSelect(choice);
    input.current?.focus();
    close();
  }

  return <div className={styles.picker} onBlur={event => {
    if (event.currentTarget.contains(event.relatedTarget)) return;
    if (exactMatch && !onChange) onSelect(exactMatch);
    close();
  }}>
    <label htmlFor={id}>{label}</label>
    <div className={styles.searchControl}>
      <input ref={input} id={id} role="combobox" autoComplete="off" aria-autocomplete="list"
        aria-expanded={open} aria-controls={open ? `${id}-options` : undefined} aria-activedescendant={selectedId}
        placeholder={placeholder ?? `Sök ${label.toLocaleLowerCase('sv')}`} value={query ?? value}
        required={required} maxLength={onChange ? maxLength : undefined}
        onFocus={event => {setOpen(true);event.currentTarget.select();}}
        onClick={() => {if (!open) setOpen(true);}}
        onChange={event => {
          const search = event.target.value;
          onChange?.(search);
          setQuery(search);
          setOpen(true);
          setActive(-1);
          if (list.current) list.current.scrollTop = 0;
        }}
        onKeyDown={event => {
          if (event.key === 'Escape' && open) {
            event.preventDefault();
            close();
          } else if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
            event.preventDefault();
            const down = event.key === 'ArrowDown';
            if (!open) {
              setOpen(true);
              setActive(down ? 0 : choices.length - 1);
            } else {
              setActive(index => index < 0 ? (down ? 0 : matches.length-1) :
                Math.max(0,Math.min(matches.length-1,index+(down ? 1 : -1))));
            }
          } else if (event.key === 'Enter' && open) {
            const option = matches[active] ?? exactMatch ?? (query && matches.length === 1 ? matches[0] : undefined);
            event.preventDefault();
            if (option) choose(option);
            else close();
          }
        }}/>
      <button type="button" aria-label={`Visa alternativ för ${label.toLocaleLowerCase('sv')}`} tabIndex={-1}
        onMouseDown={event => event.preventDefault()} onClick={() => {
          if (open) close();
          else {input.current?.focus();setOpen(true);}
        }}><ChevronDown size={16}/></button>
    </div>
    {open && <div className={styles.searchOptions} id={`${id}-options`} ref={list} role="listbox" aria-label={label} tabIndex={-1}>
      {Array.from(groups,([group,items]) => <div key={group} role="group" aria-label={group || label}>
        {group && <div className={styles.optionGroup} aria-hidden="true">{group}</div>}
        {items.map(({choice,index}) => <button type="button" role="option" id={`${id}-${index}`}
          key={choice.id ?? choice.value} aria-selected={index === active} tabIndex={-1}
          onMouseDown={event => event.preventDefault()} onClick={() => choose(choice)}>{choice.label}</button>)}
      </div>)}
      {!matches.length && <p role="status">Inga träffar.</p>}
    </div>}
  </div>;
}
