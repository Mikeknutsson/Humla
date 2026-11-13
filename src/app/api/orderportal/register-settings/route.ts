import {orderAccess} from '@/lib/orderportal/server';

const headers={'Cache-Control':'private, no-store'};
const reply=(body:unknown,status=200)=>Response.json(body,{status,headers});
const fields='category,unit,note,revision';

async function context(request:Request){
 const ctx=await orderAccess();
 if(!ctx)return reply({error:'Behörighet saknas.'},403);
 const id=new URL(request.url).searchParams.get('id')||'';
 if(!/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(id))return reply({error:'Ogiltigt register-ID.'},400);
 const {data,error}=await ctx.db.from('hub_objects').select('object_type').eq('tenant_id',ctx.tenantId)
  .eq('id',id).eq('status','active').in('object_type',['Article','Person','Vehicle','vehicle']).maybeSingle();
 if(error)return reply({error:'Registret kunde inte läsas.'},500);
 if(!data)return reply({error:'Registerposten finns inte.'},404);
 return {...ctx,id,kind:data.object_type};
}

export async function GET(request:Request){
 const ctx=await context(request);
 if(ctx instanceof Response)return ctx;
 const {data,error}=await ctx.db.from('hub_orderportal_register_settings').select(fields)
  .eq('tenant_id',ctx.tenantId).eq('object_id',ctx.id).maybeSingle();
 return error?reply({error:'Inställningarna kunde inte läsas.'},500):reply(data||{category:'',unit:'',note:'',revision:0});
}

export async function PUT(request:Request){
 if(request.headers.get('origin')!==new URL(request.url).origin)return reply({error:'Ogiltigt ursprung.'},403);
 const ctx=await context(request);
 if(ctx instanceof Response)return ctx;
 let values;
 let revision:number;
 try{
  const raw=await request.text();
  if(raw.length>10000)throw Error();
  const body=JSON.parse(raw);
  revision=body.revision;
  if(!Number.isInteger(revision)||revision<0||revision>=2147483647)throw Error();
  const field=(key:string,max:number)=>{
   const value=body[key];
   if(typeof value!=='string'||value.trim().length>max)throw Error();
   return value.trim();
  };
  values={category:field('category',80),unit:ctx.kind==='Article'?field('unit',20):'',note:field('note',2000),
   revision:revision+1,updated_by:ctx.userId,updated_at:new Date().toISOString()};
 }catch{return reply({error:'Kontrollera fältens längd och versionen.'},400);}
 const table=ctx.db.from('hub_orderportal_register_settings');
 const result=revision===0?
  await table.insert({...values,tenant_id:ctx.tenantId,object_id:ctx.id}).select(fields).single():
  await table.update(values).eq('tenant_id',ctx.tenantId).eq('object_id',ctx.id).eq('revision',revision).select(fields).maybeSingle();
 if(result.error?.code==='23505'||(!result.error&&!result.data))return reply({error:'Inställningarna har ändrats. Ladda om kortet innan du sparar igen.'},409);
 return result.error?reply({error:'Inställningarna kunde inte sparas.'},500):reply(result.data);
}
