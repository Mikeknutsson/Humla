import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Humla KPI",
  description: "Verksamhetsstyrning för transport, fordon och personal.",
};

export default function KpiLayout({ children }: { children: React.ReactNode }) {
  return children;
}
