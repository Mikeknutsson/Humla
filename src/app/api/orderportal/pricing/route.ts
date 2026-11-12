import {orderAccess} from '@/lib/orderportal/server';
export const dynamic='force-dynamic';
const headers={'Cache-Control':'private, no-store'};
export async function GET(){
 const ctx=await orderAccess();if(!ctx)return Response.json({error:'Behörighet saknas.'},{status:403,headers});
 const [lists,prices,sites]=await Promise.all([
 ctx.db.from('hub_orderportal_price_lists').select('*').eq('tenant_id',ctx.tenantId).order('name').limit(1000),
 ctx.db.from('hub_orderportal_prices').select('*').eq('tenant_id',ctx.tenantId).order('created_at',{ascending:false}).limit(1001),
 ctx.db.from('hub_objects').select('id,data').eq('tenant_id',ctx.tenantId).eq('object_type','TestMaterialSite').eq('status','active').order('id').limit(1000)]);
 if([lists,prices,sites].some(r=>r.error))return Response.json({error:'Prisregistret kunde inte läsas.'},{status:500,headers});
 if((prices.data?.length||0)>1000)return Response.json({error:'Prisregistret är för stort för denna testvy. Avgränsning behöver införas.'},{status:422,headers});
 return Response.json({lists:lists.data,prices:prices.data,sites:sites.data?.map(s=>({id:s.id,kind:'TestMaterialSite',label:String(s.data.display_name)}))},{headers});
}
export async function POST(request:Request){
 if(request.headers.get('origin')!==new URL(request.url).origin)return Response.json({error:'Ogiltigt ursprung.'},{status:403,headers});
 const ctx=await orderAccess();if(!ctx)return Response.json({error:'Behörighet saknas.'},{status:403,headers});
 try{const raw=await request.text();if(raw.length>20000)throw Error('För stor begäran.');const body=JSON.parse(raw);
 if(body.kind==='quote'){
 const d=body.data;
 const r=await ctx.db.rpc('hub_orderportal_quote',{p_tenant_id:ctx.tenantId,p_article:d.articleId,p_customer:d.customerId||null,p_project:d.projectId||null,p_day:d.date,p_unit:d.unit,p_pickup:d.pickupSiteId||null,p_delivery:d.deliverySiteId||null});
 if(r.error)throw Error('Priset kunde inte hämtas. Kontrollera artikel, enhet och datum.');return Response.json(r.data,{headers});
 }
 if(body.kind==='retire'){const r=await ctx.db.rpc('hub_orderportal_retire_price',{p_tenant_id:ctx.tenantId,p_id:body.data.id});if(r.error)throw Error('Priset kunde inte arkiveras.');return Response.json({ok:true},{headers});}
 if(!['list','site','price'].includes(body.kind))throw Error('Ogiltig åtgärd.');
 const r=await ctx.db.rpc('hub_orderportal_catalog_add',{p_tenant_id:ctx.tenantId,p_kind:body.kind,p_data:body.data});
 if(r.error){const message=r.error.message;throw Error(message.includes('overlapping_price_period')?'Det finns redan ett pris för samma artikel, enhet och platser under perioden.':message.includes('duplicate')||message.includes('already_exists')?'Namnet eller grundprislistan finns redan.':'Kunde inte spara. Kontrollera fält, datum och registerval.');}
 return Response.json({id:r.data},{headers});
 }catch(e){return Response.json({error:e instanceof Error?e.message:'Ogiltig begäran.'},{status:400,headers});}
}
