import { redirect } from "next/navigation";
import { BarChart3, LockKeyhole } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { login, logout } from "./actions";
import { LoginSubmit } from "./login-submit";

export const dynamic = "force-dynamic";

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ error?: string; stay?: string; complete?: string }> }) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  const { error, stay } = await searchParams;
  if (user && stay !== "1" && !error) redirect("/kpi");
  if (user && stay === "1") return <div className="kpi-app"><main className="session-page"><section><span className="section-kicker">Aktiv KPI-session</span><h1>Du är inloggad</h1><p>Sessionen fungerar, men KPI-arbetsytan kunde inte öppnas. Logga ut och in igen efter att felet är åtgärdat.</p><form action={logout}><button className="primary" type="submit">Logga ut</button></form><a href="/kpi">Försök öppna KPI igen</a></section></main></div>;
  return <div className="kpi-app"><main className="login-page"><section className="login-brand"><div className="login-logo">H</div><div><span>Humla</span><strong>KPI</strong></div><h1>Styr transportverksamheten med fakta.</h1><p>Ekonomi, fordon och chaufförstid samlat i en spårbar och rollstyrd arbetsyta.</p><div className="login-points"><div><BarChart3 size={18}/>Sex beslutade transport-KPI:er</div><div><LockKeyhole size={18}/>Egen säker KPI-arbetsyta</div></div></section><section className="login-form-wrap"><form action={login} className="login-form"><span className="section-kicker">KPI-inloggning</span><h2>Välkommen tillbaka</h2><p>Logga in direkt i KPI-appen.</p>{error && <div className="login-error">{error}</div>}<label>E-postadress<input name="email" type="email" autoComplete="email" required/></label><label>Lösenord<input name="password" type="password" autoComplete="current-password" required/></label><LoginSubmit/><small>Åtkomst och data begränsas av din KPI-behörighet.</small></form></section></main></div>;
}
