"use server";
import {redirect} from "next/navigation";
import {revalidatePath} from "next/cache";
import {createClient} from "@/lib/supabase/server";

const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DATE=/^\d{4}-\d{2}-\d{2}$/;

export async function assignTransportUnit(form:FormData){
 const db=await createClient(),{data:{user}}=await db.auth.getUser();
 if(!user)redirect("/kpi/login");
 const {data:owner}=await db.from("hub_tenant_members").select("tenant_id,role").eq("user_id",user.id).eq("status","active").limit(1).maybeSingle();
 if(!owner||owner.role!=="owner")redirect("/kpi/transport-styrning/admin?result=forbidden");
 const assignee=String(form.get("user_id")??""),unit=String(form.get("unit_id")??"");
 const from=String(form.get("valid_from")??"");
 const to=String(form.get("valid_to")??"");
 if(!UUID.test(assignee)||!UUID.test(unit)||!DATE.test(from)||(to&&!DATE.test(to))||(to&&to<from))
  redirect("/kpi/transport-styrning/admin?result=invalid");
 const [{data:target},{data:resource}]=await Promise.all([
  db.from("hub_tenant_members").select("user_id").eq("tenant_id",owner.tenant_id).eq("user_id",assignee).eq("status","active").maybeSingle(),
  db.from("kpi_units").select("id").eq("tenant_id",owner.tenant_id).eq("id",unit).eq("enabled",true).maybeSingle(),
 ]);
 if(!target||!resource)redirect("/kpi/transport-styrning/admin?result=invalid");
 const {error}=await db.from("hub_transport_leader_units").insert({
  tenant_id:owner.tenant_id,user_id:assignee,unit_id:unit,
  valid_from:from,valid_to:to||null,assigned_by:user.id,
 });
 if(error)redirect("/kpi/transport-styrning/admin?result=failed");
 revalidatePath("/kpi/transport-styrning");
 revalidatePath("/kpi/transport-styrning/admin");
 redirect("/kpi/transport-styrning/admin?result=created");
}

export async function closeTransportUnitAssignment(form:FormData){
 const db=await createClient(),{data:{user}}=await db.auth.getUser();
 if(!user)redirect("/kpi/login");
 const {data:owner}=await db.from("hub_tenant_members").select("tenant_id,role").eq("user_id",user.id).eq("status","active").limit(1).maybeSingle();
 if(!owner||owner.role!=="owner")redirect("/kpi/transport-styrning/admin?result=forbidden");
 const id=String(form.get("assignment_id")??""),end=String(form.get("valid_to")??"");
 if(!UUID.test(id)||!DATE.test(end))redirect("/kpi/transport-styrning/admin?result=invalid");
 const {data:existing}=await db.from("hub_transport_leader_units").select("id,valid_from")
  .eq("tenant_id",owner.tenant_id).eq("id",id).maybeSingle();
 if(!existing||end<existing.valid_from)redirect("/kpi/transport-styrning/admin?result=invalid");
 const {error}=await db.from("hub_transport_leader_units").update({valid_to:end}).eq("tenant_id",owner.tenant_id).eq("id",id);
 if(error)redirect("/kpi/transport-styrning/admin?result=failed");
 revalidatePath("/kpi/transport-styrning");
 revalidatePath("/kpi/transport-styrning/admin");
 redirect("/kpi/transport-styrning/admin?result=closed");
}
