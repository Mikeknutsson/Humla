import type {SiteRate} from './material-price-bank';
import type {Leg, ReturnLoad, Round, TonPriceDraft} from './ton-price';
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

export type QuarryOfferJob = {
  kind: SiteRate['kind'];
  address: string;
  materials: {name: string; tonnes: string}[];
  rounds: Round[];
  pricing: QuarryPricing;
  expectedPrices: number[];
  withoutReturn: string[];
  returnLoad?: ReturnLoad;
};

export type QuotedJob = {kind: SiteRate['kind']; address: string; materials: string[]};
export const maxQuarryOfferJobs = 20;

export type OfferSnapshot = {draft: TonPriceDraft; quotedJobs?: QuotedJob[]; unscopedMaterials?: string[]} & (
  {mode: 'advanced'} |
  {mode: 'quick'; quick: QuarryOfferSettings; additionalJobs?: QuarryOfferSettings[]; workifyPrices: WorkifyOfferPrice[]}
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

export function sameOfferJob(a: Pick<QuotedJob,'kind' | 'address'>, b: Pick<QuotedJob,'kind' | 'address'>) {
  const key = (value: string) => value.trim().replace(/\s+/g,' ').toLocaleLowerCase('sv');
  return a.kind === b.kind && key(a.address) === key(b.address);
}

export function priorJobMaterials(revision: OfferRevision | undefined | null, job: Pick<QuotedJob,'kind' | 'address'>) {
  if (!revision) return [];
  const snapshot = revision.calculation_snapshot;
  if (snapshot?.quotedJobs) return [...(snapshot.unscopedMaterials ?? []),
    ...snapshot.quotedJobs.filter(quoted => sameOfferJob(quoted,job)).flatMap(row => row.materials)];
  const legacy = revision.legacy;
  const original = snapshot?.mode === 'quick'
    ? {kind:snapshot.quick.kind,address:snapshot.quick.destination.address}
    : legacy?.kind && legacy.projectAddress ? {kind:legacy.kind,address:legacy.projectAddress} : undefined;
  return !original || sameOfferJob(original,job) ? revision.materials : [];
}
