import { revalidateTag } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
async function handle(request: Request, mutation: boolean) {
 const db = await createClient();
 const { data: { user } } = await db.auth.getUser();
 if (!user) return Response.json({ error: 'Inloggning krävs.' }, { status: 401 });
 const { data: member } = await db.from('hub_tenant_members').select('tenant_id').eq('user_id', user.id).eq('status','active').maybeSingle();
 if (!member) return Response.json({ error: 'Aktivt företag saknas.' }, { status:403 });
 try {
  const body = mutation ? await request.json() : { action:'list' };
  if (!['list','save','end','apply'].includes(body.action)) return Response.json({error:'Ogiltig åtgärd.'},{status:400});
  const {data,error} = await db.rpc('hub_workify_name_rules_v1',{p_tenant_id:member.tenant_id,p_action:body.action,p_rule:body.rule??{}});
  if(error) return Response.json({error:error.message},{status:400});
  if (body.action === 'apply') {
   const { error: syncError } = await db.rpc('hub_kpi_request_report_sync_v1', { p_tenant_id: member.tenant_id });
   revalidateTag(`kpi-report:${user.id}`, { expire: 0 });
   if (syncError) return Response.json({ ...data, sync_warning: 'Raderna har uppdaterats, men rapportsynkningen kunde inte startas. Använd Uppdatera i KPI.' });
  }
  return Response.json(data,{headers:{'Cache-Control':'private, no-store'}});
 } catch { return Response.json({error:'Ogiltig begäran.'},{status:400}); }
}
export async function GET(request:Request){return handle(request,false);}
export async function POST(request:Request){return handle(request,true);}
