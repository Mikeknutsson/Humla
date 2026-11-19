"use server";

import {revalidatePath} from "next/cache";
import {createClient} from "@/lib/supabase/server";
import {settlementPath} from "@/app/_components/kpi-transport-administration-nav";
import {reviewLabels} from "./review";

export async function saveReview(_previous: string, form: FormData): Promise<string> {
 const db = await createClient();
 const {data: {user}} = await db.auth.getUser();
 if (!user) return "Din session har gått ut. Logga in igen.";
 const {data: member} = await db.from("hub_tenant_members").select("tenant_id")
  .eq("user_id", user.id).eq("status","active").maybeSingle();
 if (!member) return "Aktiv arbetsyta saknas.";

 const state = String(form.get("state") ?? "");
 const note = String(form.get("note") ?? "").trim();
 const month = String(form.get("month") ?? "");
 const revision = Number(form.get("revision"));
 const page = Number(form.get("page"));
 if (!Object.hasOwn(reviewLabels,state) || note.length>1000 || !/^20\d{2}-(0[1-9]|1[0-2])$/.test(month)
    || !Number.isInteger(page) || !Number.isInteger(revision)) return "Kontrollera uppgifterna och försök igen.";
 if (state === "reviewed" && !note) return "Skriv en kort anteckning om vad du har kontrollerat.";

 const {error} = await db.rpc("hub_save_stena_review", {
  p_tenant: member.tenant_id, p_month: month+"-01", p_page: page, p_only_review: form.get("review") === "1",
  p_row_id: form.get("id"), p_fingerprint: form.get("fingerprint"), p_revision: revision, p_state: state, p_note: note,
 });
 if (error?.code === "40001") return "Raden eller underlaget har ändrats. Ladda om sidan och kontrollera den igen.";
 if (error) return "Granskningen kunde inte sparas. Försök igen.";
 revalidatePath(settlementPath);
 return "";
}
