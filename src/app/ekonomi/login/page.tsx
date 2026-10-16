import Link from "next/link";
import {redirect} from "next/navigation";
import {createClient} from "@/lib/supabase/server";
import {economyLogin} from "./actions";
import styles from "../ekonomi.module.css";
export const dynamic="force-dynamic";
export default async function EconomyLogin({searchParams}:{searchParams:Promise<{error?:string}>}){
 const db=await createClient();const {data:{user}}=await db.auth.getUser();
 if(user)redirect("/ekonomi");
 const {error}=await searchParams;
 return <main className={styles.loginShell}>
  <section className={styles.loginCard}>
   <div className={styles.identity}><strong>H</strong><span>HUMLA <b>EKONOMI</b></span></div>
   <h1>Ekonomisk uppföljning</h1>
   <p>Logga in med ditt personliga Humla-konto för att hämta KPI-tal, projektuppföljning och ekonomiska underlag.</p>
   <form action={economyLogin} className={styles.loginForm}>
    <label>E-postadress<input name="email" type="email" autoComplete="username" required/></label>
    <label>Lösenord<input name="password" type="password" autoComplete="current-password" required/></label>
    {error&&<p role="alert">Inloggningen kunde inte genomföras. Kontrollera dina uppgifter.</p>}
    <button type="submit">Öppna Ekonomi</button>
   </form>
   <small>Åtkomsten är behörighetsstyrd och gäller endast organisationens data.</small>
   <Link href="/kpi/login">Till ordinarie Humla-inloggning</Link>
  </section>
 </main>;
}
