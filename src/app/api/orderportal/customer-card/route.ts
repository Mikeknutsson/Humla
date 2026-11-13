import {orderAccess} from '@/lib/orderportal/server';
import {emptyCustomerProfile,parseCustomerProfile} from '@/lib/orderportal/customer-card';

const headers={'Cache-Control':'private, no-store'};
const reply=(body:unknown,status=200)=>Response.json(body,{status,headers});
const fail=(error:string,status:number)=>reply({error},status);
const uuid=/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i;

async function context(request:Request){
 const access=await orderAccess();
 if(!access)return fail('Behörighet saknas.',403);
 const id=new URL(request.url).searchParams.get('id')||'';
 if(!uuid.test(id))return fail('Ogiltigt kund-ID.',400);
 const {db,tenantId}=access;
 const customer=await db.from('hub_objects').select('id').eq('tenant_id',tenantId)
  .eq('id',id).eq('object_type','Customer').eq('status','active').maybeSingle();
 if(customer.error)return fail('Kundregistret kunde inte läsas.',500);
 if(!customer.data)return fail('Kunden finns inte i det aktiva registret.',404);
 return {...access,id};
}

export async function GET(request:Request){
 const ctx=await context(request);
 if(ctx instanceof Response)return ctx;
 const result=await ctx.db.from('hub_orderportal_customer_cards').select('profile,revision')
  .eq('tenant_id',ctx.tenantId).eq('customer_id',ctx.id).maybeSingle();
 if(result.error)return fail('Kundkortet kunde inte läsas.',500);
 if(!result.data)return reply({profile:emptyCustomerProfile(),revision:0});
 try{return reply({...result.data,profile:parseCustomerProfile(result.data.profile)});}
 catch{return fail('Det sparade kundkortet har ogiltiga uppgifter.',500);}
}

export async function PUT(request:Request){
 if(request.headers.get('origin')!==new URL(request.url).origin)return fail('Ogiltigt ursprung.',403);
 const ctx=await context(request);
 if(ctx instanceof Response)return ctx;
 let profile,revision:number;
 try{
  const raw=await request.text();
  if(new TextEncoder().encode(raw).length>50000)return fail('Kundkortet är för stort.',413);
  const body=JSON.parse(raw);
  revision=body.revision;
  if(!Number.isSafeInteger(revision)||revision<0||revision>=2147483647)throw Error('Ogiltig version.');
  profile=parseCustomerProfile(body.profile);
 }catch(error){return fail(error instanceof Error?error.message:'Ogiltigt kundkort.',400);}
 const values={profile,revision:revision+1,updated_by:ctx.userId,updated_at:new Date().toISOString()};
 const table=ctx.db.from('hub_orderportal_customer_cards');
 const result=revision===0?
  await table.insert({...values,tenant_id:ctx.tenantId,customer_id:ctx.id}).select('profile,revision').single():
  await table.update(values).eq('tenant_id',ctx.tenantId).eq('customer_id',ctx.id).eq('revision',revision)
   .select('profile,revision').maybeSingle();
 if(result.error?.code==='23505'||(!result.error&&!result.data))
  return fail('Kundkortet har ändrats. Ladda om det innan du sparar igen.',409);
 if(result.error)return fail('Kundkortet kunde inte sparas.',500);
 return reply(result.data);
}
