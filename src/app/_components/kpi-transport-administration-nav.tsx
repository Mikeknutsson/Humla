import Link from 'next/link';
import {Calculator, ChevronRight, ClipboardCheck, Database, FileText, PackageCheck, Scale, Truck} from 'lucide-react';
import styles from './kpi-followup-nav.module.css';

export const settlementPath = '/kpi/transportadministration/avrakningskontroll';

export const materialPath = '/kpi/transportadministration/materialkontroll-johanssons';

export const tonPricePath = '/kpi/transportadministration/tonpriskalkyl';

export const materialPriceBankPath = '/kpi/transportadministration/prisbank';

export const deliveryCheckPath = '/kpi/transportadministration/leveranskontroll';

export const transportDocumentPath = '/kpi/transportadministration/transportdokument';

export type TransportAdministrationPage = boolean | 'material' | 'ton-price' | 'price-bank' | 'delivery-check' | 'transport-document';

export function KpiTransportAdministrationNav({active = false, onNavigate}: {
  active?: TransportAdministrationPage;
  onNavigate?: () => void;
}) {
  return <details className={styles.followup} open={!!active}>
    <summary><Truck size={18}/>Transportledning<ChevronRight size={16} className={styles.chevron}/></summary>
    <div className={styles.links}>
      <Link href={transportDocumentPath} prefetch={false} className={active === 'transport-document' ? 'active' : undefined}
        aria-current={active === 'transport-document' ? 'page' : undefined} onClick={onNavigate}>
        <FileText size={16}/>Transportdokument
      </Link>
      <Link href={settlementPath} prefetch={false} className={active === true ? 'active' : undefined}
        aria-current={active === true ? 'page' : undefined} onClick={onNavigate}>
        <ClipboardCheck size={16}/>Avräkningskontroll
      </Link>
      <Link href={materialPath} prefetch={false} className={active === 'material' ? 'active' : undefined}
        aria-current={active === 'material' ? 'page' : undefined} onClick={onNavigate}>
        <PackageCheck size={16}/>Materialkontroll Johanssons
      </Link>
      <Link href={deliveryCheckPath} prefetch={false} className={active === 'delivery-check' ? 'active' : undefined}
        aria-current={active === 'delivery-check' ? 'page' : undefined} onClick={onNavigate}>
        <Scale size={16}/>Leveranskontroll Sortergården
      </Link>
      <Link href={tonPricePath} prefetch={false} className={active === 'ton-price' ? 'active' : undefined}
        aria-current={active === 'ton-price' ? 'page' : undefined} onClick={onNavigate}>
        <Calculator size={16}/>Tonpriskalkyl
      </Link>
      <Link href={materialPriceBankPath} prefetch={false} className={active === 'price-bank' ? 'active' : undefined}
        aria-current={active === 'price-bank' ? 'page' : undefined} onClick={onNavigate}>
        <Database size={16}/>Prisbank
      </Link>
    </div>
  </details>;
}
