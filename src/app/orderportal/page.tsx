import {redirect} from 'next/navigation';
import {orderAccess} from '@/lib/orderportal/server';
import Portal from './portal';
export const dynamic='force-dynamic';
export default async function Page(){if(!await orderAccess())redirect('/orderportal/login');return <Portal/>;}
