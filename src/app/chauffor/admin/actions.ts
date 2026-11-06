'use server';
import {redirect} from 'next/navigation';
import {revalidatePath} from 'next/cache';
import {createClient} from '@/lib/supabase/server';
export async function bindDriverAccount(form:FormData){
 const db=await createClient();const {data:{user}}=await db.auth.getUser();if(!user)redirect('/kpi/login');
 const {data:member}=await db.from('hub_tenant_members').select('tenant_id,role').eq('user_id',user.id).eq('status','active').maybeSingle();
 if(!member||member.role!=='owner')redirect('/chauffor');
 const account=String(form.get('account')??''),person=String(form.get('person')??'');
 if(!/^[0-9a-f-]{36}$/i.test(account)||(person&&!/^[0-9a-f-]{36}$/i.test(person)))redirect('/chauffor/admin?saved=no');
 const {error}=await db.rpc('hub_driver_bind_account_v1',{p_tenant:member.tenant_id,p_user:account,p_person:person||null});
 revalidatePath('/chauffor');revalidatePath('/chauffor/admin');redirect('/chauffor/admin?saved='+(error?'no':'yes'));
}
