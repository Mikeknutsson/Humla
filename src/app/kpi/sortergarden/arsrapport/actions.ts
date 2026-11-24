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

export async function saveYardFacility(year:number,event:string,side:'origin'|'destination',address:string) {
  const access=await yardAccess();
  if(!access) return {error:'Behörighet saknas.'};
  const {error}=await access.db.rpc('hub_sortergard_facility',{
    p_tenant:access.tenantId,p_year:year,p_event:event,p_side:side,p_address:address,
  });
  if(error) return {error:error.code==='P0001'?error.message:'Anläggningsadressen kunde inte sparas.'};
  revalidatePath('/kpi/sortergarden/arsrapport');
  return {saved:true};
}
