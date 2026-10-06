import {createClient} from '@/lib/supabase/server';
import {internalQuery,transferWorkbook,transferGroups,transferTotals,finishedRows,type InternalRow} from '@/lib/kpi/internal-transfers';
export const runtime='nodejs';export const maxDuration=60;
async function context(){const db=await createClient();const {data:{user}}=await db.auth.getUser();if(!user)return null;const {data:m}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').limit(1).maybeSingle();return m?{db,tenant:m.tenant_id}:null;}
const headers={'Cache-Control':'private, no-store'};
function download(rows:InternalRow[],id:string,report=false,includeReview=false){return new Response(new Uint8Array(transferWorkbook(rows,id,report,includeReview)),{headers:{...headers,'Content-Type':'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','Content-Disposition':`attachment; filename="humla-interna-${id}.xlsx"`,'X-Export-ID':id}});}
export async function GET(req:Request){
 const ctx=await context();if(!ctx)return Response.json({error:'Inloggning och arbetsyta krävs'},{status:401});
 try{const p=new URL(req.url).searchParams;
  if(p.has('export_id')){const id=p.get('export_id')!;if(!/^[0-9a-f-]{36}$/i.test(id))throw Error('Ogiltigt export-ID');const {data,error}=await ctx.db.from('kpi_internal_transfer_ledger').select('snapshot').eq('tenant_id',ctx.tenant).eq('export_id',id).limit(2001);if(error||!data?.length) return Response.json({error:'Export saknas eller åtkomst nekad'},{status:404});if(data.length>2000)throw Error('Exportgränsen överskreds');return download(data.map(r=>r.snapshot as InternalRow),id);}
  const {data,error}=await ctx.db.rpc('hub_kpi_internal_transfers_with_purchase_v1',{p_tenant_id:ctx.tenant,...internalQuery(p)});
  if(error)return Response.json({error:'Underlaget kunde inte läsas. Kontrollera period och KPI-behörighet.'},{status:403});
  for(const key of ['from_center','to_center'])if(p.has(key)&&!['10','20','30','40','50','60','90'].includes(p.get(key)!))throw Error('Invalid center');
  const filteredRows=(data.rows as InternalRow[]).filter(r=>(!p.get('from_center')||r.receiver_center===p.get('from_center'))&&(!p.get('to_center')||r.source_center===p.get('to_center')));
  if(p.get('download')==='purchase'){
   const rows=filteredRows.filter(r=>!p.get('cost_center')||r.source_center===p.get('cost_center')||r.receiver_center===p.get('cost_center'));
   return download(rows,`inkopsunderlag-${p.get('from')}-${p.get('to')}`,true,true);
  }
  if(p.get('download')==='report'){
   const rows=finishedRows(filteredRows,p.get('cost_center')??undefined);
   if(!rows.length)return Response.json({error:'Inga färdiga rader finns i urvalet.'},{status:400});
   return download(rows,`rapport-${p.get('from')}-${p.get('to')}-${Date.now()}`,true);
  }
  const groups=transferGroups(filteredRows);
  const centers=[...new Set(groups.flatMap(g=>[g.source_center,g.receiver_center]).filter((c):c is string=>c!==null))];
  return Response.json({...data,rows:filteredRows,count:filteredRows.length,groups,totals:transferTotals(groups),totals_by_center:Object.fromEntries(centers.map(c=>[c,transferTotals(groups,c)]))},{headers});
 }catch{return Response.json({error:'Ogiltigt urval. Välj högst ett verksamhetsår.'},{status:400});}
}
export async function POST(req:Request){
 if(req.headers.get('origin')!==new URL(req.url).origin)return Response.json({error:'Otillåten begäran'},{status:403});
 const ctx=await context();if(!ctx)return Response.json({error:'Inloggning och arbetsyta krävs'},{status:401});
 try{const body=await req.json();if(!['export','posted'].includes(body.action))throw Error('Invalid action');
  const args=body.action==='export'?{...internalQuery(new URLSearchParams(body.period)),p_keys:body.keys}:{p_export_id:body.export_id,p_reference:body.reference};
  if(body.action==='export'&&(!Array.isArray(body.keys)||body.keys.length<1||body.keys.length>2000||body.keys.some((k:unknown)=>typeof k!=='string')))throw Error('Invalid keys');
  if(body.action==='posted'&&(typeof body.reference!=='string'||typeof body.export_id!=='string'))throw Error('Invalid booking');
  const {data,error}=await ctx.db.rpc('hub_kpi_internal_transfer_action_v1',{p_tenant_id:ctx.tenant,p_action:body.action,...args});
  if(error)return Response.json({error:'Åtgärden avvisades. Uppdatera urvalet; rader måste vara granskade, inte tidigare exporterade, och du behöver kpi.manage.'},{status:409});
  return body.action==='export'?download(data.rows,data.export_id):Response.json(data,{headers});
 }catch{return Response.json({error:'Ogiltig åtgärd eller period.'},{status:400});}
}
