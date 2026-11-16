'use client';
import {useEffect,useState} from 'react';

type Option={name:string;price:string};
type Settings={unit:string;siteKind:'none'|'pickup'|'delivery';enabled:boolean;options:Option[]};
const blank=()=>({name:'',price:''});
const initial:Settings={unit:'ton',siteKind:'none',enabled:false,options:[blank()]};

export default function ReportArticleSettings({id,unit}:{id:string;unit?:string}){
 const endpoint='/api/orderportal/report-articles?id='+encodeURIComponent(id);
 const [draft,setDraft]=useState<Settings>();
 const [busy,setBusy]=useState(false);
 const [error,setError]=useState('');
 const [saved,setSaved]=useState(false);
 useEffect(()=>{
  const ctrl=new AbortController();
  fetch(endpoint,{signal:ctrl.signal}).then(async response=>{
   const data=await response.json();if(!response.ok)throw Error(data.error);
   if(!ctrl.signal.aborted)setDraft(data||{...initial,unit:['st','tim','ton','lass','kg','m³','km'].includes(unit?.toLowerCase()||'')?unit!.toLowerCase():'ton'});
  }).catch(error=>{if(!ctrl.signal.aborted)setError(error.message);});
  return ()=>ctrl.abort();
 },[endpoint,unit]);
 function change(next:Settings){setDraft(next);setSaved(false);setError('');}
 async function save(settings:Settings){
  setBusy(true);setError('');setSaved(false);
  try{
   const response=await fetch(endpoint,{method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify(settings)});
   const body=await response.json();if(!response.ok)throw Error(body.error);
   setSaved(true);
  }catch(error){setError(error instanceof Error?error.message:'Sparandet misslyckades.');}
  finally{setBusy(false);}
 }
 return <section><h4>Chaufförens återrapportering</h4>
  {error&&<p role="alert">{error}</p>}
  {saved&&<p role="status">Artikelregeln är sparad.</p>}
  {!draft&&!error&&<p>Hämtar artikelregeln…</p>}
  {draft&&<form className="op-customer-settings" onSubmit={event=>{event.preventDefault();if(!busy)void save(draft);}}>
   <fieldset disabled={busy}>
    <label className="op-customer-checkbox"><input type="checkbox" checked={draft.enabled} onChange={event=>change({...draft,enabled:event.target.checked})}/>Valbar för chaufförer</label>
    <label>Fast enhet<select value={draft.unit} onChange={event=>change({...draft,unit:event.target.value})}>
     {['st','ton','tim','lass','kg','m³','km'].map(unit=><option key={unit}>{unit}</option>)}
    </select></label>
    <label>Platskrav<select value={draft.siteKind} onChange={event=>change({...draft,siteKind:event.target.value as Settings['siteKind'],options:[blank()]})}>
     <option value="none">Ingen plats</option><option value="pickup">Täkt / hämtplats</option><option value="delivery">Tippplats / mottagare</option>
    </select></label>
    <p>Pris i kr per enhet. Lämna tomt om priset ska granskas senare.</p>
    {draft.options.map((option,index)=><div className="op-customer-fields" key={index}>
     {draft.siteKind!=='none'&&<label>Platsnamn<input required maxLength={120} value={option.name} onChange={event=>change({...draft,options:draft.options.map((item,i)=>i===index?{...item,name:event.target.value}:item)})}/></label>}
     <label>Pris / {draft.unit}<input inputMode="decimal" value={option.price} onChange={event=>change({...draft,options:draft.options.map((item,i)=>i===index?{...item,price:event.target.value}:item)})}/></label>
     {draft.siteKind!=='none'&&<button type="button" className="op-secondary" onClick={()=>change({...draft,options:draft.options.filter((_,i)=>i!==index)})}>Ta bort plats</button>}
    </div>)}
    {draft.siteKind!=='none'&&<button type="button" className="op-secondary" disabled={draft.options.length>=50} onClick={()=>change({...draft,options:[...draft.options,blank()]})}>Lägg till plats</button>}
    <button className="op-primary">{busy?'Sparar…':'Spara artikelregel'}</button>
   </fieldset>
  </form>}
 </section>;
}
