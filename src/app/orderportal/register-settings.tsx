'use client';

import {useEffect,useState} from 'react';
import type {Resource} from '@/lib/orderportal/model';

type Settings={category:string;unit:string;note:string;revision:number};

export default function RegisterSettings({resource,onSaved}:{resource:Resource;onSaved:()=>void}){
 const [draft,setDraft]=useState<Settings>();
 const [saved,setSaved]=useState<Settings>();
 const [busy,setBusy]=useState(false);
 const [message,setMessage]=useState('');
 const [failed,setFailed]=useState(false);
 const [reload,setReload]=useState(0);
 const endpoint='/api/orderportal/register-settings?id='+encodeURIComponent(resource.id);
 useEffect(()=>{
  const controller=new AbortController();
  fetch(endpoint,{signal:controller.signal})
   .then(async response=>{const data=await response.json();if(!response.ok)throw Error(data.error);return data as Settings;})
   .then(data=>{if(!controller.signal.aborted){setSaved(data);setDraft(data);}})
   .catch(error=>{if(!controller.signal.aborted){setFailed(true);setMessage(error.message);}});
  return ()=>controller.abort();
 },[endpoint,reload]);

 async function save(){
  if(!draft||busy)return;
  setBusy(true);setMessage('');setFailed(false);
  try{
   const response=await fetch(endpoint,{method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify(draft)});
   const data=await response.json();
   if(!response.ok)throw Error(data.error);
   setDraft(data);setSaved(data);setMessage('Inställningarna är sparade.');
   onSaved();
  }catch(error){setFailed(true);setMessage(error instanceof Error?error.message:'Sparandet misslyckades.');}
  finally{setBusy(false);}
 }

 return <section><h4>Inställningar i orderportalen</h4>
  {draft?<form className="op-customer-settings" onSubmit={event=>{event.preventDefault();void save();}}>
   <fieldset disabled={busy}>
    <legend>{resource.kind==='Article'?'Artikeluppgifter':'Resursuppgifter'}</legend>
    <label>Kategori<input maxLength={80} value={draft.category} onChange={event=>setDraft({...draft,category:event.target.value})}/></label>
    {resource.kind==='Article'&&<label>Standardenhet på ny orderrad<input maxLength={20} value={draft.unit}
     placeholder={resource.details?.unit||resource.details?.unit_of_measure||'Exempel: ton'}
     onChange={event=>setDraft({...draft,unit:event.target.value})}/></label>}
    <label>Intern anteckning<textarea maxLength={2000} value={draft.note} onChange={event=>setDraft({...draft,note:event.target.value})}/></label>
   </fieldset>
   <button className="op-primary" disabled={busy||JSON.stringify(draft)===JSON.stringify(saved)}>{busy?'Sparar…':'Spara inställningar'}</button>
  </form>:!failed&&<p>Hämtar inställningar…</p>}
  {message&&<p role={failed?'alert':'status'}>{message}</p>}
  {failed&&<button type="button" className="op-secondary" onClick={()=>{
   if(draft&&JSON.stringify(draft)!==JSON.stringify(saved)&&!window.confirm('Ersätta osparade ändringar med de sparade uppgifterna?'))return;
   setDraft(undefined);setMessage('');setFailed(false);setReload(value=>value+1);
  }}>Ladda om</button>}
 </section>;
}
