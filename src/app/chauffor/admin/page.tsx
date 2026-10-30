import Link from 'next/link';
import {redirect} from 'next/navigation';
import {createClient} from '@/lib/supabase/server';
import type {DriverDirectory} from '@/lib/hub/driver-self';
import {bindDriverAccount} from './actions';
import styles from '../driver.module.css';
export const dynamic='force-dynamic';
export default async function DriverAdmin({searchParams}:{searchParams:Promise<{saved?:string}>}){
 const db=await createClient();const {data:{user}}=await db.auth.getUser();if(!user)redirect('/kpi/login');
 const {data:member}=await db.from('hub_tenant_members').select('tenant_id,role').eq('user_id',user.id).eq('status','active').maybeSingle();
 if(!member||member.role!=='owner')redirect('/chauffor');
 const {data,error}=await db.rpc('hub_driver_directory_v1',{p_tenant:member.tenant_id});const directory=data as DriverDirectory|null,q=await searchParams;
 return <section className={styles.driverPage}><Link href="/chauffor">← Min körning / förhandsvisning</Link><div className={styles.intro}><span className={styles.kicker}>ÄGARINSTÄLLNINGAR</span><h1>Chaufförernas konton</h1><p>Koppla ett befintligt chaufförskonto till rätt person i Humla. Kopplingen gäller direkt och historiken sparas.</p></div>
 {q.saved&&<p role="status">{q.saved==='yes'?'Kopplingen är sparad.':'Kopplingen kunde inte sparas. Kontrollera att personen inte redan är kopplad till ett annat konto.'}</p>}
 {error||!directory?<p role="alert">Konton och chaufförer kunde inte hämtas.</p>:<>
 <article className={styles.card}><h2>Konton med rollen medarbetare</h2>{!directory.accounts.length&&<p>Inga chaufförskonton finns ännu. Personliga användarkonton behöver först skapas och få rollen medarbetare (worker) innan de kan kopplas här. Du kan redan nu förhandsvisa chaufförernas underlag nedan.</p>}
 {directory.accounts.map(a=><div className={styles.accountRow} key={a.id}><strong>{a.name}</strong><form action={bindDriverAccount}><input type="hidden" name="account" value={a.id}/><select aria-label={'Chaufför för '+a.name} name="person" defaultValue={directory.people.find(p=>p.linked_user===a.id)?.id??''}><option value="">Ingen koppling / avsluta koppling</option>{directory.people.map(p=><option key={p.id} value={p.id} disabled={!!p.linked_user&&p.linked_user!==a.id}>{p.name}{p.linked_user&&p.linked_user!==a.id?' · redan kopplad':''}</option>)}</select><button>Spara</button></form></div>)}</article>
 <article className={styles.card}><h2>Förhandsvisa chaufförer</h2>{directory.people.map(p=><div className={styles.accountRow} key={p.id}><Link href={'/chauffor?person='+p.id}>{p.name} →</Link><small>{p.linked_user?'Konto kopplat':'Konto saknas'}</small></div>)}</article></>}
 </section>;
}
