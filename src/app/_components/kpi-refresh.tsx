"use client";

import Link from "next/link";
import {refreshKpiReport} from "../kpi/actions/refresh-report";
import { usePathname, useSearchParams } from "next/navigation";
import { useState } from "react";
import { ArrowLeft, RefreshCw } from "lucide-react";

export function KpiRefresh() {
  const pathname = usePathname();
  const search = useSearchParams();
  const params = new URLSearchParams(search.toString());
  for (const key of ['view','level','grain','page','auth_retry']) params.delete(key);
  const dashboardHref = `/kpi?${params}`;
  const [refreshing, setRefreshing] = useState(false);
  if (pathname === "/kpi/login") return null;

  return <div className="kpi-refresh-bar no-print">
    {pathname !== "/kpi" && <Link href={dashboardHref} prefetch={false}><ArrowLeft size={16}/>Dashboard</Link>}
    <button type="button" disabled={refreshing} onClick={async () => {
      setRefreshing(true);
      // Reload client-side queues as well as server data, preserving the current URL.
      try { await refreshKpiReport(); } finally { window.location.reload(); }
    }}><RefreshCw size={16} className={refreshing ? "refresh-spinning" : ""}/>{refreshing ? "Uppdaterar…" : "Uppdatera"}</button>
    <span role="status" className="sr-only">{refreshing ? "Hämtar aktuellt underlag för samma vy och filter." : ""}</span>
  </div>;
}
