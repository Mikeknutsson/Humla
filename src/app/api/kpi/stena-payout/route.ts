import {createClient} from '@/lib/supabase/server';
import {stenaPdfPayoutDate} from '@/lib/hub/stena-payout-pdf';

export const runtime = 'nodejs';
export const maxDuration = 45;

export async function POST(request: Request) {
 if(request.headers.get('origin')!==new URL(request.url).origin) return Response.json({error:'Ogiltigt ursprung.'},{status:403});
 const db=await createClient();
 const {data:{user}}=await db.auth.getUser();
 if(!user) return Response.json({error:'Logga in igen.'},{status:401});
 const {data:member}=await db.from('hub_tenant_members').select('tenant_id').eq('user_id',user.id).eq('status','active').maybeSingle();
 const {data:allowed}=member?await db.rpc('hub_has_permission',{p_tenant_id:member.tenant_id,p_permission:'kpi.manage'}):{data:false};
 if(!member||!allowed)return Response.json({error:'Behörighet saknas.'},{status:403});

 try {
  const {id,confirmedDate}=await request.json();
  if(typeof id!=='string'||!/^[a-f0-9-]{36}$/i.test(id))throw Error('Ogiltig bilaga.');
  const {data:file}=await db.from('hub_gmail_attachments').select('filename,subject')
   .eq('id',id).eq('tenant_id',member.tenant_id).eq('status','stored').maybeSingle();
  const number=file?.filename.match(/^([0-9]{5,16})\.pdf$/)?.[1];
  if(!number||!/Stena Recycling/i.test(file?.subject??''))throw Error('Välj en sparad självfaktura från Stena.');
  let date:string;
  if(confirmedDate!==undefined){
   if(typeof confirmedDate!=='string'||!/^20\d{2}-\d{2}-\d{2}$/.test(confirmedDate))throw Error('Ange utbetalningsdatumet från PDF-filen.');
   date=confirmedDate;
  }else{
   const signed=await db.functions.invoke('gmail-document-import',{body:{action:'download',id}});
   if(signed.error||!signed.data?.url)throw Error('PDF-filen gick inte att öppna.');
   const url=new URL(signed.data.url);
   if(url.origin!==new URL(process.env.NEXT_PUBLIC_SUPABASE_URL!).origin||!url.pathname.startsWith('/storage/v1/object/sign/'))throw Error('Ogiltig dokumentlänk.');
   const pdf=await fetch(url,{redirect:'error',signal:AbortSignal.timeout(12000)});
   if(!pdf.ok||Number(pdf.headers.get('content-length'))>4*1024*1024)throw Error('PDF-filen kunde inte hämtas eller är för stor.');
   const bytes=await pdf.arrayBuffer();
   if(bytes.byteLength>4*1024*1024)throw Error('PDF-filen är för stor.');
   await import('pdf-parse/worker');
   const {PDFParse}=await import('pdf-parse');
   const parser=new PDFParse({data:new Uint8Array(bytes)});
   try{
    const parsed=await parser.getText();
    const payout=stenaPdfPayoutDate(parsed.text);
    if(!payout)return Response.json({needsConfirmation:true,invoice:number});
    date=payout;
   }finally{await parser.destroy();}
  }
  const saved=await db.rpc('hub_stena_record_payout',{p_tenant:member.tenant_id,p_attachment:id,p_invoice:number,p_date:date});
  if(saved.error?.code==='23505')throw Error('Ett annat datum är redan registrerat för fakturan.');
  if(saved.error)throw Error('Utbetalningsdatumet kunde inte sparas.');
  if(!saved.data)throw Error('Fakturanumret har ingen match i Avräknade transporter.');
  return Response.json({date,invoice:number,bookings:saved.data});
 }catch(error){return Response.json({error:error instanceof Error?error.message:'PDF-filen kunde inte läsas.'},{status:422});}
}
