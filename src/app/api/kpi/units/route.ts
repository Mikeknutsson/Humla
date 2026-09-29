import { createClient } from '@/lib/supabase/server';
import { unitPayload } from '@/lib/kpi/units';

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
  const query = edit ? db.from('kpi_units').update(payload).eq('tenant_id',member.tenant_id).eq('id',body.id).eq('revision',body.revision)
   : db.from('kpi_units').insert({...payload,tenant_id:member.tenant_id});
  const {data,error} = await query.select('id').maybeSingle();
  if (error) return Response.json({error:'Enheten kunde inte sparas.'},{status:400});
  if (!data) return Response.json({error:'Enheten har ändrats. Ladda om sidan innan du sparar.'},{status:409});
  return Response.json({id:data.id});
 } catch(error) {return Response.json({error:error instanceof Error ? error.message : 'Ogiltiga uppgifter.'},{status:400});}
}
export const POST=(request:Request)=>save(request,false);
export const PATCH=(request:Request)=>save(request,true);
