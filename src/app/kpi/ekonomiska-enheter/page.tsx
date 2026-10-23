import EconomicUnits from '@/app/ekonomiska-enheter/page';
import {KpiDetailShell} from '@/app/_components/kpi-detail-shell';
export const dynamic='force-dynamic';
export default function DashboardUnits(props:{searchParams:Promise<{date?:string;unit?:string;q?:string}>}){
 return <KpiDetailShell query="" title="Ekonomiska enheter" breadcrumb="Humla Dashboard / Ekonomiska enheter"><EconomicUnits {...props}/></KpiDetailShell>;
}
