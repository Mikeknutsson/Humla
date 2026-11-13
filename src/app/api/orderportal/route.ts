import {maintenanceOrders} from '@/lib/orderportal/maintenance';
import {orderAccess} from '@/lib/orderportal/server';
import {groupImports,validateOrder,type Order,type ImportRow} from '@/lib/orderportal/model';
export const dynamic='force-dynamic';
const headers={'Cache-Control':'private, no-store'};
export async function GET(request:Request){const ctx=await orderAccess();if(!ctx)return Response.json({error:'Logga in med administratörsbehörighet för testportalen.'},{status:403,headers});const {db,tenantId}=ctx;const url=new URL(request.url);const orderId=url.searchParams.get('history');if(orderId){const result=await db.from('hub_orderportal_history').select('version,created_at,actor_id,before_data,after_data').eq('tenant_id',tenantId).eq('order_id',orderId).order('version',{ascending:false}).limit(100);return Response.json(result.error?{error:'Historiken kunde inte läsas.'}:{history:result.data},{status:result.error?500:200,headers});}
 const [imports,drafts,objects,ids,maintenance]=await Promise.all([db.rpc('hub_orderportal_imports',{p_tenant_id:tenantId}),db.from('hub_orderportal_orders').select('*').eq('tenant_id',tenantId).order('updated_at',{ascending:false}).order('id').limit(1000),db.from('hub_objects').select('id,object_type,data').eq('tenant_id',tenantId).in('object_type',['Vehicle','vehicle','Person','Customer','Project','Article']).eq('status','active').order('id').range(0,999),db.from('hub_identity_keys').select('object_id,identity_type,identity_value').eq('tenant_id',tenantId).eq('identity_type','workify_customer_number').limit(1000),db.rpc('hub_orderportal_maintenance',{p_tenant_id:tenantId})]);
 if([imports,drafts,objects,ids,maintenance].some(r=>r.error))return Response.json({error:'Orderunderlaget kunde inte läsas. Kontrollera databasanslutning och behörighet.'},{status:500,headers});
 // Fetch all catalog pages: the shared registry is larger than Supabase's default 1,000-row response.
 const allObjects=[...(objects.data||[])];let offset=1000;while((offset===1000?objects.data?.length===1000:true)){const page=await db.from('hub_objects').select('id,object_type,data').eq('tenant_id',tenantId).in('object_type',['Vehicle','vehicle','Person','Customer','Project','Article']).eq('status','active').order('id').range(offset,offset+999);if(page.error)return Response.json({error:'Resursregistret kunde inte läsas.'},{status:500,headers});allObjects.push(...(page.data||[]));if((page.data||[]).length<1000)break;offset+=1000;}
 const allDrafts=[...(drafts.data||[])];if(allDrafts.length===1000){for(let start=1000;;start+=1000){const page=await db.from('hub_orderportal_orders').select('*').eq('tenant_id',tenantId).order('updated_at',{ascending:false}).order('id').range(start,start+999);if(page.error)return Response.json({error:'Testorder kunde inte läsas.'},{status:500,headers});allDrafts.push(...(page.data||[]));if((page.data||[]).length<1000)break;}}
 const registerFields:Record<string,string[]> = {
  Customer:['customer_number','organization_number','organisation_number','vat_number','email','address','postal_code','city','peppol_id'],
  Project:['project_number','description'],
  Article:['article_number','description','unit','unit_of_measure'],
  Person:['email','phone'],
  Vehicle:['registration_number','description','make','model','vehicle_type','cost_center'],
 };
 const customerNumbers=new Map<string,Set<string>>();
 for(const key of ids.data||[]){
  const numbers=customerNumbers.get(key.object_id)||new Set<string>();
  numbers.add(key.identity_value);
  customerNumbers.set(key.object_id,numbers);
 }
 const resources=allObjects.map(o=>{
  const fields=registerFields[o.object_type==='vehicle'?'Vehicle':o.object_type]||[];
  const details:Record<string,string>={};
  for(const key of fields){
   const value=o.data[key];
   if(typeof value==='string'&&value.trim())details[key]=value.trim();
  }
  const numbers=customerNumbers.get(o.id);
  if(!details.customer_number&&numbers?.size===1)details.customer_number=[...numbers][0];
  return {id:o.id,kind:o.object_type,label:String(o.data.display_name||o.data.registration_number||o.data.name||o.id)+(o.data.project_number?' · '+o.data.project_number:''),details};
 });

 const rows=(imports.data||[]) as ImportRow[];const imported=groupImports(rows,ids.data||[]);const native=allDrafts.map(d=>({...d.payload,id:d.id,number:d.order_number,source:'humla',version:d.version,amount:d.amount,importedAt:d.updated_at,issues:[]}));
 return Response.json({orders:[...native,...imported,...maintenanceOrders(maintenance.data?.orders||[])],maintenanceSync:maintenance.data?.sync||[],resources,metrics:{octoberRows:rows.filter(r=>r.occurred_on>='2026-10-01'&&r.occurred_on<='2026-10-31').length,importedOrders:imported.length},testOnly:true},{headers});}
export async function POST(request:Request){if(request.headers.get('origin')!==new URL(request.url).origin)return Response.json({error:'Ogiltigt ursprung.'},{status:403,headers});const ctx=await orderAccess();if(!ctx)return Response.json({error:'Behörighet saknas.'},{status:403,headers});try{const raw=await request.text();if(raw.length>250000)return Response.json({error:'Ordern är för stor.'},{status:413,headers});const order=JSON.parse(raw) as Order;if(order.source!=='humla')return Response.json({error:'Källorder är skrivskyddade.'},{status:400,headers});validateOrder(order);const articleIds=[...new Set(order.lines.map(l=>l.articleId).filter((id):id is string=>Boolean(id)))];if(articleIds.length){const articles=await ctx.db.from('hub_objects').select('id').eq('tenant_id',ctx.tenantId).eq('object_type','Article').eq('status','active').in('id',articleIds);if(articles.error||articles.data?.length!==articleIds.length)return Response.json({error:'En vald artikel saknas i organisationens aktiva register. Välj artikel igen.'},{status:400,headers});}const {data,error}=await ctx.db.rpc('hub_orderportal_save',{p_tenant_id:ctx.tenantId,p_id:order.id||null,p_expected_version:order.version,p_request_id:order.requestId,p_payload:order});if(error)return Response.json({error:error.message.includes('maintenance_conflict')?'Fordonet har ett bokat underhållsbesök i Fordonskontrollen. Välj en annan tid eller ett annat fordon.':error.message.includes('resource_conflict')?'Fordonet eller föraren är redan bokad under perioden. Välj en annan tid eller resurs.':error.message.includes('price_context_changed')?'Prisets villkor har ändrats. Hämta priset igen eller välj manuellt pris.':error.message.includes('version_conflict')?'Ordern har ändrats av någon annan. Stäng och öppna den igen.':'Ordern kunde inte sparas. Kontrollera fält och behörighet.'},{status:409,headers});return Response.json({id:data},{headers});}catch(error){return Response.json({error:error instanceof Error?error.message:'Ogiltig order.'},{status:400,headers});}}
