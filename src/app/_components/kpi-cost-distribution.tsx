'use client';

import {useEffect,useMemo,useRef,useState} from 'react';
import {useSearchParams} from 'next/navigation';
import {MatchEvidence,type Item} from './kpi-match-workbench';
import styles from './kpi-cost-distribution.module.css';

type Choice={id:string;name:string};
type CostItem=Item&{held?:boolean;current_units?:string[]};
type History={dimension:string;reference:string;target:string;valid_from:string;valid_to:string|null};
type Queue={items:CostItem[];units:Choice[];groups:{name:string}[];total_groups:number;history:History[]};
type Preview={saved:number;before:{cost:number;revenue:number};after:{cost:number;revenue:number};movements:{dimension:string;name:string;before_cost:number;after_cost:number}[]};
type Mode='selected'|'group'|'all'|'stop';
const money=new Intl.NumberFormat('sv-SE',{style:'currency',currency:'SEK',maximumFractionDigits:2});
const key=(item:Item)=>JSON.stringify([item.source,item.kind,item.reference_type,item.reference]);
const matches=(text:string,query:string)=>text.toLocaleLowerCase('sv').includes(query.trim().toLocaleLowerCase('sv'));

function SearchSelect({label,value,choices,onChange,disabled}:{label:string;value:string;choices:Choice[];onChange:(value:string)=>void;disabled:boolean}){
 const [open,setOpen]=useState(false),[search,setSearch]=useState('');
 const root=useRef<HTMLDivElement>(null),trigger=useRef<HTMLButtonElement>(null);
 useEffect(()=>{if(!open)return;const close=(event:PointerEvent)=>{if(!root.current?.contains(event.target as Node))setOpen(false)};document.addEventListener('pointerdown',close);return()=>document.removeEventListener('pointerdown',close)},[open]);
 const shown=choices.filter(choice=>matches(choice.name,search));
 return <div ref={root} className={styles.picker} onKeyDown={event=>{if(event.key==='Escape'){setOpen(false);trigger.current?.focus()}}}>
  <button ref={trigger} type="button" aria-label={label} aria-expanded={open&& !disabled} disabled={disabled} onClick={()=>{setOpen(!open);setSearch('')}}>{choices.find(choice=>choice.id===value)?.name||'Välj verksamhetsgrupp'} <span>▾</span></button>
  {open&&!disabled&&<div className={styles.options}><input type="search" autoFocus aria-label={`Sök ${label}`} placeholder="Sök grupp…" value={search} onChange={event=>setSearch(event.target.value)}/>{shown.map(choice=><button type="button" key={choice.id} aria-pressed={choice.id===value} onClick={()=>{onChange(choice.id);setOpen(false);trigger.current?.focus()}}>{choice.name}</button>)}{!shown.length&&<p>Ingen grupp matchar sökningen.</p>}</div>}
 </div>;
}

function Evidence({item,from,to}:{item:Item;from:string;to:string}){
 const [open,setOpen]=useState(false);
 return <details onToggle={event=>setOpen(event.currentTarget.open)}><summary>Visa underlag</summary>{open&&<MatchEvidence item={item} from={from} to={to}/>}</details>;
}

export function KpiCostDistribution({onDirtyChange}:{onDirtyChange?:(dirty:boolean)=>void}){
 const params=useSearchParams(),now=new Date();
 const year=Number(params.get('fiscal_year'))||(now.getMonth()<8?now.getFullYear()-1:now.getFullYear());
 const [from,setFrom]=useState(params.get('from')||`${year}-09-01`),[to,setTo]=useState(params.get('to')||`${year+1}-08-31`);
 const [request,setRequest]=useState(()=>new URLSearchParams({workspace:'1',dimension:'shared_cost',reference_type:'project',from,to,page:'0'}).toString());
 const [revision,setRevision]=useState(0),[data,setData]=useState<Queue|null>(null),[loading,setLoading]=useState(true),[error,setError]=useState(''),[message,setMessage]=useState('');
 const [search,setSearch]=useState(''),[selected,setSelected]=useState<Record<string,CostItem>>({}),[mode,setMode]=useState<Mode>('selected'),[group,setGroup]=useState(''),[unitSearch,setUnitSearch]=useState(''),[unitIds,setUnitIds]=useState<string[]>([]);
 const [validFrom,setValidFrom]=useState(from),[validTo,setValidTo]=useState(''),[reason,setReason]=useState('Jämn fördelning av gemensamma kostnader');
 const [busy,setBusy]=useState(false),[preview,setPreview]=useState<Preview|null>(null),[previewSignature,setPreviewSignature]=useState('');
 const submitting=useRef(false);
 const reportParams=new URLSearchParams(request),reportFrom=reportParams.get('from')!,reportTo=reportParams.get('to')!,page=Number(reportParams.get('page')||0);
 const costs=Object.values(selected),dirty=costs.length>0;
 useEffect(()=>{onDirtyChange?.(dirty||busy);const warn=(event:BeforeUnloadEvent)=>{event.preventDefault();event.returnValue=''};if(dirty)window.addEventListener('beforeunload',warn);return()=>window.removeEventListener('beforeunload',warn)},[dirty,busy,onDirtyChange]);
 useEffect(()=>{
  const controller=new AbortController();
  fetch('/api/kpi/matching?'+request,{cache:'no-store',signal:controller.signal}).then(async response=>{const result=await response.json();if(!response.ok)throw Error(result.error||'Kostnadsprojekten kunde inte hämtas');setData(result)}).catch(cause=>{if(cause.name!=='AbortError')setError(cause.message)}).finally(()=>{if(!controller.signal.aborted)setLoading(false)});
  return()=>controller.abort();
 },[request,revision]);
 const shown=useMemo(()=>data?.items.filter(item=>item.source==='NEXT'&&item.kind==='cost'&&item.reference_type==='project'&&matches([item.reference,item.project_name,item.description,...item.vehicles??[],...item.accounts??[],...item.suppliers??[]].join(' '),search))??[],[data,search]);
 const shownUnits=data?.units.filter(unit=>matches(unit.name,unitSearch))??[];
 const target=mode==='all'?'*':mode==='group'?group:mode==='stop'?'none':JSON.stringify(unitIds);
 const destination=mode==='all'?'Alla giltiga kostnadsbärare':mode==='group'?`Giltiga enheter i ${group||'vald grupp'}`:mode==='stop'?'Avsluta fördelningen':`${unitIds.length} valda kostnadsbärare`;
 const payload={changes:costs.map(item=>({item:{source:item.source,kind:item.kind,reference_type:item.reference_type,reference:item.reference},targets:{shared_cost:target},valid_from:validFrom,valid_to:validTo||null})),from:reportFrom,to:reportTo,reason};
 const signature=JSON.stringify(payload),canReview=costs.length>0&&costs.length<=100&&!!validFrom&&(!validTo||validTo>=validFrom)&&reason.trim().length>=3&&(mode!=='selected'||unitIds.length>0&&unitIds.length<=100)&&(mode!=='group'||!!group);
 const currentPreview=previewSignature===signature?preview:null;
 function toggle(item:CostItem){setSelected(previous=>{const next={...previous};if(next[key(item)])delete next[key(item)];else if(Object.keys(next).length<100)next[key(item)]=item;return next});setPreview(null)}
 function load(nextPage=0,newPeriod=false){
  if(busy||newPeriod&&dirty)return;
  setLoading(true);setError('');setPreview(null);
  setRequest(new URLSearchParams({workspace:'1',dimension:'shared_cost',reference_type:'project',from:newPeriod?from:reportFrom,to:newPeriod?to:reportTo,search,page:String(nextPage)}).toString());setRevision(value=>value+1);
  if(newPeriod)setValidFrom(from);
 }
 async function submit(isPreview:boolean){
  if(submitting.current||!canReview||loading||(!isPreview&&!currentPreview))return;
  submitting.current=true;setBusy(true);setError('');setMessage('');
  try{
   const response=await fetch('/api/kpi/matching',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({...payload,preview:isPreview}),signal:AbortSignal.timeout(110000)}),result=await response.json();
   if(!response.ok)throw Error(result.error||'Fördelningen kunde inte behandlas');
   if(isPreview){setPreview(result);setPreviewSignature(signature)}
   else{setSelected({});setPreview(null);setLoading(true);setRevision(value=>value+1);setMessage(`${costs.length} kostnadsprojekt sparade i Humla Hub. Rapporten får fördelningen vid nästa synkning.`)}
  }catch(cause){setPreview(null);setError(cause instanceof Error?cause.message:'Fördelningen kunde inte behandlas')}
  finally{submitting.current=false;setBusy(false)}
 }
 const disabled=busy||loading;
 return <section className={styles.workspace} aria-label="Enkel kostnadsfördelning">
  <p>Välj kostnadsprojekten och vilka enheter som ska bära dem. Kostnaden delas lika mellan giltiga mottagare på transaktionens datum.</p>
  <details className={styles.period}><summary>Rapportperiod · {reportFrom} – {reportTo}</summary><form onSubmit={event=>{event.preventDefault();load(0,true)}}><label>Rapport från<input type="date" required value={from} disabled={disabled||dirty} onChange={event=>setFrom(event.target.value)}/></label><label>Rapport till<input type="date" required min={from} value={to} disabled={disabled||dirty} onChange={event=>setTo(event.target.value)}/></label><button type="submit" disabled={disabled||dirty}>Hämta perioden</button>{dirty&&<small>Rensa valda kostnader innan du byter rapportperiod.</small>}</form></details>
  {error&&<p role="alert" className={styles.error}>{error}</p>}{message&&<p role="status" className={styles.notice}>{message}</p>}
  <div className={styles.columns}>
   <section className={styles.card}><h3>1. Välj kostnader</h3><p>Sök projektnummer, namn, regnummer, konto eller leverantör.</p>
    <form className={styles.search} onSubmit={event=>{event.preventDefault();load()}}><label>Sök kostnadsprojekt<input type="search" value={search} disabled={busy} onChange={event=>setSearch(event.target.value)} placeholder="T.ex. släp, vattentunna eller projektnummer"/></label><button type="submit" className="secondary" disabled={disabled}>Sök i hela perioden</button></form>
    {reportParams.get('search')&&<small>Hämtat urval: {reportParams.get('search')}. Sök i hela perioden igen för att ändra urvalet.</small>}
    <details open className={styles.listPicker}><summary>Kostnadsprojekt · {costs.length} valda</summary><div className={styles.actions}><button type="button" disabled={disabled||!shown.length} onClick={()=>{setPreview(null);setSelected(previous=>{const next={...previous};for(const item of shown){if(Object.keys(next).length>=100)break;next[key(item)]=item}return next})}}>Markera visade</button><button type="button" disabled={busy||!dirty} onClick={()=>{setSelected({});setPreview(null)}}>Rensa val</button></div>
     {loading?<p role="status">Hämtar kostnadsprojekt…</p>:<div className={styles.list}>{shown.map(item=><article key={key(item)} className={selected[key(item)]?styles.selected:''}><label className={styles.check}><input type="checkbox" checked={!!selected[key(item)]} disabled={busy||!selected[key(item)]&&costs.length>=100} onChange={()=>toggle(item)}/><span><strong>{item.reference} {item.project_name&&`· ${item.project_name}`}</strong><small>{item.description||item.vehicles?.join(', ')||'NEXT-kostnadsprojekt'}</small><small>{money.format(item.amount)} · {item.rows} transaktioner{item.held?' · behöver granskas':''}</small></span></label><Evidence item={item} from={reportFrom} to={reportTo}/></article>)}{!shown.length&&<p>Inga projekt i den hämtade listan matchar. Använd ”Sök i hela perioden” för att söka fler.</p>}</div>}
     <div className={styles.actions}><button type="button" disabled={disabled||page===0} onClick={()=>load(page-1)}>Föregående</button><span>Sida {page+1} · {data?.total_groups??0} referenser</span><button type="button" disabled={disabled||!data||(page+1)*100>=data.total_groups} onClick={()=>load(page+1)}>Nästa</button></div>
    </details>
    {dirty&&<div className={styles.chips} aria-label="Valda kostnadsprojekt">{costs.map(item=><button type="button" disabled={busy} key={key(item)} onClick={()=>toggle(item)} aria-label={`Ta bort kostnadsprojekt ${item.reference}`}>{item.reference} ×</button>)}</div>}
    <small>Valen finns kvar när du söker eller byter sida. Högst 100 projekt kan sparas samtidigt.</small>
   </section>
   <section className={styles.card}><h3>2. Välj mottagare</h3><fieldset disabled={disabled} className={styles.modes}><legend>Fördela till</legend>{([['selected','Valda enheter'],['group','En verksamhetsgrupp'],['all','Alla kostnadsbärare'],['stop','Avsluta befintlig fördelning']] as [Mode,string][]).map(([value,label])=><label className={styles.check} key={value}><input type="radio" name="distribution-mode" value={value} checked={mode===value} onChange={()=>{setMode(value);setPreview(null)}}/>{label}</label>)}</fieldset>
    {mode==='group'&&<><SearchSelect label="Välj verksamhetsgrupp" value={group} choices={data?.groups.map(value=>({id:value.name,name:value.name}))??[]} disabled={disabled} onChange={value=>{setGroup(value);setPreview(null)}}/><p>Gruppens daterade kopplingar styr vilka enheter som får kostnaden.</p></>}
    {mode==='selected'&&<details open className={styles.listPicker}><summary>Kostnadsbärare · {unitIds.length} valda</summary><small>Välj upp till 100 enheter eller använd en verksamhetsgrupp.</small><label>Sök kostnadsbärare<input type="search" value={unitSearch} disabled={busy} onChange={event=>setUnitSearch(event.target.value)} placeholder="Namn eller regnummer…"/></label><div className={styles.actions}><button type="button" disabled={disabled||!shownUnits.length} onClick={()=>{setUnitIds(previous=>[...new Set([...previous,...shownUnits.map(unit=>unit.id)])].slice(0,100));setPreview(null)}}>Markera sökträffarna</button><button type="button" disabled={busy||!unitIds.length} onClick={()=>{setUnitIds([]);setPreview(null)}}>Rensa mottagare</button></div><div className={styles.list}>{shownUnits.map(unit=><label key={unit.id} className={styles.check}><input type="checkbox" checked={unitIds.includes(unit.id)} disabled={disabled||!unitIds.includes(unit.id)&&unitIds.length>=100} onChange={event=>{setUnitIds(previous=>event.target.checked?[...previous,unit.id]:previous.filter(id=>id!==unit.id));setPreview(null)}}/>{unit.name}</label>)}{!loading&&!shownUnits.length&&<p>Ingen kostnadsbärare matchar sökningen.</p>}</div></details>}
    {mode==='selected'&&unitIds.length>0&&<div className={styles.chips} aria-label="Valda mottagare">{unitIds.map(id=><button key={id} type="button" disabled={busy} aria-label={`Ta bort mottagare ${data?.units.find(unit=>unit.id===id)?.name||id}`} onClick={()=>{setUnitIds(previous=>previous.filter(value=>value!==id));setPreview(null)}}>{data?.units.find(unit=>unit.id===id)?.name||id} ×</button>)}</div>}
    {mode==='all'&&<p>Alla giltiga ekonomiska enheter får en lika stor andel. Välj en grupp eller egna enheter för ett snävare urval.</p>}{mode==='stop'&&<p>Fördelningen avslutas från datumet nedan. Tidigare historik finns kvar.</p>}
   </section>
  </div>
  <section className={styles.card}><h3>3. Kontrollera och spara</h3><p><strong>{costs.length} kostnadsprojekt → {destination}</strong></p><div className={styles.fields}><label>Giltig från<input type="date" required value={validFrom} disabled={busy} onChange={event=>{setValidFrom(event.target.value);setPreview(null)}}/></label><label>Giltig till · valfritt<input type="date" min={validFrom} value={validTo} disabled={busy} onChange={event=>{setValidTo(event.target.value);setPreview(null)}}/></label><label>Motivering<input value={reason} disabled={busy} minLength={3} maxLength={1000} onChange={event=>{setReason(event.target.value);setPreview(null)}}/></label></div>
   <p>Hubben visar fördelningen före sparande. Originalbeloppen och tidigare kopplingars historik bevaras. Utan giltiga mottagare ligger kostnaden kvar som ofördelad.</p><button type="button" className="primary" disabled={disabled||!canReview} onClick={()=>void submit(true)}>{busy?'Hubben behandlar…':'Kontrollera fördelningen'}</button>
   {currentPreview&&<div className={styles.preview}><h4>Förhandsvisning från Humla Hub</h4><p>Total kostnad i rapportperioden: {money.format(currentPreview.before.cost)} → {money.format(currentPreview.after.cost)}</p><div className="table-wrap"><table><thead><tr><th>Mottagare</th><th>Kostnad före</th><th>Kostnad efter</th></tr></thead><tbody>{currentPreview.movements.map((movement,index)=><tr key={index}><td>{movement.dimension==='cost_center'?'Kostnadsställe · ':''}{movement.name}</td><td>{money.format(movement.before_cost)}</td><td>{money.format(movement.after_cost)}</td></tr>)}</tbody></table></div>{!currentPreview.movements.length&&<p>Inga belopp flyttas mellan mottagare i vald rapportperiod. Kontrollera datum och mottagarnas giltighet.</p>}<div className={styles.actions}><button type="button" className="primary" disabled={disabled||!canReview} onClick={()=>void submit(false)}>Godkänn och spara {costs.length} kostnadsprojekt</button><button type="button" disabled={busy} onClick={()=>setPreview(null)}>Ändra valen</button></div></div>}
  </section>
  <details className={styles.period}><summary>Senaste fördelningsregler</summary>{data?.history.filter(rule=>rule.dimension==='shared_cost').map((rule,index)=><p key={index}><strong>{rule.reference}</strong> → {rule.target==='*'?'Alla kostnadsbärare':rule.target==='none'?'Avslutad':rule.target.startsWith('[')?'Valda enheter':rule.target} · {rule.valid_from} – {rule.valid_to||'tills vidare'}</p>)}</details>
 </section>;
}
