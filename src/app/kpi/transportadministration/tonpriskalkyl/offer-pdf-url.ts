import {tonPricePath} from '@/app/_components/kpi-transport-administration-nav';

export const offerPdfUrl = (id: string, document: 'offert' | 'leveransplan') =>
  `${tonPricePath}/offertarkiv/${id}/${document}`;
