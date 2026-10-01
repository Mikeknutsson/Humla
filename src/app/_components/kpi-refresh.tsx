"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState } from "react";
import { ArrowLeft, RefreshCw } from "lucide-react";

export function KpiRefresh() {
  const pathname = usePathname();
  const [refreshing, setRefreshing] = useState(false);
  if (pathname === "/kpi/login") return null;

  return <div className="kpi-refresh-bar no-print">
    {pathname !== "/kpi" && <Link href="/kpi" prefetch={false}><ArrowLeft size={16}/>Dashboard</Link>}
    <button type="button" disabled={refreshing} onClick={() => {
      setRefreshing(true);
      // Reload client-side queues as well as server data, preserving the current URL.
      window.location.reload();
    }}><RefreshCw size={16} className={refreshing ? "refresh-spinning" : ""}/>{refreshing ? "Uppdaterar…" : "Uppdatera"}</button>
    <span role="status" className="sr-only">{refreshing ? "Hämtar aktuellt underlag för samma vy och filter." : ""}</span>
  </div>;
}
