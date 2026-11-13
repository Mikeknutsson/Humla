'use client';

import { useEffect, useRef, useState } from 'react';
import type { Order, Resource } from '@/lib/orderportal/model';
import { fetchCatalog, type Catalog } from './pricing-panel';

type Section = 'customers' | 'articles' | 'resources';
const labels: Record<string, string> = {
 customer_number: 'Kundnummer', organization_number: 'Organisationsnummer', organisation_number: 'Organisationsnummer',
 vat_number: 'Momsregistreringsnummer', email: 'E-post', address: 'Adress', postal_code: 'Postnummer',
 city: 'Ort', peppol_id: 'Peppol-ID', project_number: 'Projektnummer', description: 'Beskrivning',
 article_number: 'Artikelnummer', unit: 'Enhet', unit_of_measure: 'Enhet', phone: 'Telefon',
 registration_number: 'Registreringsnummer', make: 'Märke', model: 'Modell', vehicle_type: 'Fordonstyp',
 cost_center: 'Kostnadsställe',
};
const groups: Record<Section, { label: string; kinds: string[] }[]> = {
 customers: [{label:'Kunder',kinds:['Customer']},{label:'Projekt',kinds:['Project']}],
 articles: [{label:'Artiklar',kinds:['Article']}],
 resources: [{label:'Personal',kinds:['Person']},{label:'Fordon och objekt',kinds:['Vehicle','vehicle']}],
};
const money = new Intl.NumberFormat('sv-SE',{style:'currency',currency:'SEK'});

export default function RegisterPanel({section,resources,orders,onOrder,onPrices}:{
 section:Section;resources:Resource[];orders:Order[];onOrder:(order:Order)=>void;onPrices:()=>void;
}){
 const [group,setGroup]=useState(0);
 const [query,setQuery]=useState('');
 const [limit,setLimit]=useState(40);
 const [selected,setSelected]=useState<Resource|null>(null);
 const [catalog,setCatalog]=useState<Catalog|null>(null);
 const [priceError,setPriceError]=useState(false);
 const detailRef=useRef<HTMLElement>(null);
 useEffect(()=>{
  if(selected&&window.matchMedia('(max-width:760px)').matches){
   detailRef.current?.scrollIntoView({block:'start'});
   detailRef.current?.focus({preventScroll:true});
  }
 },[selected]);

 const needsPrices=selected?.kind==='Article'||selected?.kind==='Customer'||selected?.kind==='Project';
 useEffect(()=>{
  if(!needsPrices||catalog||priceError)return;
  let active=true;
  fetchCatalog().then(result=>{if(active)setCatalog(result);}).catch(()=>{if(active)setPriceError(true);});
  return ()=>{active=false;};
 },[needsPrices,catalog,priceError]);

 const activeGroup=groups[section][group];
 const search=query.trim().toLocaleLowerCase('sv-SE');
 const entries=resources.filter(r=>activeGroup.kinds.includes(r.kind)&&
  [r.label,...Object.values(r.details||{})].some(value=>value.toLocaleLowerCase('sv-SE').includes(search)))
  .sort((a,b)=>a.label.localeCompare(b.label,'sv-SE',{numeric:true}));
 const relatedOrders=selected?orders.filter(o=>selected.kind==='Customer'?o.customerId===selected.id:
  selected.kind==='Project'?o.projectId===selected.id:selected.kind==='Person'?o.driverId===selected.id:
  selected.kind==='Article'?o.lines.some(line=>line.articleId===selected.id):o.vehicleId===selected.id)
  .sort((a,b)=>b.start.localeCompare(a.start)).slice(0,10):[];
 const matchingPrices=catalog?.prices.filter(price=>price.article_id===selected?.id&&!price.retired_at)||[];
 const matchingLists=catalog?.lists.filter(list=>list.target_id===selected?.id)||[];
 const fields=new Map(Object.entries(selected?.details||{}).map(([key,value])=>[labels[key],value]));

 return <section className="op-panel op-register">
  <div className="op-panelhead">
   <div><h2>{section==='resources'?'Mitt företag':activeGroup.label}</h2><p>Register från Humla Hub</p></div>
   {section==='articles'&&<button type="button" className="op-secondary" onClick={onPrices}>Prislistor</button>}
  </div>
  <div className="op-register-controls">
   {groups[section].length>1&&<div className="op-segment" aria-label="Register">
    {groups[section].map((g,i)=><button type="button" key={g.label} aria-pressed={group===i}
     onClick={()=>{setGroup(i);setSelected(null);setLimit(40);}}>{g.label}</button>)}
   </div>}
   <label>Sök i {activeGroup.label.toLocaleLowerCase('sv-SE')}
    <input type="search" value={query} onChange={e=>{setQuery(e.target.value);setLimit(40);}}/>
   </label>
  </div>
  <div className="op-register-body">
   <div>
    <p>{entries.length} poster</p>
    <ul className="op-register-list">
     {entries.slice(0,limit).map(r=><li key={r.id}><button type="button" aria-pressed={selected?.id===r.id}
      onClick={()=>setSelected(r)}>{r.label}
      {(r.details?.customer_number||r.details?.article_number||r.details?.vehicle_type)&&
       <small>{r.details.customer_number||r.details.article_number||r.details.vehicle_type}</small>}
     </button></li>)}
    </ul>
    {entries.length>limit&&<button type="button" className="op-secondary" onClick={()=>setLimit(n=>n+40)}>Visa fler</button>}
    {!entries.length&&<p>Inga poster matchar sökningen.</p>}
   </div>
   {selected&&<aside ref={detailRef} tabIndex={-1} className="op-register-detail" aria-label="Registerkort">
    <header><h3>{selected.label}</h3><button type="button" className="op-secondary" onClick={()=>setSelected(null)}>Stäng kort</button></header>
    {fields.size>0?<dl>{Array.from(fields,([label,value])=><div key={label}><dt>{label}</dt><dd>{value}</dd></div>)}</dl>:
     <p>Hubben har inga ytterligare uppgifter för den här posten.</p>}
    {needsPrices&&<section>
     <h4>Prislistor</h4>
     {priceError?<p role="alert">Prislistorna kunde inte hämtas.</p>:!catalog?<p>Hämtar prislistor…</p>:
      selected.kind==='Article'?matchingPrices.length?<ul>{matchingPrices.map(price=><li key={price.id}>
       {catalog.lists.find(list=>list.id===price.list_id)?.name||'Prislista'} · {money.format(price.sale_price)} / {price.unit}
       <small> Gäller {price.valid_from}{price.valid_to?' – '+price.valid_to:''}{price.pickup_id?' · Hämtplats: '+(catalog.sites.find(site=>site.id===price.pickup_id)?.label||'Ej angiven'):''}{price.delivery_id?' · Tippplats: '+(catalog.sites.find(site=>site.id===price.delivery_id)?.label||'Ej angiven'):''}</small>
      </li>)}</ul>:<p>Inga prisrader registrerade.</p>:
      matchingLists.length?<ul>{matchingLists.map(list=><li key={list.id}>{list.name}</li>)}</ul>:<p>Ingen särskild prislista kopplad.</p>}
     <button type="button" className="op-secondary" onClick={onPrices}>Öppna prislistor</button>
    </section>}
    <section><h4>Senaste kopplade order i portalen</h4>
     {relatedOrders.length?<ul className="op-register-list">{relatedOrders.map(o=><li key={o.id}>
      <button type="button" onClick={()=>onOrder(o)}>{o.number} · {o.title}<small>{o.start.slice(0,10)} · {o.status}</small></button>
     </li>)}</ul>:<p>Inga kopplade order i portalens underlag.</p>}
    </section>
   </aside>}
  </div>
 </section>;
}
