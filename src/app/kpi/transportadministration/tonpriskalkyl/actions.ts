'use server';

import {revalidatePath} from 'next/cache';
import {archiveOffer, findArchivedOffer, offerFingerprint} from '@/lib/hub/ton-price-offer-archive';
import {tonPricePath} from '@/app/_components/kpi-transport-administration-nav';

import {advancedOfferLines, offerLines, parseOfferMarkup, type OfferDetails, type OfferLine} from '@/lib/hub/ton-price-offer';
import {deliveryPlanRoute, type DeliveryPlanLine} from '@/lib/hub/ton-price-delivery-plan';
import {tonPriceOfferPdf} from '@/lib/hub/ton-price-offer-pdf';
import {tonPriceAccess} from './access';
import {readPriceBank} from '@/lib/hub/material-price-bank-server';
import {effectiveSiteRates, stockholmDate, type MaterialSite} from '@/lib/hub/material-price-bank';
import {compareQuarries} from '@/lib/hub/quarry-comparison';
import {calculateTonPrices, type Round, type TonPriceDraft} from '@/lib/hub/ton-price';

type Access = NonNullable<Awaited<ReturnType<typeof tonPriceAccess>>>;

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

async function compareForAccess(access: Access, date: string, materials: QuarryMaterial[], rounds: Round[], draft: TonPriceDraft) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || materials.length > 100 || rounds.length > 100 ||
    !['reference','bk1','bk4'].includes(draft.profile) || draft.vehicles.length !== 3) return {error:'Ogiltigt jämförelseunderlag.'};
  const bank = await readPriceBank(access);
  if (!bank) return {error:'Prisbanken kunde inte hämtas.'};
  try {return {comparison:compareQuarries(bank,date,materials,rounds,draft)};}
  catch {return {error:'Kontrollera mil, ekipage och returparametrar.'};}
}

export async function calculateQuarryComparison(date: string, materials: QuarryMaterial[], rounds: Round[], draft: TonPriceDraft) {
  const access = await tonPriceAccess();
  if (!access) return {error:'Behörighet saknas.',comparison:undefined};
  return compareForAccess(access,date,materials,rounds,draft);
}

function validOfferDetails(details: OfferDetails) {
  return details && [details.customer, details.project, details.validity, details.terms]
    .every(value => typeof value === 'string' && value.length <= 240);
}

export async function downloadQuarryOffer(
  date: string, materials: QuarryMaterial[], rounds: Round[], draft: TonPriceDraft,
  delivery: string, markupText: string, expectedPrices: number[], details: OfferDetails,
) {
  const markup = parseOfferMarkup(markupText);
  if (markup === null) return {error:'Ange ett påslag mellan 0 och 1 000 %.'};
  if (typeof delivery !== 'string' || !delivery.trim() || delivery.length > 240 ||
    !validOfferDetails(details)) {
    return {error:'Kontrollera offertuppgifterna.'};
  }
  const access = await tonPriceAccess();
  if (!access) return {error:'Behörighet saknas.'};
  const result = await compareForAccess(access,date,materials,rounds,draft);
  if (!result.comparison) return {error:result.error};
  const lines = offerLines(result.comparison,markup);
  if (!lines.length || lines.length !== materials.length || lines.some(line => !Number.isFinite(line.unitPrice) || line.unitPrice < 0)) {
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
      tip:false, purchase:rate.price, materialPrice:rate.price * (1 + markup / 100), freight,
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
    return {
      ...lines[index], ...deliveryPlanRoute(round,times.get(round.id)!,vehicle,bySite),
      tip:input.bankKind === 'tip', tippingDestination:Boolean(round.deliverySiteId),
      purchase:row.price!.purchase, materialPrice:row.price!.sale, freight:row.selected!.freight,
    };
  });
  const destinations = new Set(draft.materials.map(input => rounds.get(input.roundId)!.delivery.trim()));
  return offerDocuments(access,destinations.size === 1 ? [...destinations][0] : '',draft.priceDate || stockholmDate(),draft,lines,plan);
}
