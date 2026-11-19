import {redirect} from 'next/navigation';
import {settlementPath} from '@/app/_components/kpi-transport-administration-nav';

export default function TransportAdministration() {
  redirect(settlementPath);
}
