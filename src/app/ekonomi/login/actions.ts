"use server";
import {redirect} from "next/navigation";
import {createClient} from "@/lib/supabase/server";
export async function economyLogin(form:FormData){
 const email=String(form.get("email")??"").trim(),password=String(form.get("password")??"");
 if(!email||!password) redirect("/ekonomi/login?error=missing");
 const db=await createClient();
 const {error}=await db.auth.signInWithPassword({email,password});
 if(error) redirect("/ekonomi/login?error=invalid");
 redirect("/ekonomi");
}
export async function economyLogout(){
 const db=await createClient();
 await db.auth.signOut();
 redirect("/ekonomi/login");
}
