import Link from "next/link";
import {redirect} from "next/navigation";
import {BarChart3, Truck, HardHat, Wrench, ShieldCheck, Recycle, Database, ArrowUpRight} from "lucide-react";
import {createClient} from "@/lib/supabase/server";
import styles from "./portal.module.css";

export const dynamic="force-dynamic";

export default async function PortalHome(){
 const supabase=await createClient();
 const {data:{user}}=await supabase.auth.getUser();
 if(!user) redirect("/kpi/login");
 const {data:member,error:memberError}=await supabase.from("hub_tenant_members")
   .select("tenant_id,display_name,role").eq("user_id",user.id).eq("status","active").limit(1).maybeSingle();
 if(memberError || !member) return <div className={styles.portal}><header className={styles.top}><div className={styles.identity}><div className={styles.mark}>H</div><strong>Humla</strong></div></header><section className={styles.hero}><span className={styles.kicker}>Behörighet krävs</span><h1>Ingen aktiv organisation hittades</h1><p>Kontakta administratören för att få tillgång till rätt arbetsyta. Dina uppgifter visas inte utan medlemskap.</p></section><Link className={styles.hubShortcut} href="/kpi/login?stay=1">Hantera session</Link></div>;
 const [{data:tenant},{data:canReadKpi}]=await Promise.all([
  supabase.from("hub_tenants").select("name").eq("id",member.tenant_id).maybeSingle(),
  supabase.rpc("hub_has_permission",{p_tenant_id:member.tenant_id,p_permission:"kpi.read"}),
 ]);
 const modules=[
  {name:"KPI & Ekonomi",description:"Resultat, marginaler, projektuppföljning och fordonskostnader.",icon:BarChart3,href:"/kpi",enabled:canReadKpi===true},
  {name:"Transportledning",description:"Körplanering, transportorder, förare och återrapportering.",icon:Truck,href:null,enabled:false},
  {name:"Entreprenad",description:"Projekt, offertkalkyl, mängdberäkning och Next-budgetar.",icon:HardHat,href:null,enabled:false},
  {name:"Resurser",description:"Fordon, maskiner, verkstad och service.",icon:Wrench,href:null,enabled:false},
  {name:"KMA",description:"Riskbedömning, arbetsberedning, kontroller och avvikelser.",icon:ShieldCheck,href:null,enabled:false},
  {name:"Sortergård",description:"Mottagning, materialflöden, lager och mängdavstämning.",icon:Recycle,href:null,enabled:false}
 ];
 return <div className={styles.portal}>
  <header className={styles.top}>
   <div className={styles.identity}><div className={styles.mark} aria-hidden="true">H</div><div><strong>Humla</strong><span>VERKSAMHETSPORTAL</span></div></div>
   <div className={styles.user}><div className={styles.account}><strong>{member.display_name || user.email || "Användare"}</strong><span>{tenant?.name || "Arbetsyta"}</span></div><Link href="/hub" className={styles.hubShortcut}>Humla Hub <ArrowUpRight size={14} aria-hidden="true"/></Link></div>
  </header>
  <section className={styles.hero}><span className={styles.kicker}>En gemensam ingång</span><h1>Välj din arbetsyta.</h1><p>Humla samlar verksamhetens funktioner i separata moduler. Hubben hanterar gemensam data, integrationer och identiteter. Dina behörigheter styr vilka funktioner du kan öppna.</p></section>
  <section aria-labelledby="portal-modules">
   <div className={styles.sectionTitle}><h2 id="portal-modules">Verksamhetsmoduler</h2><p>Aktiva moduler går att öppna · övriga byggs stegvis</p></div>
   <div className={styles.modules}>{modules.map(m=>{
    const Icon=m.icon;
    const body=<><div className={styles.moduleHeader}><span className={styles.iconBox}><Icon size={24} aria-hidden="true"/></span><span className={m.enabled?styles.state:styles.state+" "+styles.disabledState}>{m.enabled?"Öppna":"Förbereds"}</span></div><h3 className={styles.moduleName}>{m.name}</h3><p className={styles.description}>{m.description}</p>{m.enabled&&<span className={styles.go}>Gå till arbetsyta →</span>}</>;
    return m.href&&m.enabled ? <Link href={m.href} className={styles.moduleLink} key={m.name}>{body}</Link> :
      <article className={styles.moduleDisabled} key={m.name} aria-label={m.name+": inte tillgänglig ännu"}>{body}</article>;
   })}</div>
  </section>
  <footer className={styles.footer}><span>Humla Portal · Gemensam åtkomst, separata arbetsytor.</span><span><Link href="/hub"><Database size={13} style={{verticalAlign:"middle",marginRight:6}}/>System & integrationer</Link></span></footer>
 </div>;
}
