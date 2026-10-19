import type { Metadata } from "next";
import {Suspense} from "react";
import {createClient} from "@/lib/supabase/server";
import {DashboardNavigation} from "./_components/dashboard-navigation";
import {KpiRefresh} from "../_components/kpi-refresh";

export const metadata:Metadata={title:"Humla Dashboard",description:"Ekonomi, KPI och personliga styrkort"};

export default async function KpiLayout({children}:{children:React.ReactNode}){
 const db=await createClient();
 const {data:{user}}=await db.auth.getUser();
 const {data:member}=user?await db.from("hub_tenant_members").select("tenant_id,role")
  .eq("user_id",user.id).eq("status","active").limit(1).maybeSingle():{data:null};
 const showEconomy=!!member&&["owner","admin","economy"].includes(member.role);
 const showTransport=!!member&&["owner","manager","supervisor"].includes(member.role);
 return <>
  {user&&member&&<DashboardNavigation showEconomy={showEconomy} showTransport={showTransport}/>}
  <Suspense fallback={null}><KpiRefresh/></Suspense>{children}
 </>;
}
