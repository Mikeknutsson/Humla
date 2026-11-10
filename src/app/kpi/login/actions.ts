"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export async function login(formData: FormData) {
  const email = String(formData.get("email") ?? "").trim();
  const password = String(formData.get("password") ?? "");
  if (!email || !password) redirect("/kpi/login?error=Fyll i e-postadress och lösenord.");
  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) redirect(`/kpi/login?error=${encodeURIComponent("Inloggningen misslyckades. Kontrollera uppgifterna.")}`);
  // Complete auth on a separate request so the refreshed session cookie is
  // available to both Auth and tenant-scoped RLS before the dashboard loads.
  redirect("/kpi/login?complete=1");
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
