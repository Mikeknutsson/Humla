'use server';

import {revalidatePath} from 'next/cache';
import {redirect} from 'next/navigation';
import {reviewAccess} from '@/lib/hub/review-access';

export async function assignPersonVehicle(data:FormData) {
 const access=await reviewAccess();
 if(!access)redirect('/kpi');
 const person=String(data.get('person')??'');
 const registration=String(data.get('registration')??'').toUpperCase().replace(/[\s-]/g,'');
 const start=String(data.get('start')??'');
 const query=new URLSearchParams(String(data.get('selection')??''));
 const selection=new URLSearchParams();
 for(const key of ['batch','period_mode','fiscal_year','month','months','from','to']){
  const value=query.get(key);
  if(value&&value.length<=80)selection.set(key,value);
 }
 let status='invalid';
 if(/^[0-9a-f-]{36}$/i.test(person)&&/^[A-Z0-9]{2,10}$/.test(registration)&&/^\d{4}-\d{2}-\d{2}$/.test(start)){
  const {error}=await access.db.rpc('hub_set_person_work_vehicle',{
   t:access.tenantId,p_person:person,p_registration:registration,p_from:start,
  });
  status=!error?'saved':error.code==='P0002'?'missing':error.code==='23P01'?'overlap':'failed';
  if(!error)revalidatePath('/kpi/maskiner');
 }
 selection.set('vehicle_link',status);
 redirect('/kpi/maskiner?'+selection+'#personalenheter');
}
