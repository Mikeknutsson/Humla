import { createClient } from '@/lib/supabase/server';
import { unitPayload } from '@/lib/kpi/units';
import { revalidateTag } from 'next/cache';

async function save(request: Request, edit: boolean) {
 const db = await createClient();
 const {data:{user}} = await db.auth.getUser();
 if (!user) return Response.json({error:'Inloggning krävs.'},{status:401});
 const {data:member} = await db.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').limit(1).maybeSingle();
 if (!member) return Response.json({error:'Arbetsyta saknas.'},{status:403});
 const {data:allowed} = await db.rpc('hub_has_permission',{p_tenant_id:member.tenant_id,p_permission:'kpi.manage'});
 if (!allowed) return Response.json({error:'KPI-administratör krävs.'},{status:403});
 try {
  const body = await request.json();
  const payload = unitPayload(body);
  if (edit && (!/^[0-9a-f-]{36}$/i.test(body.id ?? '') || !Number.isInteger(body.revision))) throw new Error('Ogiltig enhet eller version.');
  const {data,error} = await db.rpc('hub_kpi_save_unit_v2',{p_tenant_id:member.tenant_id,p_payload:payload,p_unit_id:edit?body.id:null,p_revision:edit?body.revision:null});
  if (error) return Response.json({error:error.message},{status:400});
  if (!data) return Response.json({error:'Enheten har ändrats. Ladda om sidan innan du sparar.'},{status:409});
  revalidateTag(`kpi-report:${user.id}`,{expire:0});
  return Response.json({id:data});
 } catch(error) {return Response.json({error:error instanceof Error ? error.message : 'Ogiltiga uppgifter.'},{status:400});}
}
export const POST=(request:Request)=>save(request,false);
export const PATCH=(request:Request)=>save(request,true);

export async function GET(){
 const db=await createClient();const {data:{user}}=await db.auth.getUser();if(!user)return Response.json({error:'Inloggning krävs'},{status:401});
 const {data:m}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').limit(1).maybeSingle();if(!m)return Response.json({error:'Arbetsyta saknas'},{status:403});
 const {data,error}=await db.rpc('hub_kpi_admin_unit_builder_v2',{p_tenant_id:m.tenant_id});if(error)return Response.json({error:'Objektregistret kunde inte läsas'},{status:403});
 const [{data:units,error:unitError},{data:periods,error:periodError},{data:setup,error:setupError},{data:groups,error:groupError}]=await Promise.all([
 db.from('kpi_units').select('id,name,unit_type,projects,registrations,employees,valid_from,valid_to,enabled,revision').eq('tenant_id',m.tenant_id).in('origin',['manual','manual_builder']).order('name'),
 db.from('kpi_unit_periods').select('unit_id,valid_from,valid_to,payload').eq('tenant_id',m.tenant_id).order('valid_from',{ascending:false}),
 db.from('kpi_unit_initial_setup').select('unit_id,locked_at').eq('tenant_id',m.tenant_id),
 db.from('kpi_business_groups').select('id,name').eq('tenant_id',m.tenant_id).eq('enabled',true).order('name')
 ]);
 if(unitError||periodError||setupError||groupError)return Response.json({error:'Enheter och historik kunde inte läsas'},{status:500});
 return Response.json({...data,groups:groups??[],units:(units??[]).map(u=>{const versions=periods?.filter(p=>p.unit_id===u.id)??[];const latest=versions[0];const first=versions.at(-1);const state=setup?.find(s=>s.unit_id===u.id);return {...u,initial_version:first?{...first.payload,valid_from:first.valid_from,valid_to:first.valid_to}:null,setup_open:!!state&&state.locked_at===null,setup_locked_at:state?.locked_at??null,business_group_id:latest?.payload?.business_group_id??'',valid_from:latest?.valid_from??u.valid_from,valid_to:latest?latest.valid_to:u.valid_to,main_vehicle:latest?.payload?.main_vehicle??u.registrations[0]??'',periods:(periods??[]).filter(p=>p.unit_id===u.id).map(p=>({valid_from:p.valid_from,valid_to:p.valid_to}))}})},{headers:{'Cache-Control':'private, no-store'}});
}

