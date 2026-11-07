import {createClient} from '@/lib/supabase/server';

export const dynamic = 'force-dynamic';

async function context() {
 const db = await createClient();
 const {data: {user}} = await db.auth.getUser();
 if (!user) return {error: Response.json({error: 'Inloggning krävs'}, {status: 401})};
 const {data: member} = await db.from('hub_tenant_members').select('tenant_id')
  .eq('user_id', user.id).eq('status', 'active').limit(1).maybeSingle();
 if (!member) return {error: Response.json({error: 'Aktiv arbetsyta saknas'}, {status: 403})};
 return {db, tenant: member.tenant_id};
}

export async function GET(request: Request) {
 const ctx = await context();
 if (ctx.error) return ctx.error;
 const query = new URL(request.url).searchParams;
 const {data, error} = await ctx.db.rpc('hub_kpi_allocation_review_v1', {
  p_tenant_id: ctx.tenant,
  p_from: query.get('from'),
  p_to: query.get('to'),
  p_page: Number(query.get('page') ?? 0),
 });
 if (error) return Response.json({error: error.message}, {status: error.code === '42501' ? 403 : 400});
 return Response.json(data, {headers: {'Cache-Control': 'no-store'}});
}

export async function POST(request: Request) {
 const ctx = await context();
 if (ctx.error) return ctx.error;
 const body = await request.json().catch(() => null);
 if (!body || typeof body.generation !== 'string' || typeof body.fact !== 'string') {
  return Response.json({error: 'Välj enhet och kontrollera underlaget'}, {status: 400});
 }
 if (body.action === 'assess') {
  const {data, error} = await ctx.db.rpc('hub_kpi_assess_review_unit_v1', {
   p_tenant_id: ctx.tenant,
   p_generation: body.generation,
   p_fact_id: body.fact,
  });
  if (error) return Response.json({error: error.message}, {status: error.code === '42501' ? 403 : 409});
  return Response.json(data);
 }
 if (typeof body.unit !== 'string' || typeof body.remember !== 'boolean') {
  return Response.json({error: 'Välj en ekonomisk enhet'}, {status: 400});
 }
 const {data, error} = await ctx.db.rpc('hub_kpi_confirm_review_unit_v1', {
  p_tenant_id: ctx.tenant,
  p_generation: body.generation,
  p_fact_id: body.fact,
  p_unit_id: body.unit,
  p_remember_project: body.remember,
 });
 if (error) return Response.json({error: error.message}, {status: error.code === '42501' ? 403 : 409});
 const {error: syncError} = await ctx.db.rpc('hub_kpi_request_report_sync_v1', {p_tenant_id: ctx.tenant});
 return Response.json({...data, queued: !syncError});
}
