'use server';
import {redirect} from 'next/navigation';
import {createClient} from '@/lib/supabase/server';
export async function login(f:FormData){const db=await createClient();const {error}=await db.auth.signInWithPassword({email:String(f.get('email')||'').trim(),password:String(f.get('password')||'')});redirect(error?'/forare/login?error=1':'/forare');}
export async function logout(){const db=await createClient();await db.auth.signOut();redirect('/forare/login');}
