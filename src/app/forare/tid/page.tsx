import Link from 'next/link';
import {redirect} from 'next/navigation';
import {createClient} from '@/lib/supabase/server';
import {saveTimeDraft} from './actions';

export const dynamic='force-dynamic';
type Draft={start:string;end:string;breakMinutes:number;vehicle:string;note:string};

export default async function TimePage({searchParams}:{searchParams:Promise<{status?:string}>}){
 const db=await createClient();
 const {data:{user}}=await db.auth.getUser();
 if(!user)redirect('/forare/login');
 const {data:member}=await db.from('hub_tenant_members').select('tenant_id')
  .eq('user_id',user.id).eq('status','active').maybeSingle();
 const response=member?await db.rpc('hub_transport_time_draft',{t:member.tenant_id}):null;
 const draft=response?.data as Draft|null|undefined;
 const {status}=await searchParams;
 return <main>
  <Link className="driver-link" href="/forare">Till startsidan</Link>
  <section className="driver-card">
   <h1>Rapportera tid</h1>
   <p>Spara ett arbetspass som utkast i Humla. Registrera och skicka tidrapporten i TransPA.</p>
   <a className="driver-link" href="https://connect.mytranspa.com/" target="_blank" rel="noreferrer">Öppna TransPA</a>
   {status==='saved'&&<p role="status">Utkast sparat i Humla.</p>}
   {status==='invalid'&&<p role="alert" className="driver-error">Kontrollera start, slut och rast. Passet får vara högst 24 timmar och rasten måste vara kortare än passet.</p>}
   {status==='error'&&<p role="alert" className="driver-error">Utkastet kunde inte sparas.</p>}
   {!response||response.error?<p>Utkastet kunde inte hämtas. Ditt konto behöver vara kopplat till en chaufförsprofil.</p>:<>
    <h2>Mitt tidsutkast</h2>
    <p>Ett utkast åt gången. Tiderna anges i svensk lokal tid.</p>
    <form action={saveTimeDraft}>
     <label>Start<input name="start" type="datetime-local" required defaultValue={draft?.start}/></label>
     <label>Slut<input name="end" type="datetime-local" required defaultValue={draft?.end}/></label>
     <label>Rast i minuter<input name="breakMinutes" type="number" min={0} max={1439} required defaultValue={draft?.breakMinutes??0}/></label>
     <label>Fordon<input name="vehicle" maxLength={80} defaultValue={draft?.vehicle}/></label>
     <label>Kommentar<textarea name="note" rows={2} maxLength={500} defaultValue={draft?.note}/></label>
     <button className="driver-primary">Spara tidsutkast</button>
    </form>
   </>}
  </section>
 </main>;
}
