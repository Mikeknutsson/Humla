import { requestAccess } from '../actions';
export default async function AccessPage({searchParams}:{searchParams:Promise<{error?:string;sent?:string}>}) {
 const {error,sent}=await searchParams;
 return <div className="kpi-app"><main className="login-page"><section className="login-form-wrap"><form action={requestAccess} className="login-form"><span className="section-kicker">Humla · arbetsledare</span><h1>Kom igång med ditt konto</h1><p>Använd din registrerade jobbmejl. Via inloggningslänken väljer du ditt eget lösenord.</p>{error&&<p role="alert" className="login-error">{error}</p>}{sent&&<p role="status">Om adressen har ett konto har en länk skickats. Kontrollera även skräpposten. Öppna länken i samma webbläsare som du använder här.</p>}<label>E-postadress<input type="email" name="email" autoComplete="email" required/></label><button className="primary" type="submit">Skicka inloggningslänk</button><a href="/kpi/login">Tillbaka till inloggningen</a></form></section></main></div>;
}
