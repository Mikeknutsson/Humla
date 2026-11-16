import {redirect} from 'next/navigation';
import {createClient} from '@/lib/supabase/server';
import {selectDriverPeriod,type DriverAvailablePeriod,type DriverReport} from '@/lib/hub/driver-self';
import Mobile from './mobile';
import {HomeSummary} from './home-summary';

export const dynamic='force-dynamic';
export default async function Page(){
 const db=await createClient();
 const {data:{user}}=await db.auth.getUser();
 if(!user)redirect('/forare/login');
 const {data:member}=await db.from('hub_tenant_members').select('tenant_id')
  .eq('user_id',user.id).eq('status','active').maybeSingle();
 if(!member)return <Mobile summary={<HomeSummary/>}/>;
 const {data,error}=await db.rpc('hub_driver_goal_periods_v1',{p_tenant:member.tenant_id,p_person:null});
 const available=data as DriverAvailablePeriod[]|null;
 if(error||!available?.length)return <Mobile summary={<HomeSummary/>}/>;
 const period=selectDriverPeriod(available,undefined,available[0].to);
 const {data:report,error:reportError}=await db.rpc('hub_driver_self_v1',{
  p_tenant:member.tenant_id,p_from:period.from,p_to:period.to,p_person:null
 });
 return <Mobile summary={<HomeSummary period={period} report={reportError?null:report as DriverReport|null}/>}/>;
}
