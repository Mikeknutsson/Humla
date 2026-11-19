import Link from 'next/link';
import {ChevronRight, ClipboardCheck, PackageCheck, Truck} from 'lucide-react';
import styles from './kpi-followup-nav.module.css';

export const settlementPath = '/kpi/transportadministration/avrakningskontroll';

export const materialPath = '/kpi/transportadministration/materialkontroll-johanssons';

export function KpiTransportAdministrationNav({active = false, onNavigate}: {
  active?: boolean | 'material';
  onNavigate?: () => void;
}) {
  return <details className={styles.followup} open={!!active}>
    <summary><Truck size={18}/>Transportadministration<ChevronRight size={16} className={styles.chevron}/></summary>
    <div className={styles.links}>
      <Link href={settlementPath} prefetch={false} className={active === true ? 'active' : undefined}
        aria-current={active === true ? 'page' : undefined} onClick={onNavigate}>
        <ClipboardCheck size={16}/>Avräkningskontroll
      </Link>
      <Link href={materialPath} prefetch={false} className={active === 'material' ? 'active' : undefined}
        aria-current={active === 'material' ? 'page' : undefined} onClick={onNavigate}>
        <PackageCheck size={16}/>Materialkontroll Johanssons
      </Link>
    </div>
  </details>;
}
