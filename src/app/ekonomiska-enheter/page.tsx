import Link from 'next/link';
import {reviewAccess} from '@/lib/hub/review-access';
import type {EconomicUnitCatalog,EconomicMember} from '@/lib/hub/economic-units';
export const dynamic='force-dynamic';
const kind:Record<string,string>={vehicle:'Fordon',person:'Person',project:'Projekt',compound:'Sammansatt',overhead:'Gemensam'};
function Members({members}:{members:EconomicMember[]}){return <ul>{members.map(m=><li key={m.kind+':'+m.source_reference}>{kind[m.kind]??m.kind}: {m.source_reference} · {m.object_id?<><span>Kopplat</span><small> · Humla-ID {m.object_id}</small></>:<strong>Behöver granskas ({m.resolution==='ambiguous_identity'?'flera objekt':'objektkoppling saknas'})</strong>}</li>)}</ul>;}
export default async function EconomicUnits({searchParams}:{searchParams:Promise<{date?:string;unit?:string;q?:string}>}){
 const access=await reviewAccess();if(!access)return <main>Åtkomst saknas.</main>;
 const params=await searchParams,today=new Intl.DateTimeFormat('sv-SE',{timeZone:'Europe/Stockholm'}).format(new Date());
 const date=params.date&&/^\d{4}-\d{2}-\d{2}$/.test(params.date)&&!Number.isNaN(Date.parse(params.date))&&new Date(params.date).toISOString().slice(0,10)===params.date?params.date:today;
 const {data,error}=await access.db.rpc('hub_economic_units_catalog_v1',{p_tenant:access.tenantId,p_date:date});
 const catalog=data as EconomicUnitCatalog|null,query=(params.q??'').trim().toLocaleLowerCase('sv');
 const units=(catalog?.units??[]).filter(u=>!query||[u.name,u.business_group,...u.periods.flatMap(p=>p.members.map(m=>m.source_reference))].join(' ').toLocaleLowerCase('sv').includes(query));
 const selected=catalog?.units.find(u=>u.id===params.unit);
 const unresolved=(catalog?.units??[]).flatMap(u=>u.current_period?.members??[]).filter(m=>!m.object_id).length;
 const fiscalYear=Number(date.slice(0,4))-(Number(date.slice(5,7))<9?1:0);
 return <main className="content"><h1>Ekonomiska enheter</h1><p>Gemensamt register för Humla och Dashboarden. Bekräftade kopplingar, giltighetsperioder och ingående objekt sparas i Humla Hub.</p>
 <nav className="dashboard-report-actions"><Link prefetch={false} href="/kpi?view=kpi">Dashboard →</Link><Link prefetch={false} href="/kpi/kontrollpanel?section=units">Hantera kopplingar →</Link></nav>
 <section className="panel"><form><label>Kopplingar på datum <input name="date" type="date" defaultValue={date} required/></label> <label>Sök enhet, projekt eller regnummer <input name="q" defaultValue={params.q??''}/></label> <button>Visa</button></form><p>{catalog?.units.length??0} mappade enheter · {units.length} i sökningen · {unresolved} objektkopplingar behöver granskas på valt datum. Enheter utan transaktioner finns också i registret.</p></section>
 {error?<p role="alert">Enhetsregistret kunde inte hämtas.</p>:<section className="panel"><div className="table-wrap"><table><thead><tr><th>Enhet</th><th>Typ</th><th>Verksamhetsgrupp</th><th>Koppling på datum</th><th>Ingående objekt</th><th>Ekonomi</th></tr></thead><tbody>{units.map(u=><tr key={u.id}><td><Link prefetch={false} href={'?'+new URLSearchParams({date,unit:u.id,...(params.q?{q:params.q}:{})})}>{u.name} →</Link></td><td>{kind[u.unit_type]??u.unit_type}</td><td>{u.business_group??'–'}</td><td>{u.active_on_date?(u.enabled?'Aktiv':'Avstängd'):'Utanför giltighetsperiod'}</td><td><Members members={u.current_period?.members??[]}/></td><td><Link prefetch={false} href={'/kpi/enhet?'+new URLSearchParams({unit:u.id,fiscal_year:String(fiscalYear),months:String(Number(date.slice(5,7)))})}>Visa Dashboard →</Link></td></tr>)}</tbody></table></div></section>}
 {selected&&<section className="panel"><h2>{selected.name} – kopplingar och historik</h2><p>Humla-ID: {selected.id} · Version {selected.version}</p>{selected.periods.map((p,i)=><details key={p.source_period_id??i} open><summary>{p.valid_from} – {p.valid_to??'tills vidare'} · {p.name} · {p.enabled?'Aktiv':'Avstängd'}</summary>{p.main_vehicle&&<p>Intäktsbärande huvudfordon: {p.main_vehicle.source_reference}</p>}<Members members={p.members}/></details>)}{selected.components.length>0&&<><h3>Fördelade komponenter</h3>{selected.components.map(c=><div key={c.source_component_id}><p>{c.valid_from??'Från enhetens start'} – {c.valid_to??'tills vidare'} · {c.allocation_percent} %</p><Members members={[c.member]}/></div>)}</>}</section>}
 </main>;
}
