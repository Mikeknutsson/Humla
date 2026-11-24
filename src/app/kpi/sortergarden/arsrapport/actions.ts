'use server';
import {revalidatePath} from 'next/cache';
import {yardAccess,yardReport} from '@/lib/hub/sortergard-server';

export async function reviewYard(year:number, action:'match'|'review'|'search'|'finalize', args:object = {}) {
  if (!['match','review','search','finalize'].includes(action)) return {error:'Okänd åtgärd.'};
  const access=await yardAccess();
  if(!access) return {error:'Behörighet saknas.'};
  const {data,error}=await yardReport(access,year,action,args);
  if(error) return {error:error.code==='P0001'?error.message:'Åtgärden kunde inte slutföras. Försök igen.'};
  if(action!=='search') revalidatePath('/kpi/sortergarden/arsrapport');
  return {data};
}
