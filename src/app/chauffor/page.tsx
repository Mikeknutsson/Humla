import Link from 'next/link';
import {redirect} from 'next/navigation';
import {CheckCircle2,Truck,LogOut,ArrowRight,ShieldCheck} from 'lucide-react';
import {createClient} from '@/lib/supabase/server';
import {stockholmToday} from '@/lib/kpi/period';
import {driverPeriod,type DriverReport,type DriverDirectory} from '@/lib/hub/driver-self';
import {logout} from '@/app/kpi/login/actions';
import styles from './driver.module.css';
export const dynamic='force-dynamic';
const day=(s:string)=>new Intl.DateTimeFormat('sv-SE',{day:'numeric',month:'short',timeZone:'UTC'}).format(new Date(s+'T00:00:00Z'));
export default async function DriverPage({searchParams}:{searchParams:Promise<Record<string,string|undefined>>}){
 const db=await createClient();const {data:{user}}=await db.auth.getUser();if(!user)redirect('/kpi/login');
 const {data:member}=await db.from('hub_tenant_members').select('tenant_id,role').eq('user_id',user.id).eq('status','active').maybeSingle();
 if(!member)return <section className={styles.driverPage}><h1>Ingen aktiv arbetsyta</h1></section>;
 const q=await searchParams,owner=member.role==='owner',today=stockholmToday(),todayText=`${today.year}-${String(today.month).padStart(2,'0')}-${String(today.day).padStart(2,'0')}`;
 let period;try{period=driverPeriod(q.period,todayText);}catch{return <section className={styles.driverPage}><h1>Ogiltig period</h1><Link href="/chauffor">Återställ</Link></section>;}
 const person=owner?q.person??null:null;
 if(person&&!/^[0-9a-f-]{36}$/i.test(person))return <section className={styles.driverPage}><h1>Ogiltigt urval</h1></section>;
 const [{data,error},{data:directory}]=await Promise.all([
 db.rpc('hub_driver_self_v1',{p_tenant:member.tenant_id,p_from:period.from,p_to:period.to,p_person:person}),
 owner?db.rpc('hub_driver_directory_v1',{p_tenant:member.tenant_id}):Promise.resolve({data:null}),
 ]);
 const report=data as DriverReport|null,people=(directory as DriverDirectory|null)?.people??[];
 const href=(mode:string)=>'/chauffor?'+new URLSearchParams({period:mode,...(person?{person}:{})});
 const ready=!error&&report?.status==='ready';
 return <section className={styles.driverPage}>
 <header className={styles.top}><Link href="/chauffor" className={styles.brand}>humla<span>MIN KÖRNING</span></Link><form action={logout}><button className={styles.logout} aria-label="Logga ut"><LogOut size={18}/></button></form></header>
 {owner&&<aside className={styles.preview}><ShieldCheck size={18}/><div><strong>Förhandsvisning som ägare</strong><p>Välj chaufför för att se den personliga vyn.</p><form method="get"><input type="hidden" name="period" value={period.mode}/><label>Chaufför<select name="person" defaultValue={person??''} required><option value="" disabled>Välj chaufför</option>{people.map(p=><option key={p.id} value={p.id}>{p.name}</option>)}</select></label><button>Visa</button></form><Link href="/chauffor/admin">Koppla chaufförskonton <ArrowRight size={14}/></Link> · <Link href="/kpi">Dashboard</Link></div></aside>}
 <div className={styles.intro}><span className={styles.kicker}>DIN VARDAG, DIN UTVECKLING</span><h1>{ready?`Hej ${report.name?.split(' ')[0]??'chaufför'}!`:'Min körning'}</h1><p>Dina tider och din rapportering, samlat på ett ställe.</p></div>
 <nav className={styles.periods} aria-label="Välj period">{[['week','Denna vecka'],['four-weeks','Senaste 4 veckorna'],['month','Denna månad']].map(([key,label])=><Link key={key} href={href(key)} aria-current={period.mode===key?'page':undefined}>{label}</Link>)}</nav><p className={styles.dates}>{day(period.from)}–{day(period.to)}</p>
 {error||!report?<article className={styles.card} role="alert"><h2>Underlaget kunde inte hämtas</h2><p>Försök uppdatera sidan. Saknade uppgifter visas inte som dåliga resultat.</p></article>:!ready?<article className={styles.card}><Truck size={32}/><h2>{owner?'Välj en chaufför ovan':'Vi behöver koppla ditt konto'}</h2><p>{owner?'Du kan förhandsvisa chaufförerna innan deras konton kopplas.':'Be Mike koppla ditt konto till din chaufförsprofil. Därefter visas ditt eget underlag här.'}</p></article>:<>
 <article className={styles.hero} data-tone={report.reporting==='good'?'good':'neutral'}>
 <div className={styles.ring} aria-hidden="true"><CheckCircle2 size={34}/></div><div><span className={styles.kicker}>MIN RAPPORTERING</span><h2>{report.reporting==='good'?'Tiderna är inskickade':report.reporting==='attention'?'Se över dina tider':'Inga tider att visa'}</h2><p>{report.reporting==='good'?'Alla tider som finns registrerade i perioden är inskickade eller godkända.':report.reporting==='attention'?'Det finns registrerade tider som behöver följas upp i TransPA.':'Det finns inget registrerat tidsunderlag för perioden ännu.'}</p></div></article>
 <article className={styles.card}><h2>Mina dagar</h2><p>Senaste dagen överst. Öppna en dag för mer information.</p>
 <div className={styles.dayList}>{report.days?.map(d=><details key={d.date} className={styles.dayRow}><summary><span>{new Intl.DateTimeFormat('sv-SE',{weekday:'short',day:'numeric',month:'short',timeZone:'UTC'}).format(new Date(d.date+'T00:00:00Z'))}</span><strong data-tone={d.reporting==='good'?'good':'neutral'}>{d.reporting==='good'?'Inskickat':d.reporting==='attention'?'Se över':'Ingen tid registrerad'} <span aria-hidden="true">⌄</span></strong></summary><p>{d.reporting==='good'?'Registrerade tider är inskickade eller godkända.':d.reporting==='attention'?'Följ upp rapporteringen i TransPA.':'Inget tidsunderlag finns för dagen. Det betyder inte att du varit frånvarande.'}</p>{d.reporting!=='unknown'&&<p>{d.vehicle==='good'?'Ett fordon är angivet på tidrapporteringen.':'Fordonsuppgiften behöver kontrolleras. Be transportledningen om hjälp om något är fel.'}</p>}</details>)}</div>
 <small>Listan visar registrerat underlag, inte närvaro enligt schema.</small></article>
 <details className={styles.card}><summary className={styles.more}>Mer om min utveckling</summary><p>{report.trend==='up'?'Mer av din registrerade tid har en tydlig fordonsuppgift än förra perioden.':report.trend==='down'?'Mer registrerad tid saknar tydlig fordonsuppgift än förra perioden.':report.trend==='steady'?'Fordonsuppgifterna ligger på samma nivå som förra perioden.':'Mer historik behövs för att visa en jämförelse.'}</p><p>Jämförelsen avser föregående lika långa period och visar rapporteringens kvalitet.</p></details>
 <p className={styles.source}>Senast registrerade arbetsdag: {report.latest_work_date?day(report.latest_work_date):'saknas'}. Uppgifterna hämtas från TransPA.</p>
 </>}
 <footer className={styles.footer}>Bara ditt eget underlag · Ingen topplista · Inga ekonomibelopp</footer>
 </section>;
}
