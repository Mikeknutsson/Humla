import Link from 'next/link';
import {ChevronRight, ClipboardCheck, Truck} from 'lucide-react';
import styles from './kpi-followup-nav.module.css';

export const settlementPath = '/kpi/transportadministration/avrakningskontroll';

export function KpiTransportAdministrationNav({active = false, onNavigate}: {
  active?: boolean;
  onNavigate?: () => void;
}) {
  return <details className={styles.followup} open={active}>
    <summary><Truck size={18}/>Transportadministration<ChevronRight size={16} className={styles.chevron}/></summary>
    <div className={styles.links}>
      <Link href={settlementPath} prefetch={false} className={active ? 'active' : undefined}
        aria-current={active ? 'page' : undefined} onClick={onNavigate}>
        <ClipboardCheck size={16}/>Avräkningskontroll
      </Link>
    </div>
  </details>;
}
