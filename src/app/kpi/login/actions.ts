"use server";

import { foremanWidgetReturn } from "@/lib/kpi/foreman-widget";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export async function login(formData: FormData) {
  const email = String(formData.get("email") ?? "").trim();
  const password = String(formData.get("password") ?? "");
  const returnTo = foremanWidgetReturn(formData.get("return_to"));
  const params = new URLSearchParams(returnTo ? { return_to: returnTo } : {});
  if (!email || !password) {
    params.set("error", "Fyll i e-postadress och lösenord.");
    redirect("/kpi/login?" + params);
  }
  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) {
    params.set("error", "Inloggningen misslyckades. Kontrollera uppgifterna.");
    redirect("/kpi/login?" + params);
  }
  // The new request receives the session cookie before loading the report.
  params.set("complete", "1");
  redirect("/kpi/login?" + params);
}

export async function logout() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/kpi/login");
}

// Existing accounts only; public registration stays disabled.
export async function requestAccess(formData: FormData) {
  const email = String(formData.get("email") ?? "").trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) redirect("/kpi/login/access?error=Fyll i en giltig e-postadress.");
  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithOtp({email, options: {
    shouldCreateUser: false,
    emailRedirectTo: "https://humla-humla.vercel.app/kpi/login/confirm",
  }});
  if (error && !["user_not_found", "signup_disabled"].includes(error.code ?? "")) {
    redirect("/kpi/login/access?error=" + encodeURIComponent("Länken kunde inte skickas. Vänta en stund och försök igen. Kontakta Mike om felet kvarstår."));
  }
  redirect("/kpi/login/access?sent=1");
}

export async function setPassword(formData: FormData) {
  const password = String(formData.get("password") ?? "");
  const repeat = String(formData.get("repeat") ?? "");
  if (password.length < 12 || password !== repeat) redirect("/kpi/login/password?error=" + encodeURIComponent("Använd minst 12 tecken och skriv samma lösenord i båda fälten."));
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/kpi/login/access");
  const { error } = await supabase.auth.updateUser({ password });
  if (error) redirect("/kpi/login/password?error=" + encodeURIComponent("Lösenordet kunde inte sparas. Välj ett annat lösenord eller begär en ny inloggningslänk."));
  redirect("/kpi");
}
