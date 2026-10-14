import {KpiMonthlyReport} from '@/app/_components/kpi-monthly-report';
import {KpiDetailShell} from '@/app/_components/kpi-detail-shell';
import {reviewAccess} from '@/lib/hub/review-access';
export const dynamic='force-dynamic';
export default async function MonthlyMeetingReport({searchParams}:{searchParams:Promise<Record<string,string|undefined>>}){
 if(!await reviewAccess())return <main>Åtkomst saknas.</main>;
 const params=await searchParams,query=new URLSearchParams(Object.entries(params).filter((entry):entry is[string,string]=>typeof entry[1]==='string'));
 query.set('view','monthly');
 return <KpiDetailShell query={query.toString()}title="Månadsrapport till ledningsgruppen"breadcrumb="Humla Dashboard / Månadsrapport"><div className="content"><KpiMonthlyReport query={query.toString()}/></div></KpiDetailShell>;
}
