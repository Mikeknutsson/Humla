import Link from 'next/link';
import {redirect} from 'next/navigation';
import {createClient} from '@/lib/supabase/server';
import './reports.css';
export const dynamic='force-dynamic';
const date=(value:string)=>new Date(value).toLocaleString('sv-SE',{timeZone:'Europe/Stockholm'});
export default async function Reports({searchParams}:{searchParams:Promise<{page?:string}>}){
 const db=await createClient();
 const {data:{user}}=await db.auth.getUser();
 if(!user)redirect('/orderportal/login');
 const {data:member}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').maybeSingle();
 const permission=member?await db.rpc('hub_has_permission',{p_tenant_id:member.tenant_id,p_permission:'transport.orders.manage'}):null;
 if(permission?.data!==true)return <main className="transport-reports"><h1>Mottagna rapporter</h1><p>Du behöver behörigheten Transport: orderledning för att läsa chaufförernas rapporter.</p><Link href="/orderportal">Till orderportalen</Link></main>;
 const params=await searchParams;const page=Math.max(0,Math.min(100000,Number.parseInt(params.page||'0',10)||0));
 const {data:orders,error,count}=await db.from('hub_transport_orders').select('id,order_number,payload,version',{count:'exact'}).eq('tenant_id',member!.tenant_id).not('payload->>driverSubmittedAt','is',null).order('updated_at',{ascending:false}).order('id').range(page*25,page*25+24);
 return <main className="transport-reports"><header><p>HUMLA · TRANSPORTLEDNING</p><h1>Mottagna rapporter <span>{count??'–'}</span></h1><p>Chaufförernas inskickade driftorder. Låsta för chauffören och redo för din kontroll.</p><nav><Link href="/orderportal">← Orderportal</Link><Link href={'/orderportal/rapporter?page='+page}>Uppdatera</Link></nav></header><aside>Under utveckling · Ingen fakturering. Den här vyn visar driftorder, inte testportalens order. Granskning och godkännande byggs vidare separat.</aside>
 {error?<p role="alert">Rapporterna kunde inte hämtas. Försök uppdatera sidan.</p>:!orders?.length?<p>Inga inskickade rapporter på den här sidan.</p>:orders.map(o=>{const p=o.payload,r=p.driverReport||{};return <details key={o.id}><summary><strong>{o.order_number} · {p.title}</strong><span> {p.status} · {date(p.driverSubmittedAt)}</span></summary><div className="report-content"><p><b>Kund:</b> {p.customer||'Ej angiven'} · <b>Projekt:</b> {p.project||'Ej angivet'}</p><p><b>Fordon:</b> {p.vehicle||'Ej angivet'} · <b>Förare:</b> {p.driver||'Se tilldelad person i ordern'}</p><p><b>Uppdrag:</b> {p.start?.replace('T',' ')} – {p.end?.replace('T',' ')} (svensk tid)</p><h2>Chaufförens återrapportering</h2><dl>{[['Timmar',r.hours],['Lass',r.loads],['Ton',r.tonnes]].map(([label,value])=><div key={label}><dt>{label}</dt><dd>{value??'Ej angivet'}</dd></div>)}</dl><p className="report-note">{r.note||'Ingen kommentar.'}</p><small>Inskickad {date(p.driverSubmittedAt)} · Orderversion {o.version}. Inskickande användare och ändringar sparas i historiken.</small></div></details>;})}
 <nav aria-label="Sidor">{page>0&&<Link href={'?page='+(page-1)}>← Föregående</Link>}{(count||0)>(page+1)*25&&<Link href={'?page='+(page+1)}>Nästa →</Link>}</nav></main>;
}
