import {redirect} from 'next/navigation';
import {createClient} from '@/lib/supabase/server';
import {KpiDetailShell} from '@/app/_components/kpi-detail-shell';
import {AssetTcoWorkspace} from '@/app/_components/asset-tco-workspace';
import type {AssetTcoReport} from '@/lib/hub/asset-tco';
export const dynamic='force-dynamic';
export default async function Page({searchParams}:{searchParams:Promise<{asset?:string;date?:string}>}){
 const db=await createClient();const {data:{user}}=await db.auth.getUser();if(!user)redirect('/kpi/login');
 const {data:member}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').limit(1).maybeSingle();if(!member)redirect('/kpi');
 const q=await searchParams;const today=new Intl.DateTimeFormat('sv-SE',{timeZone:'Europe/Stockholm'}).format(new Date());
 const asOf=/^\d{4}-\d{2}-\d{2}$/.test(q.date??'')?q.date!:today;
 const asset=q.asset&&/^[0-9a-f-]{36}$/i.test(q.asset)?q.asset:null;
 const {data,error}=await db.rpc('hub_asset_tco_v1',{p_tenant_id:member.tenant_id,p_as_of:asOf,p_asset:asset});
 return <KpiDetailShell query="" title="Fordon & TCO" breadcrumb="Humla / Fordonsansvarig"><div className="content">{error?<section className="panel"><h2>Fordonsvyn kunde inte öppnas</h2><p role="alert">{error.code==='42501'?'Du behöver behörigheten Visa fordonskostnader och TCO.':'Kontrollera datumet och försök igen.'}</p></section>:<AssetTcoWorkspace report={data as AssetTcoReport} selectedId={asset} today={today}/>}</div></KpiDetailShell>;
}
