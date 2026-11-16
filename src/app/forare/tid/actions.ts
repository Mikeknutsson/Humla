'use server';

import {redirect} from 'next/navigation';
import {createClient} from '@/lib/supabase/server';

export async function saveTimeDraft(form:FormData){
 const db=await createClient();
 const {data:{user}}=await db.auth.getUser();
 if(!user)redirect('/forare/login');
 const {data:member}=await db.from('hub_tenant_members').select('tenant_id')
  .eq('user_id',user.id).eq('status','active').maybeSingle();
 if(!member)redirect('/forare/tid?status=error');
 const start=String(form.get('start')||''),end=String(form.get('end')||'');
 const rawBreak=String(form.get('breakMinutes')||'');
 const vehicle=String(form.get('vehicle')||''),note=String(form.get('note')||'');
 const timestamp=/^\d{4}-\d\d-\d\dT\d\d:\d\d$/;
 if(!timestamp.test(start)||!timestamp.test(end)||!/^\d{1,4}$/.test(rawBreak)||vehicle.length>80||note.length>500)
  redirect('/forare/tid?status=invalid');
 const {error}=await db.rpc('hub_transport_time_draft',{t:member.tenant_id,draft:{
  start,end,breakMinutes:Number(rawBreak),vehicle,note
 }});
 redirect('/forare/tid?status='+(error?(error.code?.startsWith('22')||error.code==='23514'?'invalid':'error'):'saved'));
}
