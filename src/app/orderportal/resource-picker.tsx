'use client';
import {useRef,useState} from 'react';
import type {Resource} from '@/lib/orderportal/model';

export default function ResourcePicker({label,value,items,onChange}:{label:string;value:string;items:Resource[];onChange:(item:Resource|null)=>void}) {
 const [query,setQuery]=useState('');const menu=useRef<HTMLDetailsElement>(null);
 const chosen=items.find(item=>item.id===value);
 const matches=items.filter(item=>item.label.toLocaleLowerCase('sv-SE').includes(query.toLocaleLowerCase('sv-SE')));
 const choose=(item:Resource|null)=>{onChange(item);setQuery('');if(menu.current){menu.current.open=false;menu.current.querySelector('summary')?.focus();}};
 return <div className="op-picker-field"><span>{label}</span><details className="op-picker" ref={menu} onKeyDown={event=>{if(event.key==='Escape'&&menu.current?.open){event.preventDefault();event.stopPropagation();menu.current.open=false;menu.current.querySelector('summary')?.focus();}}}><summary>{chosen?.label||(value?'Referens saknas i aktivt register':'Välj…')}</summary><div className="op-picker-menu"><label><span className="op-sr-only">Sök {label.toLocaleLowerCase('sv-SE')}</span><input type="search" value={query} onChange={event=>setQuery(event.target.value)} placeholder={'Sök '+label.toLocaleLowerCase('sv-SE')} onKeyDown={event=>{if(event.key==='Enter')event.preventDefault();}}/></label><div className="op-picker-options"><button type="button" onClick={()=>choose(null)}>— Ingen vald —</button>{matches.slice(0,80).map(item=><button type="button" key={item.id} aria-pressed={item.id===value} onClick={()=>choose(item)}>{item.label}</button>)}{!matches.length&&<p>Ingen träff i Humla Hub.</p>}{matches.length>80&&<p>{matches.length} träffar. Skriv mer för att avgränsa.</p>}</div></div></details></div>;
}
