import {orderAccess} from '@/lib/orderportal/server';
import {parseCustomerProfile} from '@/lib/orderportal/customer-card';
import {orderDocumentPdf,type OrderDocument} from '@/lib/orderportal/documents';
import type {Order} from '@/lib/orderportal/model';

export const dynamic='force-dynamic';
const headers={'Cache-Control':'private, no-store'};
const fail=(error:string,status:number)=>Response.json({error},{status,headers});

export async function GET(request:Request){
 const ctx=await orderAccess();
 if(!ctx)return fail('Behörighet saknas.',403);
 const {searchParams}=new URL(request.url);
 const id=searchParams.get('id')||'';
 const kind=searchParams.get('kind') as OrderDocument|null;
 const version=Number(searchParams.get('version'));
 if(!/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(id)||
  (kind!=='delivery-note'&&kind!=='invoice-basis')||!Number.isSafeInteger(version)||version<1)
  return fail('Ogiltig dokumentbegäran.',400);
 const stored=await ctx.db.from('hub_orderportal_orders').select('order_number,payload,amount,version')
  .eq('tenant_id',ctx.tenantId).eq('id',id).maybeSingle();
 if(stored.error)return fail('Ordern kunde inte läsas.',500);
 if(!stored.data)return fail('Testordern finns inte.',404);
 if(stored.data.version!==version)return fail('Ordern har ändrats. Öppna den senaste versionen.',409);
 const order:Order={...stored.data.payload,number:stored.data.order_number,amount:Number(stored.data.amount),version};
 const card=await ctx.db.from('hub_orderportal_customer_cards').select('profile')
  .eq('tenant_id',ctx.tenantId).eq('customer_id',order.customerId).maybeSingle();
 if(card.error)return fail('Kundkortet kunde inte läsas.',500);
 if(!card.data)return fail('Aktivera dokumenttypen på kundkortet.',409);
 try{
  const {documents}=parseCustomerProfile(card.data.profile);
  if(!(kind==='delivery-note'?documents.deliveryNote:documents.invoiceData))
   return fail('Aktivera dokumenttypen på kundkortet.',409);
  const bytes=await orderDocumentPdf(order,kind,documents);
  const number=order.number.replace(/[^a-z0-9_-]/gi,'_');
  const name=kind==='delivery-note'?'foljesedel':'fakturaunderlag';
  return new Response(new Uint8Array(bytes),{headers:{...headers,'Content-Type':'application/pdf',
   'Content-Disposition':`attachment; filename="test-${name}-${number}-v${version}.pdf"`}});
 }catch{return fail('Dokumentet kunde inte skapas.',500);}
}
