"use client";

import Link from "next/link";
import {refreshKpiReport} from "../kpi/actions/refresh-report";
import {syncKpiReport} from "../kpi/actions/sync-report";
import type {ReportSyncStatus} from '@/lib/kpi/report-sync';
import {defaultSelection} from '@/lib/kpi/selection';
import { usePathname, useSearchParams, useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { ArrowLeft, RefreshCw, MessageSquare,RotateCcw } from "lucide-react";

export function KpiRefresh() {
  const pathname = usePathname();
  const search = useSearchParams();
  const params = new URLSearchParams(search.toString());
  for (const key of ['view','level','grain','page','auth_retry']) params.delete(key);
  const dashboardHref = `/kpi?${params}`;
  const [refreshing, setRefreshing] = useState(false);
  const router=useRouter();
  const [sync,setSync]=useState<ReportSyncStatus|null>(null);
  const [requesting,setRequesting]=useState(false);
  const [syncError,setSyncError]=useState('');
  const generation=useRef<string|null>(null);
  const queued=sync?.status==='queued';
  useEffect(()=>{
    if(pathname==='/kpi/login')return;
    const controller=new AbortController();
    let timer:ReturnType<typeof setTimeout>|undefined;
    let failures=0;
    const started=Date.now();
    async function check(){
      try{
        const response=await fetch('/api/kpi/sync',{cache:'no-store',signal:controller.signal});
        if(!response.ok)throw new Error('Status unavailable');
        const next:ReportSyncStatus=await response.json();
        if(controller.signal.aborted)return;
        failures=0;
        if(generation.current&&next.generation&&generation.current!==next.generation)router.refresh();
        generation.current=next.generation;
        setSync(next);setSyncError('');
        if(next.status==='queued'&&Date.now()-started<600000)timer=setTimeout(check,4000);
        else if(next.status==='queued')setSyncError('Synkningen tar längre tid än väntat. Underlaget ligger kvar; använd Uppdatera för att kontrollera status.');
      }catch{
        if(controller.signal.aborted)return;
        if(++failures<=3)timer=setTimeout(check,8000);
        else setSyncError('Synkstatus kunde inte hämtas. Visat underlag ligger kvar.');
      }
    }
    void check();
    return ()=>{controller.abort();if(timer)clearTimeout(timer);};
  },[pathname,queued,router]);
  const lastSync=sync?.synced_at?new Intl.DateTimeFormat('sv-SE',{timeZone:'Europe/Stockholm',dateStyle:'short',timeStyle:'short'}).format(new Date(sync.synced_at)):null;
  if (pathname === "/kpi/login") return null;

  return <div className="kpi-refresh-bar no-print">
    {pathname !== "/kpi" && <Link href={dashboardHref} prefetch={false}><ArrowLeft size={16}/>Dashboard</Link>}
    {pathname !== "/kpi/ai" && <Link href="/kpi/ai" prefetch={false}><MessageSquare size={16}/>Fråga Humla</Link>}
    <span className="kpi-sync-status" role="status" title="KPI-underlaget förberäknas kl. 03.00 svensk tid. Importer och matchningar kommer med vid nästa synkning.">
      {syncError||sync?.error||(queued?'Synkar… Senaste underlaget visas.':lastSync?`KPI synkat ${lastSync} · nattligen 03.00`:'')}
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
      try { await refreshKpiReport(); } finally { window.location.reload(); }
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
