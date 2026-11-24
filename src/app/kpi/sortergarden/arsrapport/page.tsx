import Link from 'next/link';
import {KpiDetailShell} from '@/app/_components/kpi-detail-shell';
import {reportYear,yardAccess,yardReport} from '@/lib/hub/sortergard-server';
import type {ReportVersion,Weighing} from '@/lib/hub/sortergard-report';
import YardWorkspace from './workspace';

export const dynamic='force-dynamic';

export default async function Page({searchParams}:{searchParams:Promise<{year?:string;version?:string}>}) {
  const params=await searchParams;
  const year=reportYear(params.year), latest=reportYear();
  const access=await yardAccess();
  const selected=/^[a-f0-9-]{36}$/i.test(params.version??'')?params.version:undefined;
  const [report,archive]=access?await Promise.all([yardReport(access,year,selected?'version':'read',{id:selected}),yardReport(access,year,'archive')]):[null,null];
  const version=selected?report?.data as (ReportVersion&{rows:Weighing[]})|null:null;
  return <KpiDetailShell title="Årsrapport Miljöförbundet" breadcrumb="Humla Dashboard / Sortergården" query=""
    extraNavigation={<Link href="/kpi/import/flintab">Import – Flintab Fordonsvåg</Link>}>
    <div className="content">
      {!access ? <section className="panel">KPI-administratör krävs för årsrapporten.</section> :
        !report?.data || report.error ? <section className="panel">Rapporten kunde inte hämtas. <Link href="?">Öppna aktuell rapport</Link></section> :
        <YardWorkspace key={`${year}:${selected??''}`} year={year} latest={latest} version={version}
          rows={version?.rows??report.data as Weighing[]} archive={archive?.error?null:archive?.data as ReportVersion[]}/>}
    </div>
  </KpiDetailShell>;
}
