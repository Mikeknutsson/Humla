import Link from 'next/link';
import {unitDailyRevenueTargets,weekdays} from '@/lib/hub/daily-revenue-target';
import {redirect} from 'next/navigation';
import {createClient} from '@/lib/supabase/server';
import {stockholmToday,previousYearDate} from '@/lib/kpi/period';
import {validTransportDate,type TransportScorecard} from '@/lib/kpi/transport-leader';
import {TransportBalanceCards} from '@/app/_components/kpi-transport-balance';
import {buildTransportCardAnalyses} from '@/lib/hub/transport-card-analysis';
import {ForemanSawBreakdown,type SawBreakdown} from '@/app/_components/foreman-saw-breakdown';
import {ForemanAreaKpis,type AreaKpis} from '@/app/_components/foreman-area-kpis';
import {ForemanResultTrend} from '@/app/_components/foreman-result-trend';
import type {ForemanTrend} from '@/lib/kpi/foreman-trend';
import {ForemanPeriodPicker} from '@/app/_components/foreman-period-picker';
import {foremanFiscalYear,resolveForemanPeriod,foremanPeriodQuery} from '@/lib/kpi/foreman-period';
import {KpiDetailShell} from '@/app/_components/kpi-detail-shell';

export const dynamic='force-dynamic';
const money=new Intl.NumberFormat('sv-SE',{style:'currency',currency:'SEK',maximumFractionDigits:0});

export default async function MyUnits({searchParams}:{searchParams:Promise<Record<string,string|undefined>>}) {
 const db=await createClient();const {data:{user}}=await db.auth.getUser();if(!user)redirect('/kpi/login');
 const {data:member}=await db.from('hub_tenant_members').select('tenant_id,role,display_name').eq('user_id',user.id).eq('status','active').limit(1).maybeSingle();
 if(!member)return <main className="content"><h1>Ingen aktiv arbetsyta</h1></main>;
 const q=await searchParams,today=stockholmToday();
 let fiscalYear:number;
 try{fiscalYear=foremanFiscalYear(q.fiscal_year,today);}catch{return <main className="content"><p>Ogiltigt verksamhetsår.</p><Link href="/kpi/mina-enheter">Återställ</Link></main>;}
 const owner=member.role==='owner';
 const [people,cutoff]=await Promise.all([
  owner?db.rpc('hub_foreman_profiles_v1',{p_tenant:member.tenant_id}):Promise.resolve({data:[],error:null}),
  db.rpc('hub_foreman_revenue_cutoff_v1',{p_tenant:member.tenant_id,p_fiscal_year:fiscalYear}),
 ]);
 const profileRows=(people.data??[]) as {user_id:string;display_name:string|null;role:string}[];
 let chosen:ReturnType<typeof resolveForemanPeriod>;
 try{chosen=resolveForemanPeriod(q,cutoff.error?null:cutoff.data?.revenue_through??null,today);}catch{return <main className="content"><p>Ogiltigt periodval.</p><Link href="/kpi/mina-enheter">Återställ</Link></main>;}
 const {from,to}=chosen;
 const target=owner?(q.user_id??null):user.id;
 const period=new URLSearchParams({from,...(to?{to}:{})});
 const controls=<ForemanPeriodPicker period={chosen} userId={owner?target:null} cutoffError={Boolean(cutoff.error)}/>;
 const profiles=owner&&<section className="panel">{!target&&<><h2>Välj arbetsledarvy</h2><p>Förhandsvisa det underlag respektive läsprofil får se.</p></>}{people.error?<p role="alert">Profilerna kunde inte hämtas. Försök igen.</p>:<div className={target?undefined:"metrics-grid"} style={target?{display:"flex",flexWrap:"wrap",gap:8}:undefined}><Link prefetch={false} className={target?"secondary":"metric-card"} href={"/kpi/verkstad?"+foremanPeriodQuery(chosen)}><strong>Verkstaden</strong>{!target&&<><span>KST 40 · Ekonomi och verkstadstid</span><small>Visa arbetsledarvy →</small></>}</Link>{profileRows.map(p=><Link key={p.user_id} prefetch={false} className={target?"secondary":"metric-card"} aria-current={target===p.user_id?'page':undefined} style={{textDecoration:'none',border:target===p.user_id?'2px solid #e1ad27':undefined}} href={'/kpi/mina-enheter?'+foremanPeriodQuery(chosen,p.user_id)}><strong>{p.display_name??'Arbetsledare'}</strong>{!target&&<><span>Läsåtkomst</span><small>Visa arbetsledarvy →</small></>}</Link>)}</div>}{!people.error&&!profileRows.length&&<p>Inga arbetsledarprofiler finns att förhandsvisa.</p>}</section>;
 if(owner&&!target)return <KpiDetailShell title="Arbetsledarvyer" breadcrumb="Humla Dashboard / Arbetsledarvyer" query={period.toString()}><div className="content">{profiles}<section className="panel">{controls}</section></div></KpiDetailShell>;
 if(!target)return <main className="content"><p>Ingen profil vald.</p></main>;
 if(to===null){const empty=<div className="content">{profiles}<section className="panel">{controls}<p>Giltigt intäktsunderlag saknas. Välj en annan period.</p></section></div>;return owner?<KpiDetailShell title="Arbetsledarvyer" query="">{empty}</KpiDetailShell>:<main>{empty}</main>;}
 if(!validTransportDate(from)||!validTransportDate(to)||from>to||Date.parse(to)-Date.parse(from)>366*86400000||!/^[0-9a-f-]{36}$/i.test(target))return <main className="content"><p>Ogiltigt urval.</p><Link href="/kpi/mina-enheter">Återställ</Link></main>;
 const args={p_tenant:member.tenant_id,p_from:from,p_to:to,p_user:target};
 if(owner&&!profileRows.some(p=>p.user_id===target))return <KpiDetailShell title="Arbetsledarvyer" query=""><div className="content">{profiles}<p role="alert">Välj en av arbetsledarprofilerna ovan.</p></div></KpiDetailShell>;
 const todayText=`${today.year}-${String(today.month).padStart(2,'0')}-${String(today.day).padStart(2,'0')}`;
 const historyTo=to<todayText?to:todayText;
 const [current,old,trendResult,history]=await Promise.all([
  db.rpc('hub_transport_leader_scorecard_v4',args),
  db.rpc('hub_transport_leader_scorecard_v4',{...args,p_from:previousYearDate(from),p_to:previousYearDate(to)}),
  db.rpc('hub_foreman_result_trend_v1',args),
  to>todayText&&from<=historyTo?db.rpc('hub_transport_leader_scorecard_v4',{...args,p_to:historyTo}):Promise.resolve(null),
 ]);
 const report=current.data as TransportScorecard|null,prior=old.data as TransportScorecard|null;
 const dailyReport=(from>historyTo||history?.error||(history?.data&&history.data.generation!==report?.generation)?null:history?history.data:current.error?null:current.data) as TransportScorecard|null;
 const dailyTargets=dailyReport?unitDailyRevenueTargets(dailyReport):undefined;
 const dailyPeriod=dailyReport?{from:dailyReport.from,to:dailyReport.to,days:weekdays(dailyReport.from,dailyReport.to)}:undefined;
 const trend=trendResult.data as ForemanTrend|null;
 const trendAvailable=!trendResult.error&&trend&&report&&trend.generation===report.generation&&trend.from===from&&trend.to===to;
 const name=owner?profileRows.find(p=>p.user_id===target)?.display_name:member.display_name;
 const base=new URLSearchParams({from,to,user_id:target}).toString();
 const view=<div className="content">{profiles}
 <header className="panel"><h1>{owner?name??'Arbetsledarvy':'Mina enheter'}</h1><p>{name??'Arbetsledare'} · Läsåtkomst · {from}–{to}</p>
 {owner&&<p role="status"><strong>Förhandsvisning som ägare.</strong> Du ser profilens avgränsade underlag. <Link href="/transport-styrning/admin">Hantera ansvar →</Link></p>}
 {controls}</header>
 {current.error||!report?<section className="panel" role="alert"><h2>Underlaget kunde inte hämtas</h2><p>Försök igen. Saknade belopp visas inte som noll.</p></section>:!report.units.length?<section className="panel"><h2>Inga tilldelade enheter i perioden</h2><p>Ansvar behöver mappas innan siffror kan visas. Kontakta Mike.</p></section>:<>
 {trendAvailable?<ForemanResultTrend key={target+from+to+report.generation} trend={trend!}/>:<section className="panel"><h2>Resultatets utveckling</h2><p role="status">Trenden kunde inte hämtas. Försök uppdatera vyn.</p></section>}
 <section className="metrics-grid">{(['revenue','cost','result']as const).map((key,i)=><article className="metric-card" key={key}><span>{['Intäkter','Kostnader','Resultat'][i]}</span><strong>{report.summary[key]==null?'Underlag saknas':money.format(report.summary[key]!)}</strong></article>)}<article className="metric-card"><span>Resultat %</span><strong>{report.summary.margin_percent==null?'–':new Intl.NumberFormat('sv-SE',{maximumFractionDigits:1}).format(report.summary.margin_percent)+' %'}</strong></article></section>
 <ForemanSawBreakdown value={(report as TransportScorecard &{saw_breakdown?:SawBreakdown|null}).saw_breakdown}/>
 <ForemanAreaKpis kpis={(report as TransportScorecard &{area_kpis?:AreaKpis}).area_kpis}/>
 <TransportBalanceCards report={{...report,groups:[]}} prior={prior} base={base} selectedUnit={null} selectedGroup={null} analyses={buildTransportCardAnalyses(report,prior)} hideGroups foremanMode dailyTargets={dailyTargets} dailyPeriod={dailyPeriod}/>
 <p>Endast dina tilldelade enheter och de datum ansvaret gäller. Kostnadsfördelningen visas direkt på varje enhetskort. Inga uppgifter kan ändras i denna vy.</p>
 </>}
 </div>;
 return owner?<KpiDetailShell title="Arbetsledarvyer" breadcrumb="Humla Dashboard / Arbetsledarvyer" query={period.toString()}>{view}</KpiDetailShell>:<main>{view}</main>;
}
