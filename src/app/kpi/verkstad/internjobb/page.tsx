import {redirect} from 'next/navigation';

export default async function WorkshopResourceRedirect({searchParams}:{searchParams:Promise<Record<string,string|string[]|undefined>>}){
  const query=await searchParams;
  const next=new URLSearchParams({cost_center:'40'});
  for(const key of ['from','to','batch','tab','center','project','ao','page']){
    const value=query[key];
    if(typeof value==='string')next.set(key==='from'||key==='to'?key:'intern_'+key,value);
  }
  redirect('/kpi/verkstad?'+next+'#internjobb');
}
