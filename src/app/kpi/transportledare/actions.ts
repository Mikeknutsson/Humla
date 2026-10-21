'use server';
import {redirect} from 'next/navigation';
import {revalidatePath} from 'next/cache';
import {createClient} from '@/lib/supabase/server';

export async function saveTransportTarget(form:FormData){
 const db=await createClient();const {data:{user}}=await db.auth.getUser();if(!user)redirect('/kpi/login');
 const {data:member}=await db.from('hub_tenant_members').select('tenant_id,role').eq('user_id',user.id).eq('status','active').limit(1).maybeSingle();
 if(!member||member.role!=='owner')throw new Error('Ägarbehörighet krävs.');
 const {error}=await db.rpc('hub_transport_unit_target_save_v2',{p_tenant:member.tenant_id,p_unit:String(form.get('unit_id')??''),p_from:String(form.get('valid_from')??''),p_margin:Number(form.get('margin')),p_reason:String(form.get('reason')??'')});
 revalidatePath('/kpi/transportledare');
 const q=new URLSearchParams({from:String(form.get('from')??''),to:String(form.get('to')??''),unit:String(form.get('unit_id')??''),saved:error?'failed':'yes'});
 for(const key of ['user_id','months']){const value=String(form.get(key)??'');if(value)q.set(key,value);}
 redirect('/kpi/transportledare?'+q);
}
