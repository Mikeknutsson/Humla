"use client";

import Link from "next/link";
import {refreshKpiReport} from "../kpi/actions/refresh-report";
import {syncKpiReport} from "../kpi/actions/sync-report";
import type {ReportSyncStatus} from '@/lib/kpi/report-sync';
import {kpiReportVersion,canAutoRefreshKpi} from '@/lib/kpi/report-updates';
import {defaultSelection} from '@/lib/kpi/selection';
import { usePathname, useSearchParams } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { ArrowLeft, RefreshCw, MessageSquare,RotateCcw } from "lucide-react";

export function KpiRefresh() {
  const pathname = usePathname();
  const search = useSearchParams();
  const params = new URLSearchParams(search.toString());
  for (const key of ['view','level','grain','page','auth_retry']) params.delete(key);
  const dashboardHref = `/kpi?${params}`;
  const [refreshing, setRefreshing] = useState(false);
  const [sync,setSync]=useState<ReportSyncStatus|null>(null);
  const [requesting,setRequesting]=useState(false);
  const [syncError,setSyncError]=useState('');
  const generation=useRef<string|null>(null);
  const [updatePending,setUpdatePending]=useState(false);
  const query=search.toString();
  const queued=sync?.status==='queued';
  useEffect(()=>{
    if(pathname==='/kpi/login')return;
    const controller=new AbortController();
    let timer:ReturnType<typeof setTimeout>|undefined,checking=false,failures=0;
    async function check(){
      if(controller.signal.aborted||checking)return;
      if(timer)clearTimeout(timer);
      if(document.visibilityState==='hidden'){timer=setTimeout(check,60000);return;}
      checking=true;
      let delay=30000;
      try{
        const response=await fetch('/api/kpi/sync',{cache:'no-store',signal:AbortSignal.any([controller.signal,AbortSignal.timeout(15000)])});
        if(!response.ok)throw new Error('Status unavailable');
        const next:ReportSyncStatus=await response.json();
        if(controller.signal.aborted)return;
        failures=0;
        const version=kpiReportVersion(next);
        if(generation.current&&version&&generation.current!==version){
          setUpdatePending(true);
          const editing=document.activeElement?.matches('input,textarea,select,[contenteditable="true"]');
          if(canAutoRefreshKpi(pathname,query)&&!editing){
            // A document refresh clears client report snapshots too, including
            // monthly reports and forecast period caches. URL filters survive.
            window.location.reload();
            return;
          }
        }else if(version)generation.current=version;
        setSync(next);setSyncError('');
        delay=next.status==='queued'?4000:30000;
      }catch{
        if(controller.signal.aborted)return;
        failures++;
        delay=failures<=3?8000:60000;
        setSyncError('Synkstatus kunde inte hämtas. Visat underlag ligger kvar; status kontrolleras igen automatiskt.');
      }finally{
        checking=false;
        if(!controller.signal.aborted)timer=setTimeout(check,delay);
      }
    }
    const recheck=()=>void check();
    void check();
    window.addEventListener('focus',recheck);
    window.addEventListener('humla:kpi-imported',recheck);
    document.addEventListener('visibilitychange',recheck);
    return ()=>{controller.abort();if(timer)clearTimeout(timer);window.removeEventListener('focus',recheck);window.removeEventListener('humla:kpi-imported',recheck);document.removeEventListener('visibilitychange',recheck);};
  },[pathname,query]);
  const lastSync=sync?.synced_at?new Intl.DateTimeFormat('sv-SE',{timeZone:'Europe/Stockholm',dateStyle:'short',timeStyle:'short'}).format(new Date(sync.synced_at)):null;
  if (pathname === "/kpi/login" || pathname === "/kpi/fordon") return null;

  return <div className="kpi-refresh-bar no-print">
    {pathname !== "/kpi" && <Link href={dashboardHref} prefetch={false}><ArrowLeft size={16}/>Dashboard</Link>}
    {pathname !== "/kpi/ai" && <Link href="/kpi/ai" prefetch={false}><MessageSquare size={16}/>Fråga Humla</Link>}
    <span className="kpi-sync-status" role="status" title="Sparade importer begär rapportomräkning. Öppna rapportvyer uppdateras automatiskt när nytt underlag är publicerat. Nattlig kontroll 03.20.">
      {syncError||sync?.error||(queued?'Ny data bearbetas… Senaste publicerade underlaget visas.':updatePending?'Nytt rapportunderlag finns. Använd Uppdatera när du är klar med pågående redigering.':lastSync?`KPI uppdaterat ${lastSync}`:'')}
    </span>
    {sync?.can_sync&&<button type="button" disabled={requesting||queued} title="Förbered nytt KPI-underlag från Hubben. Dina filter behålls." onClick={async()=>{
      setRequesting(true);setSyncError('');
      try{const result=await syncKpiReport();if(result.data)setSync(result.data);else setSyncError(result.error??'Synkningen kunde inte startas.');}
      catch{setSyncError('Synkningen kunde inte startas. Underlaget ligger kvar.');}
      finally{setRequesting(false);}
    }}><RefreshCw size={16} className={requesting||queued?'refresh-spinning':''}/>{requesting||queued?'Synkar…':'Synka'}</button>}
    <button type="button" title="Ladda om vyn från det förberedda underlaget, utan att starta en Hub-synkning." disabled={refreshing} onClick={async () => {
      setRefreshing(true);
      // Reload client-side queues as well as server data, preserving the current URL.
      try { await Promise.race([refreshKpiReport(),new Promise(resolve=>setTimeout(resolve,15000))]); } finally { window.location.reload(); }
    }}><RefreshCw size={16} className={refreshing ? "refresh-spinning" : ""}/>{refreshing ? "Uppdaterar…" : "Uppdatera"}</button>
    <button type="button" title="Återställ alla filter till hela aktuella verksamhetsåret och alla kostnadsställen, grupper och enheter." onClick={()=>{
      const reset=defaultSelection();
      if(pathname==='/kpi'&&search.get('view'))reset.set('view',search.get('view')!);
      // A document navigation updates the saved selection before rendering,
      // and resets page-specific controls without reusing a cached client view.
      // eslint-disable-next-line @next/next/no-location-assign-relative-destination -- Reset must clear the client route cache and commit the preference cookie.
      window.location.assign(`${pathname}?${reset}`);
    }}><RotateCcw size={16}/>Reset</button>
    <span role="status" className="sr-only">{refreshing ? "Hämtar aktuellt underlag för samma vy och filter." : ""}</span>
  </div>;
}
