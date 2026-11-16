import { redirect } from 'next/navigation';

export default async function ImportHistoryRedirect({searchParams}:{searchParams:Promise<{kind?:string;page?:string}>}){
  const {kind,page}=await searchParams;
  const target=new URLSearchParams({view:'importhistorik'});
  if(typeof kind==='string')target.set('history_kind',kind);
  if(typeof page==='string')target.set('history_page',page);
  redirect(`/kpi?${target}`);
}
