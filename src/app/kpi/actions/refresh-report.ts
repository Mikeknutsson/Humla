'use server';
import {revalidateTag} from 'next/cache';
import {createClient} from '@/lib/supabase/server';
export async function refreshKpiReport() {
 const supabase=await createClient();
 const {data:{user}}=await supabase.auth.getUser();
 if(user)revalidateTag(`kpi-report:${user.id}`,{expire:0});
}
