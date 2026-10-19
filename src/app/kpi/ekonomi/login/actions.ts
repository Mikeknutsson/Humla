"use server";
import {redirect} from "next/navigation";
import {createClient} from "@/lib/supabase/server";
export async function economyLogin(form:FormData){
 const email=String(form.get("email")??"").trim(),password=String(form.get("password")??"");
 if(!email||!password) redirect("/kpi/ekonomi/login?error=missing");
 const db=await createClient();
 const {error}=await db.auth.signInWithPassword({email,password});
 if(error) redirect("/kpi/ekonomi/login?error=invalid");
 redirect("/kpi/ekonomi");
}
export async function economyLogout(){
 const db=await createClient();
 await db.auth.signOut();
 redirect("/kpi/ekonomi/login");
}
