import 'server-only';

import {createHash} from 'node:crypto';
import type {createClient as createSessionClient} from '@/lib/supabase/server';

import type {OfferRevision, OfferSnapshot} from './ton-price-offer-revision';

type Access = {db: Awaited<ReturnType<typeof createSessionClient>>; tenantId: string; userId: string};
type ArchiveEntry = {
  id: string;
  offer_date: string;
  customer: string;
  project: string;
  destinations: string[];
  materials: string[];
  source_offer_id: string | null;
};

const fields = 'id,offer_date,customer,project,destinations,materials';
const table = 'hub_ton_price_offers';
export const offerPageSize = 25;

export async function readOffers(access: Access, page: number) {
  const from = page * offerPageSize;
  const {data,error} = await access.db.from(table).select(fields+',source_offer_id')
    .eq('tenant_id',access.tenantId).order('created_at',{ascending:false}).order('id',{ascending:false})
    .range(from,from+offerPageSize).returns<ArchiveEntry[]>();
  if (error || !data) return null;
  return {entries:data.slice(0,offerPageSize),hasNext:data.length > offerPageSize};
}

export async function readOfferRevision(access: Access, id: string) {
  if (!/^[\da-f]{8}(?:-[\da-f]{4}){3}-[\da-f]{12}$/i.test(id)) return null;
  const {data,error} = await access.db.from(table).select(fields+',calculation_snapshot')
    .eq('tenant_id',access.tenantId).eq('id',id).maybeSingle().returns<OfferRevision>();
  if (error) throw error;
  return data;
}

export async function openOfferRevision(access: Access, id: string) {
  const revision = await readOfferRevision(access,id);
  if (!revision || revision.calculation_snapshot) return revision;
  try {
    const [offer,plan] = await Promise.all([readOfferPdf(access,id,'offert'),readOfferPdf(access,id,'leveransplan')]);
    if (offer && plan) {
      const {readLegacyOfferSettings} = await import('./ton-price-offer-legacy');
      revision.legacy = await readLegacyOfferSettings(offer,plan);
    }
  } catch {
    // The saved PDFs are still available to review manually.
  }
  return revision;
}

export async function findArchivedOffer(access: Access, fingerprint: string) {
  const {data,error} = await access.db.from(table).select('id')
    .eq('tenant_id',access.tenantId).eq('fingerprint',fingerprint).maybeSingle();
  if (error) throw error;
  return data?.id as string | undefined;
}

export function offerFingerprint(snapshot: unknown) {
  return createHash('sha256').update(JSON.stringify(snapshot)).digest('hex');
}

export async function archiveOffer(access: Access, entry: Omit<ArchiveEntry,'id'>, fingerprint: string, offer: Uint8Array, plan: Uint8Array, snapshot: OfferSnapshot) {
  const {error} = await access.db.from(table).upsert({
    ...entry, calculation_snapshot:snapshot, tenant_id:access.tenantId, created_by:access.userId, fingerprint,
    offer_pdf:'\\x'+Buffer.from(offer).toString('hex'),
    delivery_plan_pdf:'\\x'+Buffer.from(plan).toString('hex'),
  },{onConflict:'tenant_id,fingerprint',ignoreDuplicates:true});
  if (error) throw error;
  const id = await findArchivedOffer(access,fingerprint);
  if (!id) throw new Error('Archived offer could not be verified');
  return id;
}

export async function readOfferPdf(access: Access, id: string, document: 'offert' | 'leveransplan') {
  const field = document === 'offert' ? 'offer_pdf' : 'delivery_plan_pdf';
  const {data,error} = await access.db.from(table).select(`pdf:${field}`).eq('tenant_id',access.tenantId).eq('id',id).maybeSingle();
  if (error) throw error;
  const pdf = data?.pdf;
  return typeof pdf === 'string' && pdf.startsWith('\\x') ? Buffer.from(pdf.slice(2),'hex') : null;
}
