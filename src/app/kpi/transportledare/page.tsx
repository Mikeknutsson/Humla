import Link from 'next/link';
import {redirect} from 'next/navigation';
import {createClient} from '@/lib/supabase/server';
import {stockholmToday,previousYearDate} from '@/lib/kpi/period';
import {type TransportScorecard,validTransportDate} from '@/lib/kpi/transport-leader';
import {KpiDetailShell} from '@/app/_components/kpi-detail-shell';
import {KpiPrint} from '@/app/_components/kpi-print';
import {saveTransportTarget} from './actions';
export const dynamic='force-dynamic';
const currency=new Intl.NumberFormat('sv-SE',{style:'currency',currency:'SEK',maximumFractionDigits:0});
const number=new Intl.NumberFormat('sv-SE',{maximumFractionDigits:1});
const money=(n:number|null|undefined)=>n==null?'Underlag saknas':currency.format(n);
const pct=(n:number|null|undefined,suffix='%')=>n==null?'Ej angivet':`${number.format(n)} ${suffix}`;
const labels:Record<string,string>={transport:'Transport',material:'Material',tipp:'Tippavgifter',other:'Övrigt / gemensamt',personnel:'Personal',fuel:'Bränsle',service_repair:'Service & Rep',fixed:'Fasta kostnader',depreciation:'Avskrivning'};
export default async function TransportLeader({searchParams}:{searchParams:Promise<Record<string,string|undefined>>}){
 const db=await createClient();const {data:{user}}=await db.auth.getUser();if(!user)redirect('/kpi/login');
 const {data:member}=await db.from('hub_tenant_members').select('tenant_id,display_name,role').eq('user_id',user.id).eq('status','active').limit(1).maybeSingle();
 if(!member)return <main className="content"><h1>Ingen aktiv arbetsyta</h1></main>;
 const q=await searchParams,today=stockholmToday(),fy=today.month>=9?today.year:today.year-1;
 const todayText=`${today.year}-${String(today.month).padStart(2,'0')}-${String(today.day).padStart(2,'0')}`;
 const from=q.from??`${fy}-09-01`,to=q.to??todayText,owner=member.role==='owner';
 const unit=q.unit??null,targetUser=owner?q.user_id??null:user.id;
 if(!validTransportDate(from)||!validTransportDate(to)||from>to||(Date.parse(to)-Date.parse(from))/86400000>366||(unit&&!/^[0-9a-f-]{36}$/i.test(unit))||(targetUser&&!/^[0-9a-f-]{36}$/i.test(targetUser)))return <main className="content"><h1>Ogiltigt urval</h1><Link href="/kpi/transportledare">Återställ urvalet</Link></main>;
 const page=Number(q.page??0);if(!Number.isInteger(page)||page<0||page>10000)return <main>Ogiltig sida.</main>;
 const args={p_tenant:member.tenant_id,p_from:from,p_to:to,p_user:targetUser,p_unit:unit,p_page:page};
 const [{data,error},{data:previous},{data:people}]=await Promise.all([
 db.rpc('hub_transport_leader_scorecard_v2',args),
 db.rpc('hub_transport_leader_scorecard_v2',{...args,p_from:previousYearDate(from),p_to:previousYearDate(to),p_page:0}),
 owner?db.from('hub_tenant_members').select('user_id,display_name').eq('tenant_id',member.tenant_id).eq('status','active').order('display_name'):Promise.resolve({data:[]})]);
 const params=new URLSearchParams({from,to});if(targetUser)params.set('user_id',targetUser);
 const base=params.toString();
 const report=data as TransportScorecard|null,prior=previous as TransportScorecard|null;
 const selected=report?.units.find(u=>u.unit_id===unit);
 const selfView=report?.scope==='assigned';
 return <KpiDetailShell query={base} title="Transportledar-KPI" extraNavigation={<Link href={'/kpi/transportledare?'+base}>Transportledar-KPI</Link>}><div className="content">
 <section className="panel"><div className="panel-head"><div><h2>{unit?selected?.unit_name??'Enhetsunderlag':selfView?'Mina kostnadsenheter':'Transport – samlad uppföljning'}</h2><p>{from} – {to}{selfView?' · Enbart tilldelade enheter, på de datum ansvaret gäller':' · KST 30'}</p></div><KpiPrint/></div>
 <form method="get" className="form-grid"><label>Från<input type="date" name="from" defaultValue={from} required/></label><label>Till<input type="date" name="to" defaultValue={to} required/></label>{owner&&<label>Ansvar<select name="user_id" defaultValue={targetUser??''}><option value="">Alla enheter inom Transport</option>{people?.map(p=><option key={p.user_id} value={p.user_id}>{p.display_name??'Användare'} – tilldelade enheter</option>)}</select></label>}<button type="submit">Visa</button></form>
 <p><Link href={'/kpi/transportledare?'+new URLSearchParams({from:`${fy}-09-01`,to:todayText,...(targetUser?{user_id:targetUser}:{})})}>YTD till dagens datum</Link>{owner&&<> · <Link href="/transport-styrning/admin">Hantera tilldelningar</Link></>}</p></section>
 {error||!report?<section className="panel" role="alert"><h2>Styrkortet kunde inte hämtas</h2><p>Kontrollera behörighet och publicerat rapportunderlag. Saknade belopp visas inte som noll.</p></section>:<>
 <section className="metrics-grid">{([['Omsättning','revenue'],['Kostnader','cost'],['Resultat','result']]as const).map(([label,key])=><article className="metric-card" key={key}><span>{label}</span><strong>{money(report.summary[key])}</strong><small>Samma period fg. år: {money(prior?.summary[key])}</small></article>)}</section>
 {!report.units.length&&<section className="panel"><h2>Inget underlag i urvalet</h2><p>{selfView?'Inga transaktioner är kopplade till dina tilldelade enheter under dessa datum. En ägare kan lägga in ansvar med giltighetsdatum.':'Det finns inga publicerade transaktioner för urvalet.'}</p></section>}
 <section className="panel"><h2>Ekonomiska enheter</h2><div className="monthly-scroll"><table><thead><tr><th>Enhet</th><th>Omsättning</th><th>Kostnad</th><th>Resultat</th><th>Marginal</th><th>Mål</th><th>Avvikelse</th><th>Avvikelse kr</th></tr></thead><tbody>{report.units.map(u=><tr key={u.unit_id??'unassigned'}><td>{u.unit_id?<Link prefetch={false} href={'/kpi/transportledare?'+base+'&unit='+u.unit_id}>{u.unit_name??'Enhet'}</Link>:'Ej kopplat till enhet'}</td><td>{money(u.revenue)}</td><td>{money(u.cost)}</td><td>{money(u.result)}</td><td>{pct(u.margin_percent)}</td><td>{pct(u.target_margin_percent)}</td><td>{pct(u.deviation_pp,'pp')}</td><td>{u.deviation_amount==null?'Ej angivet':money(u.deviation_amount)}</td></tr>)}</tbody></table></div><p>Mål beräknas per transaktionsdatum och vägs med omsättningen. Saknas mål för en del av omsättningen visas inget sammanvägt mål. Inga exempelvärden har lagts in.</p>{report.summary.unassigned_rows>0&&<p>{report.summary.unassigned_rows} rader saknar ekonomisk enhet och ingår i totalsumman under ”Ej kopplat till enhet”.</p>}</section>
 <section className="panel"><h2>Transport, material och tippavgifter</h2><div className="monthly-scroll"><table><thead><tr><th>Del</th><th>Intäkt</th><th>Direkta kostnader</th><th>Resultat</th><th>Marginal</th></tr></thead><tbody>{report.sections.map(s=><tr key={s.section}><td>{labels[s.section]??s.section}</td><td>{money(s.revenue)}</td><td>{money(s.cost)}</td><td>{s.result==null?'Ej fullständigt fördelat':money(s.result)}</td><td>{s.margin_percent==null?'–':pct(s.margin_percent)}</td></tr>)}</tbody></table></div><p>Personal, bränsle, fasta kostnader och andra kostnader utan verifierad artikelkoppling ligger under Övrigt / gemensamt. De ingår i enhetens totala resultat. Delarnas resultat och marginal visas först när kostnaderna är fullständigt fördelade; kombinerade artiklar delas enligt Hub-reglerna.</p></section>
 {unit&&<section className="panel"><h2>Arbetsorder och originalrader</h2><p>100 transaktioner per sida. Alla tilldelade körningar ingår, även körningar inom andra områden. Kostnader utan verifierad orderkoppling ligger kvar som enhetskostnad.</p><div className="monthly-scroll"><table><thead><tr><th>Datum / order</th><th>Kund / projekt</th><th>Källa</th><th>Kategori</th><th>Typ</th><th>Belopp / original</th></tr></thead><tbody>{report.transactions.map(t=><tr key={t.fact_id}><td>{t.occurred_on} · {t.order_number??'Ingen orderkoppling'}</td><td>{t.customer??'–'} / {t.project??'–'}</td><td>{t.source}</td><td>{labels[t.category]??t.category}</td><td>{t.kind==='revenue'?'Intäkt':'Kostnad'}</td><td><details><summary>{money(t.amount)}</summary><pre style={{whiteSpace:'pre-wrap',maxWidth:600}}>{JSON.stringify(t.original,null,2)}</pre></details></td></tr>)}</tbody></table></div><nav aria-label="Underlagssidor">{page>0&&<Link href={'/kpi/transportledare?'+base+'&unit='+unit+'&page='+(page-1)}>← Föregående</Link>} {report.transactions.length===100&&<Link href={'/kpi/transportledare?'+base+'&unit='+unit+'&page='+(page+1)}>Nästa →</Link>}</nav></section>}
 {owner&&unit&&selected&&<section className="panel"><h2>Målmarginal – {selected.unit_name}</h2>{q.saved&&<p role="status">{q.saved==='yes'?'Målet är sparat.':'Målet kunde inte sparas. Kontrollera datum, värde och om ett mål redan finns på eller efter valt startdatum.'}</p>}<form action={saveTransportTarget} className="form-grid"><input type="hidden" name="unit_id" value={unit}/><input type="hidden" name="from" value={from}/><input type="hidden" name="to" value={to}/><label>Målmarginal, %<input type="number" name="margin" min="-100" max="100" step="0.1" required/></label><label>Gäller från<input type="date" name="valid_from" defaultValue={from} required/></label><label>Motivering<input name="reason" minLength={3} maxLength={1000} required/></label><button type="submit">Spara nytt mål</button></form><p>Ett nytt mål avslutar föregående mål dagen innan. Tidigare målperioder behålls.</p></section>}
 <p>Publicerat underlag: {report.synced_at?new Intl.DateTimeFormat('sv-SE',{dateStyle:'short',timeStyle:'short',timeZone:'Europe/Stockholm'}).format(new Date(report.synced_at)):'–'}. Samma Hub-underlag som Enhetsuppföljningen.</p>
 </>}
 </div></KpiDetailShell>;
}
