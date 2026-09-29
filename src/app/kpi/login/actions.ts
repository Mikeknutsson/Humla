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
