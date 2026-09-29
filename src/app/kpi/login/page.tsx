import { redirect } from "next/navigation";
import { BarChart3, LockKeyhole } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { login } from "./actions";

export const dynamic = "force-dynamic";

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (user) redirect("/kpi");
  const { error } = await searchParams;
  return <div className="kpi-app"><main className="login-page"><section className="login-brand"><div className="login-logo">H</div><div><span>Humla</span><strong>KPI</strong></div><h1>Styr transportverksamheten med fakta.</h1><p>Ekonomi, fordon och chaufförstid samlat i en spårbar och rollstyrd arbetsyta.</p><div className="login-points"><div><BarChart3 size={18}/>Sex beslutade transport-KPI:er</div><div><LockKeyhole size={18}/>Tenantseparerad och behörighetsstyrd</div></div></section><section className="login-form-wrap"><form action={login} className="login-form"><span className="section-kicker">Säker inloggning</span><h2>Välkommen tillbaka</h2><p>Logga in med ditt Humla-konto.</p>{error && <div className="login-error">{error}</div>}<label>E-postadress<input name="email" type="email" autoComplete="email" required/></label><label>Lösenord<input name="password" type="password" autoComplete="current-password" required/></label><button className="primary" type="submit">Logga in</button><small>Åtkomst och data begränsas av din roll i Humla.</small></form></section></main></div>;
}
