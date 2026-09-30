import {redirect} from "next/navigation";import {createClient} from "@/lib/supabase/server";
export default async function Layout({children}:{children:React.ReactNode}){
 const s=await createClient();const {data:{user}}=await s.auth.getUser();if(!user)redirect("/kpi/login");
 const {data:m}=await s.from("hub_tenant_members").select("tenant_id").eq("user_id",user.id).eq("status","active").maybeSingle();
 if(!m)return <main className="access-denied">Ingen aktiv organisation.</main>;
 const {data:allowed}=await s.rpc("hub_has_permission",{p_tenant_id:m.tenant_id,p_permission:"kpi.manage"});
 if(!allowed)return <main className="access-denied">Administratörsbehörighet krävs för Kontrollpanelen.</main>;
 return children;
}