import type { Metadata } from "next";
import { Suspense } from "react";
import { KpiRefresh } from "../_components/kpi-refresh";

export const metadata: Metadata = {
  title: "Humla KPI",
  description: "Verksamhetsstyrning för transport, fordon och personal.",
};

export default function KpiLayout({ children }: { children: React.ReactNode }) {
  return <><Suspense fallback={null}><KpiRefresh/></Suspense>{children}</>;
}
