import Link from 'next/link';
import {Calculator, ChevronRight, ClipboardCheck, PackageCheck, Truck} from 'lucide-react';
import styles from './kpi-followup-nav.module.css';

export const settlementPath = '/kpi/transportadministration/avrakningskontroll';

export const materialPath = '/kpi/transportadministration/materialkontroll-johanssons';

export const tonPricePath = '/kpi/transportadministration/tonpriskalkyl';

export type TransportAdministrationPage = boolean | 'material' | 'ton-price';

export function KpiTransportAdministrationNav({active = false, onNavigate}: {
  active?: TransportAdministrationPage;
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
      <Link href={tonPricePath} prefetch={false} className={active === 'ton-price' ? 'active' : undefined}
        aria-current={active === 'ton-price' ? 'page' : undefined} onClick={onNavigate}>
        <Calculator size={16}/>Tonpriskalkyl
      </Link>
    </div>
  </details>;
}
