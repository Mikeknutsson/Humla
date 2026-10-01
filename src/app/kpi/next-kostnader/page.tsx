import {redirect} from 'next/navigation';
export default async function NextCosts({searchParams}:{searchParams:Promise<{from?:string;to?:string}>}){const p=await searchParams;const q=new URLSearchParams({from:p.from??'2026-08-01',to:p.to??'2026-08-31',source:'NEXT'});redirect(`/kpi/analys?${q}`)}
