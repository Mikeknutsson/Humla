import Link from 'next/link';
import {reviewAccess} from '@/lib/hub/review-access';

export const dynamic='force-dynamic';
const date=(v:string|null)=>v?new Intl.DateTimeFormat('sv-SE',{dateStyle:'short',timeStyle:'short',timeZone:'Europe/Stockholm'}).format(new Date(v)):'—';

export default async function WorkshopOrdersPage(){
 const access=await reviewAccess();
 if(!access)return <main style={{padding:24}}>Du saknar behörighet att se verkstadens arbetsorder.</main>;
 const {data,error}=await access.db.from('hub_workshop_workorders').select('id,order_number,title,vehicle,planned_start,planned_end,completed_at,derived_status,planned_window_hours,linked_fault_count').eq('tenant_id',access.tenantId).order('planned_start',{ascending:false,nullsFirst:false}).limit(200);
 const rows=data??[];
 const count=rows.length;
 const unfinished=rows.filter(x=>!x.completed_at).length;
 const faults=rows.filter(x=>Number(x.linked_fault_count)>0).length;
 return <main style={{padding:'24px',maxWidth:1500,margin:'auto',color:'#20262b'}}>
  <p><Link href="/kpi/verkstad">← Verkstadsöversikt</Link></p>
  <h1>Verkstad · Arbetsorder</h1>
  <p>Arbetsorder från Fordonskontrollen. Visar de 200 senaste importerade posterna, inte en verifierad realtidskö.</p>
  {error?<p role="alert">Kunde inte läsa arbetsorder: {error.message}</p>:<>
   <div style={{display:'flex',gap:16,flexWrap:'wrap',margin:'20px 0'}}>
    {[['Visade AO',count],['Utan slutmarkering',unfinished],['Med felrapport',faults]].map(([label,value])=><div key={String(label)} style={{border:'1px solid #cbd5e1',borderRadius:8,padding:18,minWidth:170}}><div>{label}</div><strong style={{fontSize:28}}>{value}</strong></div>)}
   </div>
   <div style={{overflowX:'auto'}}>
    <table style={{width:'100%',borderCollapse:'collapse',fontSize:14}}>
     <thead><tr>{['AO','Fordon','Arbete','Start','Planerat slut','Färdig','Planeringsfönster','Felrapporter'].map(h=><th key={h} style={{textAlign:'left',padding:10,borderBottom:'2px solid #9ca3af',whiteSpace:'nowrap'}}>{h}</th>)}</tr></thead>
     <tbody>{rows.map(r=><tr key={r.id} style={{borderBottom:'1px solid #d1d5db'}}>
      <td style={{padding:10}}>{r.order_number||'—'}</td>
      <td style={{padding:10}}>{r.vehicle||'—'}</td>
      <td style={{padding:10}}>{r.title||'—'}</td>
      <td style={{padding:10,whiteSpace:'nowrap'}}>{date(r.planned_start)}</td>
      <td style={{padding:10,whiteSpace:'nowrap'}}>{date(r.planned_end)}</td>
      <td style={{padding:10,whiteSpace:'nowrap'}}>{date(r.completed_at)}</td>
      <td style={{padding:10}}>{r.planned_window_hours==null?'—':r.planned_window_hours+' h'}</td>
      <td style={{padding:10}}>{r.linked_fault_count}</td>
     </tr>)}</tbody>
    </table>
   </div>
   <p style={{fontSize:13,color:'#475569'}}>Planeringsfönster är kalendertid mellan start och slut, inte mekanikertimmar. Prioritet och faktisk tid från NeXT visas först när fälten är verifierade och matchade.</p>
  </>}
 </main>;
}
