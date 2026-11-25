'use server';
import {revalidatePath} from 'next/cache';
import type {Candidate} from '@/lib/hub/sortergard-report';
import type {YardAddressClue} from '@/lib/hub/sortergard-address-clues';
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

export async function loadYardAddressClues(year:number,event:string) {
  const access=await yardAccess();
  if(!access) return {error:'Behörighet saknas.'};
  if (!Number.isInteger(year)||!/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(event)) return {error:'Ogiltig vägning.'};
  const {data,error}=await access.db.rpc('hub_sortergard_address_clues',{
    p_tenant:access.tenantId,p_year:year,p_event:event,
  });
  if(error) return {error:'Adressunderlaget kunde inte hämtas.'};
  return {clues:(data??[]) as YardAddressClue[]};
}

export async function saveLikelyYardAddress(year:number,event:string,candidate:Candidate) {
  const access=await yardAccess();
  if(!access) return {error:'Behörighet saknas.'};
  const {data,error}=await access.db.rpc('hub_sortergard_use_address',{
    p_tenant:access.tenantId,p_year:year,p_event:event,p_candidate:candidate,
  });
  if(error) return {error:'Den sannolika adressen kunde inte sparas.'};
  if(data) revalidatePath('/kpi/sortergarden/arsrapport');
  return {saved:data===true};
}
