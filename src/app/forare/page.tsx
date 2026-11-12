import {redirect} from 'next/navigation';
import {createClient} from '@/lib/supabase/server';
import Mobile from './mobile';
export const dynamic='force-dynamic';
export default async function Page(){const db=await createClient();const {data:{user}}=await db.auth.getUser();if(!user)redirect('/forare/login');return <Mobile/>;}
