import {redirect} from 'next/navigation';
import {aiContext} from '@/lib/ai/context';
import {HumlaChat} from '@/app/_components/humla-chat';
export const dynamic='force-dynamic';
export const metadata={title:'Fråga Humla · Dashboard'};
export default async function AiPage(){const c=await aiContext();if('error'in c){if(c.status===401)redirect('/kpi/login');return <main><h1>Fråga Humla</h1><p>{c.error}</p></main>;}return <div className="kpi-app"><HumlaChat/></div>;}
