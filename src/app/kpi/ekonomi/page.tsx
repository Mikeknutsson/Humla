import Link from "next/link";
import {redirect} from "next/navigation";
import {createClient} from "@/lib/supabase/server";
import {parseMonthPeriod,monthPeriodQuery,fiscalMonths,stockholmToday} from "@/lib/kpi/period";
import type {Analysis} from "@/lib/kpi/analysis";
import {economyLogout} from "./login/actions";
import styles from "./ekonomi.module.css";
export const dynamic="force-dynamic";
const fmt=new Intl.NumberFormat("sv-SE",{style:"currency",currency:"SEK",maximumFractionDigits:0});
const integer=new Intl.NumberFormat("sv-SE",{maximumFractionDigits:0});
const monthNames:Record<number,string>={9:"Sep",10:"Okt",11:"Nov",12:"Dec",1:"Jan",2:"Feb",3:"Mar",4:"Apr",5:"Maj",6:"Jun",7:"Jul",8:"Aug"};
function amount(v:unknown){return typeof v==="number"&&Number.isFinite(v)?fmt.format(v):"Underlag saknas";}
export default async function EconomyHome({searchParams}:{searchParams:Promise<{fiscal_year?:string;months?:string;cost_center?:string}>}){
 const db=await createClient();const {data:{user}}=await db.auth.getUser();if(!user)redirect("/kpi/ekonomi/login");
 const {data:member}=await db.from("hub_tenant_members").select("tenant_id,display_name,role")
  .eq("user_id",user.id).eq("status","active").limit(1).maybeSingle();
 if(!member)return <main className={styles.page}><h1>Ingen aktiv arbetsyta</h1><p>Du behöver kopplas till Elleholms organisation av en administratör.</p></main>;
 const {data:allowed}=await db.rpc("hub_has_permission",{p_tenant_id:member.tenant_id,p_permission:"kpi.read"});
 if(!allowed||!["economy","admin","owner"].includes(member.role??""))return <main className={styles.page}><h1>Behörighet saknas</h1><p>Din roll saknar åtkomst till ekonomiavdelningens vy. Be administratören tilldela rollen Ekonomi.</p><Link href="/kpi">Till KPI</Link></main>;
 const {data:tenant}=await db.from("hub_tenants").select("name").eq("id",member.tenant_id).maybeSingle();
 const query=await searchParams;const today=stockholmToday();
 let period;
 try{period=parseMonthPeriod(query.fiscal_year,query.months);}
 catch{return <main className={styles.page}><h1>Ogiltigt periodurval</h1><Link href="/kpi/ekonomi">Återställ</Link></main>;}
 const center=query.cost_center?.trim()??"";
 if(center&&!["10","20","30","40","50","60","90"].includes(center))return <main className={styles.page}><h1>Ogiltigt kostnadsställe</h1><Link href="/kpi/ekonomi">Återställ</Link></main>;
 const from=`${period.fiscalYear}-09-01`,to=`${period.fiscalYear+1}-08-31`;
 const filters:Record<string,string|number|number[]>={fiscal_year:period.fiscalYear,selected_months:period.months};
 if(center)filters.cost_center=center;
 const {data,error}=await db.rpc("hub_kpi_analysis_months_v1",{p_tenant_id:member.tenant_id,p_from:from,p_to:to,p_filters:filters,p_level:"group",p_grain:"month",p_page:0});
 const report=error||!data?null:data as Analysis;
 const params=new URLSearchParams(monthPeriodQuery(period));if(center)params.set("cost_center",center);
 params.set("level","group");params.set("grain","month");
 return <main className={styles.page}>
  <header className={styles.top}>
   <div><span className={styles.kicker}>HUMLA · EKONOMI</span><h1>Ekonomisk uppföljning</h1><p>{tenant?.name??"Organisation"} · {member.display_name??user.email}</p></div>
   <form action={economyLogout}><button className={styles.secondary}>Logga ut</button></form>
  </header>
  <nav className={styles.shortcuts} aria-label="Ekonomiska rapporter">
   <Link href="/kpi">KPI-dashboard</Link><Link href="/kpi/projekt">Projektuppföljning</Link>
   <Link href={`/kpi/analys?from=${from}&to=${to}&level=group`}>Detaljanalys</Link>
  </nav>
  <form method="get" className={styles.filters}>
   <label>Verksamhetsår<select name="fiscal_year" defaultValue={period.fiscalYear}>
    {[today.year-2,today.year-1,today.year,today.year+1].map(y=><option key={y} value={y}>{y}/{y+1}</option>)}
   </select></label>
   <label>Kostnadsställe<select name="cost_center" defaultValue={center}>
    <option value="">Alla</option><option value="20">20 · Sortergård</option><option value="30">30 · Transport</option><option value="40">40 · Verkstad</option><option value="90">90 · Övrigt</option>
   </select></label>
   <label>Månader<select name="months" defaultValue={query.months??""}>
    <option value="">Hela verksamhetsåret</option>
    {fiscalMonths.map(m=><option key={m} value={m}>{monthNames[m]}</option>)}
   </select></label><button type="submit">Uppdatera</button>
  </form>
  {error||!report?<section className={styles.warning} role="alert"><h2>Ekonomiska data kunde inte läsas</h2>
    <p>Inga belopp visas när rapportunderlaget saknas eller är otillgängligt. Kontrollera Hubbles rapport och dina behörigheter.</p></section>:
   <>
    <section className={styles.metrics} aria-label="KPI-tal">
     <article><span>Omsättning</span><strong>{amount(report.summary?.revenue)}</strong></article>
     <article><span>Kostnader</span><strong>{amount(report.summary?.cost)}</strong></article>
     <article><span>Resultat</span><strong>{amount(report.summary?.result)}</strong></article>
     <article><span>Transaktionsrader i urvalet</span><strong>{integer.format(report.transactions?.length??0)}</strong><small>Visade underlagsrader, inte hela resultatets antal</small></article>
    </section>
    <section className={styles.panel}><div className={styles.heading}><div><h2>Månadsutfall</h2><p>{period.months.map(m=>monthNames[m]).join(", ")} · {period.fiscalYear}/{period.fiscalYear+1}</p></div></div>
     <div className={styles.tableWrap}><table><thead><tr><th>Period</th><th>Intäkt</th><th>Kostnad</th><th>Resultat</th></tr></thead><tbody>
       {(report.periods??[]).map((p,i)=><tr key={p.period_start+"-"+i}><td>{p.period_start}</td><td>{amount(p.revenue)}</td><td>{amount(p.cost)}</td><td>{amount(p.result)}</td></tr>)}
      </tbody></table>{!report.periods?.length&&<p>Inget verifierat månadsunderlag finns för urvalet.</p>}</div>
    </section>
    <section className={styles.panel}><h2>Hämta KPI-underlag</h2>
      <p>Exporterna använder Hubbles befintliga spårbara analyser. Data omfattar endast den valda perioden och kostnadsstället.</p>
      <div className={styles.shortcuts}><a href={`/api/kpi/export?${params.toString()}&format=xlsx`}>Hämta Excel</a><a href={`/api/kpi/export?${params.toString()}&format=pdf`}>Hämta PDF</a><Link href={`/kpi/analys?${params.toString()}`}>Granska underlag</Link></div>
      <p className={styles.note}>Siffrorna är hämtade ur Humla Hub. Ekonomiska korrigeringar, omappade konton och avstämningar ska fortfarande kontrolleras före slutligt bokslut.</p>
    </section>
   </>
  }
 </main>;
}
