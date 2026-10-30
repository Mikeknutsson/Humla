import Link from 'next/link';
import {redirect} from 'next/navigation';
import {CheckCircle2,Truck,TrendingUp,ClipboardCheck,Fuel,LogOut,ArrowRight,ShieldCheck} from 'lucide-react';
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
 <div className={styles.intro}><span className={styles.kicker}>DIN VARDAG, DIN UTVECKLING</span><h1>{ready?`Hej ${report.name?.split(' ')[0]??'chaufför'}!`:'Min körning'}</h1><p>En enkel koll på din rapportering och fordonskoppling.</p></div>
 <nav className={styles.periods} aria-label="Välj period">{[['week','Denna vecka'],['four-weeks','Senaste 4 veckorna'],['month','Denna månad']].map(([key,label])=><Link key={key} href={href(key)} aria-current={period.mode===key?'page':undefined}>{label}</Link>)}</nav><p className={styles.dates}>{day(period.from)}–{day(period.to)}</p>
 {error||!report?<article className={styles.card} role="alert"><h2>Underlaget kunde inte hämtas</h2><p>Försök uppdatera sidan. Saknade uppgifter visas inte som dåliga resultat.</p></article>:!ready?<article className={styles.card}><Truck size={32}/><h2>{owner?'Välj en chaufför ovan':'Vi behöver koppla ditt konto'}</h2><p>{owner?'Du kan förhandsvisa chaufförerna innan deras konton kopplas.':'Be Mike koppla ditt konto till din chaufförsprofil. Därefter visas ditt eget underlag här.'}</p></article>:<>
 <article className={styles.hero} data-tone={report.vehicle_link==='good'?'good':'neutral'}><div className={styles.ring} role="img" aria-label={report.vehicle_link==='good'?'Tydlig fordonskoppling':report.vehicle_link==='unknown'?'Underlag saknas':'Fordonskoppling behöver ses över'}><Truck size={34}/></div><div><span className={styles.kicker}>DET HÄR KAN DU PÅVERKA</span><h2>{report.vehicle_link==='good'?'Tydlig fordonskoppling':report.vehicle_link==='unknown'?'Vi väntar på underlag':'Se över fordonskopplingen'}</h2><p>{report.vehicle_link==='good'?'Din registrerade tid är till stor del kopplad till ett fordon.':report.vehicle_link==='unknown'?'Det finns ingen registrerad arbetstid i perioden.':'En del av din tid saknar ett entydigt fordon. Det kan bero på rapporteringen eller på kopplingen mellan systemen.'}</p></div></article>
 <div className={styles.grid}><article className={styles.card}><ClipboardCheck className={styles.icon} size={24}/><h2>Min rapportering</h2><strong className={styles.status} data-tone={report.reporting==='good'?'good':'neutral'}>{report.reporting==='good'?'Registrerade tider inskickade':report.reporting==='attention'?'Rapportering att följa upp':'Underlag saknas'}</strong><p>{report.reporting==='good'?'De tider som finns i underlaget är inskickade eller godkända.':'Kontrollera din tidrapportering med transportledningen.'}</p><small>Avser registrerade tider. Saknade arbetsdagar kan inte upptäckas utan ett schema.</small></article>
 <article className={styles.card}><TrendingUp className={styles.icon} size={24}/><h2>Min utveckling</h2><strong className={styles.status}>{report.trend==='up'?'Tydligare koppling':report.trend==='down'?'Mer tid utan koppling':report.trend==='steady'?'På samma nivå':'Mer historik behövs'}</strong><p>Fordonskopplad andel av din registrerade tid jämfört med föregående lika långa period. Det här är ingen prestationsbedömning.</p></article></div>
 <article className={styles.card}><h2>Din utveckling över perioden</h2><p>Hur tydligt din registrerade tid är kopplad till ett fordon.</p><div className={styles.timeline}>{report.weeks?.map(w=><div key={w.from}><div className={styles.track} role="img" aria-label={day(w.from)+'–'+day(w.to)+': '+(w.band==null?'underlag saknas':['','Behöver ses över','Delvis kopplat','Mestadels kopplat','Tydligt kopplat'][w.band])}><span style={{height:w.band==null?'0':`${w.band*25}%`}}/></div><small>{day(w.from)}</small><b>{w.band==null?'Saknas':['','Se över','Delvis','Mestadels','Tydligt'][w.band]}</b></div>)}</div></article>
 <h2 className={styles.sectionTitle}>Så går bilen</h2><div className={styles.grid}><article className={styles.card}><Truck className={styles.icon} size={24}/><h2>Bilens läge mot målet</h2><strong className={styles.status}>Ännu inte aktiverad</strong><p>Ekonomisk återkoppling kräver verifierad koppling mellan dig, bilen och körningarna. Reparationer, priser och tillgång på uppdrag påverkar bilens läge.</p></article><article className={styles.card}><Fuel className={styles.icon} size={24}/><h2>Bränsleutveckling</h2><strong className={styles.status}>Ännu inte aktiverad</strong><p>Förbrukning behöver körsträcka, rätt fordon och jämförbara uppdrag. Tankad mängd räcker inte för att bedöma din körning.</p></article></div>
 {report.reporting==='good'&&<aside className={styles.encouragement}><CheckCircle2 size={22}/><span>Bra! Tiderna som finns registrerade i perioden är inskickade.</span></aside>}
 <p className={styles.source}>Senast registrerade arbetsdag: {report.latest_work_date?day(report.latest_work_date):'saknas'}. Underlaget kommer från TransPA via Humla.</p>
 </>}
 <footer className={styles.footer}>Bara ditt eget underlag · Ingen topplista · Inga ekonomibelopp</footer>
 </section>;
}
