import Link from 'next/link';
import {redirect} from 'next/navigation';
import {createClient} from '@/lib/supabase/server';
import {stockholmToday,previousYearDate} from '@/lib/kpi/period';
import {validTransportDate,type TransportScorecard} from '@/lib/kpi/transport-leader';
import {TransportBalanceCards} from '@/app/_components/kpi-transport-balance';
import {buildTransportCardAnalyses} from '@/lib/hub/transport-card-analysis';
import {KpiDetailShell} from '@/app/_components/kpi-detail-shell';

export const dynamic='force-dynamic';
const money=new Intl.NumberFormat('sv-SE',{style:'currency',currency:'SEK',maximumFractionDigits:0});

export default async function MyUnits({searchParams}:{searchParams:Promise<Record<string,string|undefined>>}) {
 const db=await createClient();const {data:{user}}=await db.auth.getUser();if(!user)redirect('/kpi/login');
 const {data:member}=await db.from('hub_tenant_members').select('tenant_id,role,display_name').eq('user_id',user.id).eq('status','active').limit(1).maybeSingle();
 if(!member)return <main className="content"><h1>Ingen aktiv arbetsyta</h1></main>;
 const q=await searchParams,today=stockholmToday(),fy=today.month>=9?today.year:today.year-1;
 const from=q.from??`${fy}-09-01`,to=q.to??`${today.year}-${String(today.month).padStart(2,'0')}-${String(today.day).padStart(2,'0')}`;
 const owner=member.role==='owner';
 const people=owner?await db.from('hub_tenant_members').select('user_id,display_name').eq('tenant_id',member.tenant_id).eq('status','active').eq('role','supervisor').order('display_name'):{data:[],error:null};
 const target=owner?(q.user_id??null):user.id;
 const period=new URLSearchParams({from,to});
 const profiles=owner&&<section className="panel"><h2>Välj arbetsledarvy</h2><p>Förhandsvisa det underlag respektive läsprofil får se.</p>{people.error?<p role="alert">Profilerna kunde inte hämtas. Försök igen.</p>:<div className="metrics-grid">{people.data?.map(p=><Link key={p.user_id} prefetch={false} className="metric-card" aria-current={target===p.user_id?'page':undefined} style={{textDecoration:'none',border:target===p.user_id?'2px solid #e1ad27':undefined}} href={'/kpi/mina-enheter?'+new URLSearchParams({from,to,user_id:p.user_id})}><strong>{p.display_name??'Arbetsledare'}</strong><span>Läsåtkomst</span><small>Visa arbetsledarvy →</small></Link>)}</div>}{!people.error&&!people.data?.length&&<p>Inga arbetsledarprofiler finns att förhandsvisa.</p>}</section>;
 if(owner&&!target)return <KpiDetailShell title="Arbetsledarvyer" breadcrumb="Humla Dashboard / Arbetsledarvyer" query={period.toString()}><div className="content">{profiles}</div></KpiDetailShell>;
 if(!target)return <main className="content"><p>Ingen profil vald.</p></main>;
 if(!validTransportDate(from)||!validTransportDate(to)||from>to||Date.parse(to)-Date.parse(from)>366*86400000||!/^[0-9a-f-]{36}$/i.test(target))return <main className="content"><p>Ogiltigt urval.</p><Link href="/kpi/mina-enheter">Återställ</Link></main>;
 const args={p_tenant:member.tenant_id,p_from:from,p_to:to,p_user:target};
 if(owner&&!people.data?.some(p=>p.user_id===target))return <KpiDetailShell title="Arbetsledarvyer" query=""><div className="content">{profiles}<p role="alert">Välj en av arbetsledarprofilerna ovan.</p></div></KpiDetailShell>;
 const [current,old]=await Promise.all([
  db.rpc('hub_transport_leader_scorecard_v4',args),
  db.rpc('hub_transport_leader_scorecard_v4',{...args,p_from:previousYearDate(from),p_to:previousYearDate(to)}),
 ]);
 const report=current.data as TransportScorecard|null,prior=old.data as TransportScorecard|null;
 const name=owner?people.data?.find(p=>p.user_id===target)?.display_name:member.display_name;
 const base=new URLSearchParams({from,to,user_id:target}).toString();
 const view=<div className="content">{profiles}
 <header className="panel"><h1>{owner?name??'Arbetsledarvy':'Mina enheter'}</h1><p>{name??'Arbetsledare'} · Läsåtkomst · {from}–{to}</p>
 {owner&&<p role="status"><strong>Förhandsvisning som ägare.</strong> Du ser profilens avgränsade underlag. <Link href="/transport-styrning/admin">Hantera ansvar →</Link></p>}
 <form method="get" className="form-grid"><label>Från<input type="date" name="from" defaultValue={from} required/></label><label>Till<input type="date" name="to" defaultValue={to} required/></label>
 {owner&&<input type="hidden" name="user_id" value={target}/>}<button type="submit">Visa</button></form></header>
 {current.error||!report?<section className="panel" role="alert"><h2>Underlaget kunde inte hämtas</h2><p>Försök igen. Saknade belopp visas inte som noll.</p></section>:!report.units.length?<section className="panel"><h2>Inga tilldelade enheter i perioden</h2><p>Ansvar behöver mappas innan siffror kan visas. Kontakta Mike.</p></section>:<>
 <section className="metrics-grid">{(['revenue','cost','result']as const).map((key,i)=><article className="metric-card" key={key}><span>{['Intäkter','Kostnader','Resultat'][i]}</span><strong>{report.summary[key]==null?'Underlag saknas':money.format(report.summary[key]!)}</strong></article>)}</section>
 <TransportBalanceCards report={{...report,groups:[]}} prior={prior} base={base} selectedUnit={null} selectedGroup={null} analyses={buildTransportCardAnalyses(report,prior)} hideGroups/>
 <p>Endast dina tilldelade enheter och de datum ansvaret gäller. Klicka på en enhet för underlag. Inga uppgifter kan ändras i denna vy.</p>
 </>}
 </div>;
 return owner?<KpiDetailShell title="Arbetsledarvyer" breadcrumb="Humla Dashboard / Arbetsledarvyer" query={period.toString()}>{view}</KpiDetailShell>:<main>{view}</main>;
}
