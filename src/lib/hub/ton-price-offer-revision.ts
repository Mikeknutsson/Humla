import type {SiteRate} from './material-price-bank';
import type {Leg, ReturnLoad, TonPriceDraft} from './ton-price';
import type {QuarryPricing, WorkifyOfferPrice} from './ton-price-offer';

type ProjectLocation = {
  address: string;
  id?: string;
  point?: {lat: number; lng: number};
};

export type QuarryOfferSettings = {
  destination: ProjectLocation;
  kind: SiteRate['kind'];
  pricing: QuarryPricing;
  routes: Record<string, Partial<Record<'outbound' | 'inbound', Leg>>>;
  withoutReturn: string[];
  returnLoad?: ReturnLoad;
};

export type OfferSnapshot = {draft: TonPriceDraft} & (
  {mode: 'advanced'} |
  {mode: 'quick'; quick: QuarryOfferSettings; workifyPrices: WorkifyOfferPrice[]}
);

export type LegacyOfferSettings = {
  kind?: SiteRate['kind'];
  projectAddress?: string;
  date?: string;
  validity?: string;
  pricing?: QuarryPricing;
  terms?: string;
};

export type OfferRevision = {
  id: string;
  offer_date: string;
  customer: string;
  project: string;
  destinations: string[];
  materials: string[];
  calculation_snapshot: OfferSnapshot | null;
  legacy?: LegacyOfferSettings;
};

export function quotedMaterial(materials: string[], name: string) {
  const normalized = name.trim().toLocaleLowerCase('sv');
  return materials.some(material => material.trim().toLocaleLowerCase('sv') === normalized);
}
