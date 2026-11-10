import {redirect} from 'next/navigation';
import {createClient} from '@/lib/supabase/server';
import {setPassword} from '../actions';
export default async function PasswordPage({searchParams}:{searchParams:Promise<{error?:string}>}) {
 const supabase=await createClient();const {data:{user}}=await supabase.auth.getUser();
 if(!user)redirect('/kpi/login/access');
 const {error}=await searchParams;
 return <div className="kpi-app"><main className="login-page"><section className="login-form-wrap"><form action={setPassword} className="login-form"><h1>Välj ditt lösenord</h1><p>{user.email} · Minst 12 tecken.</p>{error&&<p role="alert" className="login-error">{error}</p>}<label>Nytt lösenord<input name="password" type="password" autoComplete="new-password" minLength={12} required/></label><label>Upprepa lösenord<input name="repeat" type="password" autoComplete="new-password" minLength={12} required/></label><button className="primary" type="submit">Spara och öppna min vy</button></form></section></main></div>;
}
