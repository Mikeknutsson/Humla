'use client';
import { useEffect, useState } from 'react';

export function ProjectReportLoading({ monthHref }: { monthHref: string }) {
  const [seconds, setSeconds] = useState(0);
  useEffect(() => {
    const started = performance.now();
    const timer = setInterval(() => setSeconds(Math.floor((performance.now() - started) / 1000)), 1000);
    return () => clearInterval(timer);
  }, []);
  return <section className="panel" aria-busy="true" role="status">
    <h2>Hämtar projektunderlag från Humla Hub…</h2>
    <p>{seconds < 15 ? 'Räknar på hela ditt urval.' : `Hämtningen pågår fortfarande (${seconds} sekunder). Stora perioder tar längre tid.`} Inga preliminära belopp visas.</p>
    <p><a href={monthHref}>Avbryt laddningen och visa en månad</a></p>
  </section>;
}
