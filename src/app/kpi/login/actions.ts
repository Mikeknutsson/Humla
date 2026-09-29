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
  redirect("/kpi");
}

export async function logout() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/kpi/login");
}
