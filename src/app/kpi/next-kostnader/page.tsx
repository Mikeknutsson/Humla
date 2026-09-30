import Link from "next/link";
import {redirect} from "next/navigation";
import {createClient} from "@/lib/supabase/server";
export const dynamic="force-dynamic";
const money=(n:number)=>new Intl.NumberFormat("sv-SE",{style:"currency",currency:"SEK",maximumFractionDigits:0}).format(n);
type Cost={id:string;occurred_on:string;amount:number;account:string|null;description:string|null;allocation:{allocation_type?:string;allocation_reference?:string;allocation_status?:string}|null;source_data:Record<string,unknown>|null};
export default async function NextCosts({searchParams}:{searchParams:Promise<{from?:string;to?:string}>}){
 const db=await createClient();const {data:{user}}=await db.auth.getUser();if(!user)redirect("/kpi/login");
 const {data:member}=await db.from("hub_tenant_members").select("tenant_id").eq("user_id",user.id).eq("status","active").limit(1).maybeSingle();
 if(!member)return <main style={{padding:28}}>Ingen aktiv arbetsyta.</main>;
 const {data:allowed}=await db.rpc("hub_has_permission",{p_tenant_id:member.tenant_id,p_permission:"kpi.read"});if(!allowed)return <main style={{padding:28}}>Behörighet saknas.</main>;
 const q=await searchParams;const now=new Date(),y=now.getUTCMonth()<8?now.getUTCFullYear()-1:now.getUTCFullYear();
 const from=/^\d{4}-\d{2}-\d{2}$/.test(q.from??"")?q.from!:`${y}-09-01`,to=/^\d{4}-\d{2}-\d{2}$/.test(q.to??"")?q.to!:`${y+1}-08-31`;
 const rows:Cost[]=[];let error="";
 for(let start=0;start<50000;start+=900){const res=await db.from("kpi_import_rows").select("id,occurred_on,amount,account,description,allocation,source_data").eq("tenant_id",member.tenant_id).eq("data_kind","cost").gte("occurred_on",from).lte("occurred_on",to).order("id").range(start,start+899);
 if(res.error){error=res.error.message;break;}rows.push(...(res.data??[]) as Cost[]);if((res.data??[]).length<900)break;}
 const refs=[...new Set(rows.map(r=>r.allocation?.allocation_reference).filter((v):v is string=>Boolean(v)))];
 const mapping=new Map<string,string[]>();for(let i=0;i<refs.length;i+=100){const res=await db.from("kpi_project_unit_mappings").select("project_reference,vehicle_registration").eq("tenant_id",member.tenant_id).eq("enabled",true).in("project_reference",refs.slice(i,i+100));if(res.error){error=res.error.message;break;}for(const m of res.data??[]){const regs=mapping.get(m.project_reference)??[];const reg=String(m.vehicle_registration??"").trim().toUpperCase();if(reg&&!regs.includes(reg))regs.push(reg);mapping.set(m.project_reference,regs);}}
 const groups=new Map<string,{amount:number;count:number;accounts:Map<string,{amount:number;count:number;rows:Cost[]}>}>();
 let confident=0,review=0,confidentAmount=0,reviewAmount=0;
 for(const r of rows){const ref=r.allocation?.allocation_reference;const regs=ref?mapping.get(ref)??[]:[];const isVehicle=regs.length===1&&r.allocation?.allocation_status==="identified";const label=isVehicle?`${regs[0]} · ${ref}`:ref?`Granska: projekt ${ref}`:"Granska: saknar objekt";if(isVehicle){confident++;confidentAmount+=Number(r.amount);}else{review++;reviewAmount+=Number(r.amount);}
 const g=groups.get(label)??{amount:0,count:0,accounts:new Map()};g.amount+=Number(r.amount);g.count++;const a=String(r.account??"Utan konto");const ag=g.accounts.get(a)??{amount:0,count:0,rows:[]};ag.amount+=Number(r.amount);ag.count++;ag.rows.push(r);g.accounts.set(a,ag);groups.set(label,g);}
 return <main style={{maxWidth:1280,margin:"auto",padding:"26px 20px"}}><Link href={`/kpi?from=${from}&to=${to}`}>← Dashboard</Link><h1>Alla kostnader från NEXT</h1><p>Alla importerade kostnadskonton. Automatisk fordonskoppling föreslås vid entydig, registrerad projektkoppling. Förslagen innebär inte att varje faktura är verifierad. Beloppen redovisas separat och läggs inte till en andra gång i KPI-resultatet.</p>
 <form style={{display:"flex",gap:12,flexWrap:"wrap",alignItems:"end",margin:"20px 0"}}><label>Från<br/><input type="date" name="from" defaultValue={from}/></label><label>Till<br/><input type="date" name="to" defaultValue={to}/></label><button>Visa</button></form>
 {error&&<p style={{color:"darkred"}}>Ofullständigt underlag: {error}</p>}
 <div style={{display:"flex",gap:32,flexWrap:"wrap",margin:"24px 0"}}><div><strong>Totala NEXT-kostnader</strong><h2>{money(confidentAmount+reviewAmount)}</h2><small>{rows.length} rader</small></div><div><strong>Entydig projekt-/fordonskoppling</strong><h2>{money(confidentAmount)}</h2><small>{confident} rader, föreslagen mappning</small></div><div><strong>Granska koppling</strong><h2>{money(reviewAmount)}</h2><small>{review} rader</small></div></div>
 <h2>Kostnader per objekt och konto</h2>{[...groups].sort((a,b)=>b[1].amount-a[1].amount).map(([name,g])=><details key={name} style={{borderTop:"1px solid #bbb",padding:"12px 0"}}><summary style={{cursor:"pointer",fontWeight:600}}>{name} — {money(g.amount)} ({g.count} rader)</summary><div style={{padding:"8px 14px"}}>{[...g.accounts].sort((a,b)=>b[1].amount-a[1].amount).map(([account,a])=><details key={account} style={{borderTop:"1px solid #ddd",padding:8}}><summary style={{cursor:"pointer"}}>Konto {account} — {money(a.amount)} ({a.count})</summary>{a.rows.sort((x,y)=>y.occurred_on.localeCompare(x.occurred_on)).map(r=><div key={r.id} style={{padding:6,fontSize:13,borderTop:"1px solid #eee"}}>{r.occurred_on} · {r.description??"Kostnad"} · {money(Number(r.amount))}</div>)}</details>)}</div></details>)}
 </main>;
}