'use server';

import {revalidatePath} from 'next/cache';
import {archiveOffer, findArchivedOffer, offerFingerprint} from '@/lib/hub/ton-price-offer-archive';
import {tonPricePath} from '@/app/_components/kpi-transport-administration-nav';

import {advancedOfferLines, priceQuarryOffer, type QuarryPricing, type OfferDetails, type OfferLine} from '@/lib/hub/ton-price-offer';
import {readWorkifyMaterialPrices} from '@/lib/hub/workify-material-prices';
import {deliveryPlanRoute, type DeliveryPlanLine} from '@/lib/hub/ton-price-delivery-plan';
import {tonPriceOfferPdf} from '@/lib/hub/ton-price-offer-pdf';
import {tonPriceAccess} from './access';
import {readPriceBank} from '@/lib/hub/material-price-bank-server';
import {effectiveSiteRates, stockholmDate, type MaterialSite, type SiteRate} from '@/lib/hub/material-price-bank';
import {compareQuarries} from '@/lib/hub/quarry-comparison';
import {calculateTonPrices, offerTermsMaxLength, type Round, type TonPriceDraft} from '@/lib/hub/ton-price';

type Access = NonNullable<Awaited<ReturnType<typeof tonPriceAccess>>>;

export async function loadWorkifyCustomers() {
  const access = await tonPriceAccess();
  if (!access) return null;
  const {data,error} = await access.db.rpc('hub_ton_price_workify_customers',{p_tenant_id:access.tenantId});
  if (error) return null;
  return (data as {name: string}[]).map(row => row.name).sort((a,b) => a.localeCompare(b,'sv'));
}

async function prepareTonPrices(access: Access | null, draft: TonPriceDraft, includeSites = false) {
  if (!access) return {error: 'Behörighet saknas.'};
  if (!draft || !Array.isArray(draft.rounds) || !Array.isArray(draft.materials) ||
    !Array.isArray(draft.vehicles) || draft.rounds.length > 30 || draft.materials.length > 100 ||
    draft.vehicles.length !== 3 || !['reference', 'bk1', 'bk4'].includes(draft.profile)) {
    return {error: 'Kalkylen kunde inte läsas.'};
  }
  try {
    const usesBankRates = draft.materials.some(row => row.bankRateId);
    const usesBankSites = includeSites && draft.rounds.some(round => round.pickupSiteId || round.deliverySiteId);
    let sites: MaterialSite[] = [];
    if (usesBankRates || usesBankSites) {
      const bank = await readPriceBank(access);
      if (!bank) return {error: 'Prisbanken kunde inte hämtas.'};
      sites = bank.sites;
      const date = draft.priceDate || stockholmDate();
      if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return {error: 'Ange ett giltigt prisdatum.'};
      const byRate = new Map(effectiveSiteRates(bank.rates, date).map(rate => [rate.id, rate]));
      const byRound = new Map(draft.rounds.map(round => [round.id, round]));
      for (const row of draft.materials) {
        if (!row.bankRateId) continue;
        const rate = byRate.get(row.bankRateId);
        const round = byRound.get(row.roundId);
        if (!rate || rate.unit !== 'ton' || rate.siteId !== (rate.kind === 'tip' ? round?.deliverySiteId : round?.pickupSiteId)) {
          return {error: 'En vald prisrad gäller inte för platsen och datumet. Välj materialet igen.'};
        }
        row.purchase = String(rate.price);
        row.bankKind = rate.kind;
        row.name = rate.material;
      }
    }
    return {result: calculateTonPrices(draft), sites};
  } catch {
    return {error: 'Kalkylen innehåller ogiltiga värden.'};
  }
}

export async function recalculateTonPrices(draft: TonPriceDraft) {
  const {result,error} = await prepareTonPrices(await tonPriceAccess(),draft);
  return {result,error};
}

async function offerDocuments(access: Access, delivery: string, priceDate: string, details: OfferDetails, lines: OfferLine[], plan: DeliveryPlanLine[]) {
  const date = stockholmDate();
  const {customer,project,validity,terms} = details;
  const fingerprint = offerFingerprint([date,delivery,priceDate,customer,project,validity,terms,lines,plan]);
  try {
    let id = await findArchivedOffer(access,fingerprint);
    if (!id) {
      const [pdf, deliveryPlan] = await Promise.all([
        tonPriceOfferPdf(delivery,date,details,lines),
        tonPriceOfferPdf(delivery,date,details,[],plan,priceDate),
      ]);
      id = await archiveOffer(access,{
        offer_date:date, customer, project,
        destinations:[...new Set(plan.map(row => row.delivery).filter(Boolean))],
        materials:[...new Set(lines.map(line => line.material))],
      },fingerprint,pdf,deliveryPlan);
    }
    revalidatePath(tonPricePath);
    return {id};
  } catch (error) {
    console.error('Could not archive ton-price offer',error instanceof Error ? error.message : 'database error');
    return {error:'Offerten kunde inte sparas i arkivet. Försök igen.'};
  }
}

type QuarryMaterial = {name: string; tonnes: string};

async function compareForAccess(access: Access, date: string, materials: QuarryMaterial[], rounds: Round[], draft: TonPriceDraft, kind: SiteRate['kind']) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || materials.length > 100 || rounds.length > 100 ||
    !['reference','bk1','bk4'].includes(draft.profile) || draft.vehicles.length !== 3 ||
    (kind !== 'tip' && kind !== 'purchase')) return {error:'Ogiltigt jämförelseunderlag.'};
  const bank = await readPriceBank(access);
  if (!bank) return {error:'Prisbanken kunde inte hämtas.'};
  try {return {comparison:compareQuarries(bank,date,materials,rounds,draft,kind)};}
  catch {return {error:'Kontrollera mil, ekipage och returparametrar.'};}
}

export async function calculateQuarryComparison(date: string, materials: QuarryMaterial[], rounds: Round[], draft: TonPriceDraft, kind: SiteRate['kind'] = 'purchase') {
  const access = await tonPriceAccess();
  if (!access) return {error:'Behörighet saknas.',comparison:undefined};
  return compareForAccess(access,date,materials,rounds,draft,kind);
}

function validOfferDetails(details: OfferDetails) {
  return details && [details.customer, details.project, details.validity]
    .every(value => typeof value === 'string' && value.length <= 240) &&
    typeof details.terms === 'string' && details.terms.length <= offerTermsMaxLength;
}

export async function downloadQuarryOffer(
  date: string, materials: QuarryMaterial[], rounds: Round[], draft: TonPriceDraft,
  delivery: string, pricing: QuarryPricing, expectedPrices: number[], details: OfferDetails, kind: SiteRate['kind'] = 'purchase',
) {
  if (!pricing || !['markup','workify'].includes(pricing.mode) || typeof pricing.markup !== 'string' ||
    !pricing.overrides || typeof pricing.overrides !== 'object' || Object.keys(pricing.overrides).length > 100 ||
    Object.values(pricing.overrides).some(value => !value || typeof value.markup !== 'string' || typeof value.source !== 'string' ||
      (value.source !== '' && value.source !== 'markup' && !/^workify:[\w-]{1,80}$/.test(value.source)))) {
    return {error:'Kontrollera offertens prisval.'};
  }
  if (typeof delivery !== 'string' || !delivery.trim() || delivery.length > 240 ||
    !validOfferDetails(details)) {
    return {error:'Kontrollera offertuppgifterna.'};
  }
  const access = await tonPriceAccess();
  if (!access) return {error:'Behörighet saknas.'};
  const usesWorkify = kind === 'purchase' &&
    (pricing.mode === 'workify' || Object.values(pricing.overrides).some(value => value.source.startsWith('workify:')));
  const [result,workifyPrices] = await Promise.all([
    compareForAccess(access,date,materials,rounds,draft,kind),
    usesWorkify ? readWorkifyMaterialPrices(access) : [],
  ]);
  if (!result.comparison) return {error:result.error};
  if (!workifyPrices) return {error:'Workifys standardpriser kunde inte hämtas.'};
  const priced = priceQuarryOffer(result.comparison,pricing,workifyPrices);
  const lines = priced.flatMap(row => row.line ? [row.line] : []);
  if (!lines.length || lines.length !== materials.length || lines.some(line => !Number.isFinite(line.unitPrice) || (!line.isTip && line.unitPrice < 0))) {
    return {error:'Kontrollera att alla valda material har ett giltigt offertpris.'};
  }
  if (!Array.isArray(expectedPrices) || lines.length !== expectedPrices.length ||
    lines.some((line,index) => line.unitPrice !== expectedPrices[index])) {
    return {error:'Offertpriserna har ändrats. Räkna om kalkylen och kontrollera priserna.'};
  }
  const vehicle = draft.vehicles.find(row => row.id === 'trailer')?.name ?? 'Bil + kärra';
  const plan = result.comparison.map((row,index) => {
    const winner = row.options[0];
    const {site,round,time,rate,freight} = winner;
    return {
      ...lines[index], ...deliveryPlanRoute(round,time,vehicle,new Map([[site.id,site]])),
      material:rate.material === row.material ? row.material : row.material + ' · ' + rate.material,
      tip:kind === 'tip', tippingDestination:kind === 'tip',
      purchase:rate.price, materialPrice:priced[index].materialPrice!, pricingSource:priced[index].pricingSource, freight,
    };
  });
  return offerDocuments(access,delivery,date,details,lines,plan);
}

export async function downloadAdvancedOffer(draft: TonPriceDraft, expectedPrices: number[]) {
  if (!validOfferDetails(draft)) return {error:'Kontrollera offertuppgifterna.'};
  const access = await tonPriceAccess();
  if (!access) return {error:'Behörighet saknas.'};
  const {result,sites,error} = await prepareTonPrices(access,draft,true);
  if (!result) return {error};
  const lines = advancedOfferLines(draft,result);
  if (!lines.length || lines.length !== draft.materials.length) return {error:'Kontrollera kalkylen innan du skapar offerten.'};
  if (!Array.isArray(expectedPrices) || lines.length !== expectedPrices.length ||
    lines.some((line,index) => line.unitPrice !== expectedPrices[index])) {
    return {error:'Offertpriserna har ändrats. Räkna om kalkylen och kontrollera priserna.'};
  }
  const rounds = new Map(draft.rounds.map(round => [round.id,round]));
  const times = new Map(result.rounds.map(round => [round.id,round.result]));
  const bySite = new Map(sites.map(site => [site.id,site]));
  const plan = result.materials.map((row,index) => {
    const input = draft.materials[index];
    const round = rounds.get(input.roundId)!;
    const vehicle = draft.vehicles.find(option => option.id === input.vehicleId)!.name;
    const material = lines[index].material;
    return {
      ...lines[index], ...deliveryPlanRoute(round,times.get(round.id)!,vehicle,bySite),
      material:input.bankRateId && input.name !== material ? material + ' · ' + input.name : material,
      tip:input.bankKind === 'tip', tippingDestination:Boolean(round.deliverySiteId),
      purchase:row.price!.purchase, materialPrice:row.price!.sale, freight:row.selected!.freight,
    };
  });
  const destinations = new Set(draft.materials.map(input => rounds.get(input.roundId)!.delivery.trim()));
  return offerDocuments(access,destinations.size === 1 ? [...destinations][0] : '',draft.priceDate || stockholmDate(),draft,lines,plan);
}
