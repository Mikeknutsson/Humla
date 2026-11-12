'use client';
import {useEffect,useRef} from 'react';
import {X,Wrench,Truck,CalendarDays} from 'lucide-react';
import type {Order} from '@/lib/orderportal/model';
export default function MaintenanceDialog({order,onClose}:{order:Order;onClose:()=>void}){
 const ref=useRef<HTMLDialogElement>(null);
 useEffect(()=>{const dialog=ref.current;dialog?.showModal();return ()=>dialog?.close();},[]);
 return <dialog ref={ref} className="op-dialog" aria-label={'Underhållsorder '+order.number} onCancel={onClose}>
  <header className="op-editorhead"><div><span className="op-eyebrow">FORDONSKONTROLLEN · EJ DEBITERBAR</span><h2><Wrench size={24}/> {order.number}</h2><p>{order.status} · ändras i Fordonskontrollen</p></div><button className="op-icon" aria-label="Stäng" onClick={onClose}><X/></button></header>
  <div className="op-editorbody"><h2>{order.title}</h2><p><Truck size={18}/> {order.vehicle||'Fordonskoppling saknas'}</p><p><CalendarDays size={18}/> {order.start.replace('T',' ')||'Starttid saknas'} – {order.end.replace('T',' ')||'Sluttid saknas'} · svensk tid</p>
   {order.issues.map(issue=><p className="op-error" key={issue}>{issue}</p>)}
   <h3>Plats</h3><p>{order.location||'Ej angiven'}</p><h3>Instruktioner</h3><p style={{whiteSpace:'pre-wrap'}}>{order.instruction||'Inga instruktioner'}</p>
   <p className="op-notice">Underhållsorder från Fordonskontrollen. Ingen fakturering eller intäkt skapas. Tid och fordon följer källsystemet och kan inte ändras med drag och släpp.</p>
   <p className="op-help">Källreferens {order.reference} · Hub-version {order.version}. Saknad sluttid innebär att Humla inte kan avgöra när fordonet är tillgängligt igen.</p>
  </div><footer className="op-editorfoot"><button className="op-secondary" onClick={onClose}>Stäng</button></footer>
 </dialog>;
}
