import Link from 'next/link';
import {redirect} from 'next/navigation';
import {createClient} from '@/lib/supabase/server';
import {cachedKpiReport} from '@/lib/kpi/report-cache';
import {analysisQuery} from '@/lib/kpi/analysis';
import {EconomicUnitDetail,type EconomicUnit} from '@/app/_components/kpi-economic-units';
import {KpiDetailShell} from '@/app/_components/kpi-detail-shell';
export const dynamic='force-dynamic';
export default async function UnitPage({searchParams}:{searchParams:Promise<Record<string,string|undefined>>}){
 const raw=await searchParams,p=new URLSearchParams(Object.entries(raw).filter((v):v is [string,string]=>typeof v[1]==='string'));
 const selected=p.get('unit');if(!selected)redirect('/kpi?view=kpi');
 for(const k of ['vehicle','project','kind','category','source','page','level','grain','view'])p.delete(k);
 let args:ReturnType<typeof analysisQuery>;try{args=analysisQuery(p)}catch{return <main className="content"><h1>Välj en giltig rapportperiod</h1><Link href="/kpi?view=kpi">Till kostnadsbärare</Link></main>}
 const db=await createClient(),{data:{user}}=await db.auth.getUser();if(!user)redirect('/kpi/login');
 const {data:member}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').limit(1).maybeSingle();if(!member)return <main>Arbetsyta saknas.</main>;
 const {data:canRead}=await db.rpc('hub_has_permission',{p_tenant_id:member.tenant_id,p_permission:'kpi.read'});if(!canRead)return <main>Du saknar åtkomst till KPI-underlagen.</main>;
 const monthly=Array.isArray(args.p_filters.selected_months);
 const rpc=monthly?'hub_kpi_overview_months_v1':'hub_kpi_cost_center_dashboard_v1';
 const rpcArgs=monthly?{p_tenant_id:member.tenant_id,p_fiscal_year:args.p_filters.fiscal_year,p_selected_months:args.p_filters.selected_months,p_cost_center:p.get('cost_center'),p_filters:args.p_filters}:{p_tenant_id:member.tenant_id,p_from:args.p_from,p_to:args.p_to,p_cost_center:p.get('cost_center')};
 const {data,error}=await cachedKpiReport<{economic_units?:EconomicUnit[]}>(user.id,member.tenant_id,{report:'unit-detail',rpc,...rpcArgs},async()=>db.rpc(rpc,rpcArgs));
 const unit=data?.economic_units?.find(u=>u.key===selected);
 const back=new URLSearchParams(p);back.delete('unit');back.set('view','kpi');
 return <KpiDetailShell query={back.toString()}><div className="content" style={{maxWidth:1200,margin:'auto'}}><nav className="dashboard-report-actions"><Link prefetch={false} href={'/kpi?'+back}>← Alla kostnadsbärare</Link></nav><p>{p.get('months')?'Valda månader: '+p.get('months')+' · ':''}{args.p_from} – {args.p_to}</p>{error?<section role="alert"><h2>Underlaget kunde inte hämtas</h2><Link href={'/kpi/enhet?'+p}>Försök igen</Link></section>:unit?<EconomicUnitDetail unit={unit} query={p.toString()}/>:<section><h2>Kostnadsbäraren saknar underlag i detta urval</h2><Link href={'/kpi?'+back}>Till kostnadsbärare</Link></section>}</div></KpiDetailShell>;
}
