'use server';
import {redirect} from 'next/navigation';
import {createClient} from '@/lib/supabase/server';
export async function login(form:FormData){const db=await createClient();const {error}=await db.auth.signInWithPassword({email:String(form.get('email')||'').trim(),password:String(form.get('password')||'')});if(error)redirect('/orderportal/login?error=1');redirect('/orderportal');}
