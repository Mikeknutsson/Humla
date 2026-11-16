import {orderAccess} from '@/lib/orderportal/server';

const headers={'Cache-Control':'private, no-store'};
const reply=(body:unknown,status=200)=>Response.json(body,{headers,status});
const uuid=/^[\da-f]{8}(?:-[\da-f]{4}){3}-[\da-f]{12}$/i;

async function context(request:Request){
 const ctx=await orderAccess();
 if(!ctx)return reply({error:'Behörighet saknas.'},403);
 const access=await ctx.db.rpc('hub_has_permission',{p_tenant_id:ctx.tenantId,p_permission:'transport.orders.manage'});
 if(access.data!==true)return reply({error:'Behörighet för transportledning krävs.'},403);
 const id=new URL(request.url).searchParams.get('id')||'';
 return uuid.test(id)?{...ctx,id}:reply({error:'Ogiltig artikel.'},400);
}

export async function GET(request:Request){
 const ctx=await context(request);
 if(ctx instanceof Response)return ctx;
 const {data,error}=await ctx.db.from('hub_transport_report_articles').select('unit, site_kind, enabled, options')
  .eq('tenant_id',ctx.tenantId).eq('article_id',ctx.id).maybeSingle();
 if(error)return reply({error:'Artikelkopplingar kunde inte hämtas.'},500);
 if(!data)return reply(null);
 const options=data.options as {siteId:string|null;price:number|null}[];
 const ids=options.flatMap(option=>option.siteId?[option.siteId]:[]);
 const sites=ids.length?await ctx.db.from('hub_objects').select('id,data').eq('tenant_id',ctx.tenantId).in('id',ids):null;
 if(sites?.error)return reply({error:'Platserna kunde inte hämtas.'},500);
 return reply({unit:data.unit,siteKind:data.site_kind,enabled:data.enabled,
  options:options.map(option=>({name:sites?.data?.find(site=>site.id===option.siteId)?.data?.display_name||'',price:option.price===null?'':String(option.price)}))});
}

export async function PUT(request:Request){
 if(request.headers.get('origin')!==new URL(request.url).origin)return reply({error:'Ogiltigt ursprung.'},403);
 const ctx=await context(request);
 if(ctx instanceof Response)return ctx;
 try{
  const raw=await request.text();
  if(raw.length>15000)throw Error();
  const body=JSON.parse(raw);
  const {unit,siteKind,enabled}=body;
  if(!Array.isArray(body.options)||typeof enabled!=='boolean')throw Error();
  const choices=body.options.map((option:{name:unknown;price:unknown})=>{
   if(typeof option.name!=='string'||typeof option.price!=='string')throw Error();
   const price=option.price.trim()===''?null:Number(option.price.replace(',','.'));
   if(price!==null&&!Number.isFinite(price))throw Error();
   return {name:option.name,price};
  });
  const {error}=await ctx.db.rpc('hub_transport_report_article_save',{t:ctx.tenantId,a:ctx.id,u:unit,k:siteKind,e:enabled,choices});
  if(error)return reply({error:error.message.includes('duplicate_site')?'Samma plats kan bara anges en gång.':'Kontrollera enhet, platser och priser. Inställningarna sparades inte.'},409);
  return reply({saved:true});
 }catch{return reply({error:'Ogiltiga artikelinställningar.'},400);}
}
