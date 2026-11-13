'use client';

import {useEffect,useState} from 'react';
import type {CustomerCard,CustomerProfile,DocumentSettings} from '@/lib/orderportal/customer-card';

export function useCustomerCard(id:string){
 const [state,setState]=useState<{id:string;card?:CustomerCard;error?:string}>();
 const [reload,setReload]=useState(0);
 useEffect(()=>{
  if(!id)return;
  const controller=new AbortController();
  fetch('/api/orderportal/customer-card?id='+encodeURIComponent(id),{signal:controller.signal})
   .then(async response=>{const data=await response.json();if(!response.ok)throw Error(data.error);return data as CustomerCard;})
   .then(card=>setState({id,card}))
   .catch(error=>{if(!controller.signal.aborted)setState({id,error:error.message});});
  return ()=>controller.abort();
 },[id,reload]);
 return {card:state?.id===id?state.card:undefined,error:state?.id===id?state.error:undefined,
  refresh:()=>{setState(undefined);setReload(value=>value+1);}};
}

const flags:{key:Exclude<keyof DocumentSettings,'recipient'>;label:string}[]=[
 {key:'deliveryNote',label:'Följesedel'},{key:'invoiceData',label:'Fakturaunderlag'},
 {key:'showRoute',label:'Visa hämt- och lämnaplats'},{key:'signature',label:'Begär signatur'},
];

export default function CustomerCardPanel({id}:{id:string}){
 const {card,error,refresh}=useCustomerCard(id);
 return <section><h4>Kundinställningar</h4>
  {error?<p role="alert">{error} <button type="button" onClick={refresh}>Försök igen</button></p>:
   card?<CustomerCardEditor id={id} initial={card} refresh={refresh}/>:<p>Hämtar kundinställningar…</p>}
 </section>;
}

function CustomerCardEditor({id,initial,refresh}:{id:string;initial:CustomerCard;refresh:()=>void}){
 const [saved,setSaved]=useState(initial);
 const [draft,setDraft]=useState<CustomerProfile>(initial.profile);
 const [busy,setBusy]=useState(false);
 const [message,setMessage]=useState('');
 const [failed,setFailed]=useState(false);
 const dirty=JSON.stringify(draft)!==JSON.stringify(saved.profile);
 async function save(){
  setBusy(true);setMessage('');setFailed(false);
  try{
   const response=await fetch('/api/orderportal/customer-card?id='+encodeURIComponent(id),{
    method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify({profile:draft,revision:saved.revision})
   });
   const result=await response.json();
   if(!response.ok)throw Error(result.error);
   setSaved(result);setDraft(result.profile);setMessage('Kundkortet är sparat.');
  }catch(error){setFailed(true);setMessage(error instanceof Error?error.message:'Sparandet misslyckades.');}
  finally{setBusy(false);}
 }
 return <form className="op-customer-settings" onSubmit={e=>{e.preventDefault();if(!busy&&dirty)void save();}}>
  <fieldset disabled={busy}>
   <legend>Kontaktpersoner</legend>
   {draft.contacts.map((contact,i)=><div className="op-customer-fields" key={i}>
    <label>Namn<input required maxLength={150} value={contact.name} onChange={e=>{const name=e.target.value;setDraft(d=>({...d,contacts:d.contacts.map((c,j)=>j===i?{...c,name}:c)}));}}/></label>
    <label>E-post<input type="email" maxLength={254} value={contact.email} onChange={e=>{const email=e.target.value;setDraft(d=>({...d,contacts:d.contacts.map((c,j)=>j===i?{...c,email}:c)}));}}/></label>
    <label>Telefon<input type="tel" maxLength={60} value={contact.phone} onChange={e=>{const phone=e.target.value;setDraft(d=>({...d,contacts:d.contacts.map((c,j)=>j===i?{...c,phone}:c)}));}}/></label>
    <button type="button" className="op-secondary" onClick={()=>setDraft(d=>({...d,contacts:d.contacts.filter((_,j)=>j!==i)}))}>Ta bort kontakt</button>
   </div>)}
   <button type="button" className="op-secondary" disabled={draft.contacts.length>=50} onClick={()=>setDraft(d=>({...d,contacts:[...d.contacts,{name:'',email:'',phone:''}]}))}>Lägg till kontakt</button>
  </fieldset>
  <fieldset disabled={busy}>
   <legend>Kundmärkningar</legend>
   {draft.markings.map((marking,i)=><div className="op-customer-fields" key={i}>
    <label>Nummer<input required maxLength={80} value={marking.number} onChange={e=>{const number=e.target.value;setDraft(d=>({...d,markings:d.markings.map((m,j)=>j===i?{...m,number}:m)}));}}/></label>
    <label>Beskrivning<input maxLength={250} value={marking.description} onChange={e=>{const description=e.target.value;setDraft(d=>({...d,markings:d.markings.map((m,j)=>j===i?{...m,description}:m)}));}}/></label>
    <button type="button" className="op-secondary" onClick={()=>setDraft(d=>({...d,markings:d.markings.filter((_,j)=>j!==i)}))}>Ta bort märkning</button>
   </div>)}
   <button type="button" className="op-secondary" disabled={draft.markings.length>=100} onClick={()=>setDraft(d=>({...d,markings:[...d.markings,{number:'',description:''}]}))}>Lägg till märkning</button>
  </fieldset>
  <fieldset disabled={busy}>
   <legend>Dokumentinställningar</legend>
   {flags.map(({key,label})=><label className="op-customer-checkbox" key={key}>
    <input type="checkbox" checked={draft.documents[key]} onChange={e=>{const checked=e.target.checked;setDraft(d=>({...d,documents:{...d.documents,[key]:checked}}));}}/>{label}
   </label>)}
   <label>Dokumentmottagare<input type="email" maxLength={254} value={draft.documents.recipient} onChange={e=>{const recipient=e.target.value;setDraft(d=>({...d,documents:{...d.documents,recipient}}));}}/></label>
   <label>Intern kommentar<textarea maxLength={2000} value={draft.note} onChange={e=>{const note=e.target.value;setDraft(d=>({...d,note}));}}/></label>
  </fieldset>
  <button className="op-primary" disabled={busy||!dirty}>{busy?'Sparar…':'Spara kundkort'}</button>
  {failed&&<button type="button" className="op-secondary" onClick={()=>{if(window.confirm('Hämta sparat kundkort och ersätta dina osparade ändringar?'))refresh();}}>Ladda om</button>}
  {message&&<p role={failed?'alert':'status'}>{message}</p>}
 </form>;
}
