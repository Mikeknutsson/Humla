'use server';

import {revalidatePath} from 'next/cache';
import {archiveOffer, findArchivedOffer, offerFingerprint, openOfferRevision} from '@/lib/hub/ton-price-offer-archive';
import {tonPricePath} from '@/app/_components/kpi-transport-administration-nav';

import {advancedOfferLines, priceQuarryOffer, type OfferDetails, type OfferSection} from '@/lib/hub/ton-price-offer';
import {maxQuarryOfferJobs, priorJobMaterials, quotedMaterial, sameOfferJob, type OfferRevision, type OfferSnapshot, type QuarryOfferJob, type QuarryOfferSettings} from '@/lib/hub/ton-price-offer-revision';
import {readWorkifyMaterialPrices} from '@/lib/hub/workify-material-prices';
import {deliveryPlanRoute, type DeliveryPlanLine} from '@/lib/hub/ton-price-delivery-plan';
import {tonPriceOfferPdf} from '@/lib/hub/ton-price-offer-pdf';
import {tonPriceAccess} from './access';
import {readPriceBank} from '@/lib/hub/material-price-bank-server';
import {effectiveSiteRates, stockholmDate, type MaterialPriceBank, type MaterialSite, type SiteRate} from '@/lib/hub/material-price-bank';
import {compareQuarries} from '@/lib/hub/quarry-comparison';
import {calculateStartLeg, calculateTonPrices, offerTermsMaxLength, type Round, type TonPriceDraft} from '@/lib/hub/ton-price';

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
    const usedRounds = new Set(draft.materials.map(row => row.roundId));
    if (draft.rounds.some(round => usedRounds.has(round.id) && !calculateStartLeg(round))) {
      return {error:'Ange startsträckan från Pukavik för varje använd runda.'};
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

async function offerDocuments(access: Access, priceDate: string, details: OfferDetails, sections: OfferSection[], plan: DeliveryPlanLine[], snapshot: OfferSnapshot, source: OfferRevision | null) {
  const date = stockholmDate();
  const {customer,project,validity,terms} = details;
  for (const section of sections) {
    const prior = priorJobMaterials(source,section);
    if (section.lines.some(line => quotedMaterial(prior,line.material))) {
      return {error:'En vald fraktion finns redan för samma uppdrag och adress.'};
    }
  }
  const former = source?.calculation_snapshot?.quotedJobs;
  const old = source?.calculation_snapshot;
  const legacyKind = source?.legacy?.kind;
  const legacyAddress = source?.legacy?.projectAddress;
  const previousJobs = former ?? (source && old?.mode === 'quick'
    ? [{kind:old.quick.kind,address:old.quick.destination.address,materials:source.materials}]
    : source && legacyKind && legacyAddress ? [{kind:legacyKind,address:legacyAddress,materials:source.materials}] : []);
  const lines = sections.flatMap(section => section.lines);
  snapshot.quotedJobs = [...previousJobs,...sections.map(({kind,address,lines}) => ({kind,address,materials:lines.map(line => line.material)}))];
  snapshot.unscopedMaterials = old?.unscopedMaterials ?? (source && !previousJobs.length ? source.materials : undefined);
  const allMaterials = [...new Set([...(source?.materials ?? []),...lines.map(line => line.material)])];
  if (allMaterials.length > 100) return {error:'En offert kan innehålla högst 100 olika material inklusive kompletteringar.'};
  const reference = source ? {date:source.offer_date,id:source.id} : undefined;
  const fingerprint = offerFingerprint([date,priceDate,customer,project,validity,terms,sections,plan,snapshot,reference]);
  try {
    let id = await findArchivedOffer(access,fingerprint);
    if (!id) {
      const [pdf, deliveryPlan] = await Promise.all([
        tonPriceOfferPdf('',date,details,lines,undefined,undefined,reference,sections),
        tonPriceOfferPdf('',date,details,[],plan,priceDate,reference),
      ]);
      id = await archiveOffer(access,{
        offer_date:date, customer, project,
        destinations:[...new Set(sections.map(section => section.address).filter(Boolean))],
        materials:allMaterials,
        source_offer_id:source?.id ?? null,
      },fingerprint,pdf,deliveryPlan,snapshot);
    }
    revalidatePath(tonPricePath);
    return {id};
  } catch (error) {
    console.error('Could not archive ton-price offer',error instanceof Error ? error.message : 'database error');
    return {error:'Offerten kunde inte sparas i arkivet. Försök igen.'};
  }
}

async function revisionSource(access: Access, id?: string) {
  if (!id) return {source:null};
  try {
    const source = await openOfferRevision(access,id);
    if (source) return {source};
  } catch {
    // Do not create an unlinked offer when the archive cannot be read.
  }
  return {source:null,error:'Offerten som ska kompletteras kunde inte hämtas. Öppna den igen från offertarkivet.'};
}

type QuarryMaterial = {name: string; tonnes: string};

function compareBank(bank: MaterialPriceBank, date: string, materials: QuarryMaterial[], rounds: Round[], draft: TonPriceDraft, kind: SiteRate['kind']) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || materials.length > 100 || rounds.length > 100 ||
    !['reference','bk1','bk4'].includes(draft.profile) || draft.vehicles.length !== 3 ||
    (kind !== 'tip' && kind !== 'purchase')) return {error:'Ogiltigt jämförelseunderlag.'};
  try {return {comparison:compareQuarries(bank,date,materials,rounds,draft,kind)};}
  catch {return {error:'Kontrollera mil, ekipage och returparametrar.'};}
}

export async function calculateQuarryComparison(date: string, materials: QuarryMaterial[], rounds: Round[], draft: TonPriceDraft, kind: SiteRate['kind'] = 'purchase') {
  const access = await tonPriceAccess();
  if (!access) return {error:'Behörighet saknas.',comparison:undefined};
  const bank = await readPriceBank(access);
  return bank ? compareBank(bank,date,materials,rounds,draft,kind) : {error:'Prisbanken kunde inte hämtas.'};
}

function validOfferDetails(details: OfferDetails) {
  return details && [details.customer, details.project, details.validity]
    .every(value => typeof value === 'string' && value.length <= 240) &&
    typeof details.terms === 'string' && details.terms.length <= offerTermsMaxLength;
}

function prepareQuarryJob(
  bank: MaterialPriceBank, date: string, job: QuarryOfferJob, draft: TonPriceDraft,
  workifyPrices: Awaited<ReturnType<typeof readWorkifyMaterialPrices>>,
  previousJobs: QuarryOfferSettings[],
) {
  const {kind, address, pricing, materials, rounds, expectedPrices} = job;
  if (!pricing || !['markup','workify'].includes(pricing.mode) || typeof pricing.markup !== 'string' ||
    !pricing.overrides || typeof pricing.overrides !== 'object' || Object.keys(pricing.overrides).length > 100 ||
    Object.values(pricing.overrides).some(value => !value || typeof value.markup !== 'string' || typeof value.source !== 'string' ||
      (value.source !== '' && value.source !== 'markup' && !/^workify:[\w-]{1,80}$/.test(value.source)))) {
    return {error:'Kontrollera uppdragets prisval.'};
  }
  if (typeof address !== 'string' || !address.trim() || address.length > 240 || !Array.isArray(rounds) ||
    rounds.some(round => (kind === 'tip' ? round?.pickup : round?.delivery) !== address)) {
    return {error:'Kontrollera adressen för uppdraget och räkna om rutten.'};
  }
  const usesWorkify = kind === 'purchase' &&
    (pricing.mode === 'workify' || Object.values(pricing.overrides).some(value => value.source.startsWith('workify:')));
  const result = compareBank(bank,date,materials,rounds,draft,kind);
  if (!result.comparison) return {error:result.error};
  if (usesWorkify && !workifyPrices) return {error:'Workifys standardpriser kunde inte hämtas.'};
  const priced = priceQuarryOffer(result.comparison,pricing,workifyPrices ?? []);
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
  const tip = kind === 'tip';
  const first = result.comparison[0].options[0].round;
  const routes: QuarryOfferSettings['routes'] = {};
  const destination = {address,id:tip ? first.pickupPlaceId : first.deliveryPlaceId,
    point:tip ? first.pickupPoint : first.deliveryPoint};
  const matching = previousJobs.find(previous => sameOfferJob({kind:previous.kind,address:previous.destination.address},{kind,address}) &&
    previous.destination.id === destination.id && previous.destination.point?.lat === destination.point?.lat &&
    previous.destination.point?.lng === destination.point?.lng);
  if (matching) Object.assign(routes,matching.routes);
  for (const round of rounds) {
    const siteId = tip ? round.deliverySiteId : round.pickupSiteId;
    if (!siteId || !round.outbound.miles.trim()) continue;
    const returnLeg = round.mirror ? round.outbound : round.inbound;
    routes[siteId] = tip ? {outbound:returnLeg,inbound:round.outbound,start:round.start} : {outbound:round.outbound,inbound:returnLeg,start:round.start};
  }
  const settings: QuarryOfferSettings = {
    destination,kind,pricing:{mode:pricing.mode,markup:pricing.markup,overrides:{}},routes,
    withoutReturn:job.withoutReturn ?? [],returnLoad:job.returnLoad,
  };
  return {section:{kind,address,lines},plan,settings};
}

export async function downloadQuarryOffer(date: string, jobs: QuarryOfferJob[], draft: TonPriceDraft, details: OfferDetails, sourceId?: string) {
  if (!validOfferDetails(details) || !Array.isArray(jobs) || !jobs.length || jobs.length > maxQuarryOfferJobs ||
    jobs.some(job => !job || !Array.isArray(job.materials)) ||
    jobs.reduce((sum,job) => sum+job.materials.length,0) > 100) {
    return {error:'Kontrollera offertuppgifterna. Högst 100 materialrader kan ingå.'};
  }
  const access = await tonPriceAccess();
  if (!access) return {error:'Behörighet saknas.'};
  const {source,error} = await revisionSource(access,sourceId);
  if (error) return {error};
  const previous = source?.calculation_snapshot;
  const previousJobs = previous?.mode === 'quick' ? [previous.quick,...(previous.additionalJobs ?? [])] : [];
  const [bank,workifyPrices] = await Promise.all([
    readPriceBank(access),previous?.mode === 'quick' ? previous.workifyPrices : readWorkifyMaterialPrices(access),
  ]);
  if (!bank) return {error:'Prisbanken kunde inte hämtas.'};
  const sections: OfferSection[] = [];
  const plan: DeliveryPlanLine[] = [];
  const settings = [...previousJobs];
  for (const [index,job] of jobs.entries()) {
    const result = prepareQuarryJob(bank,date,job,draft,workifyPrices,previousJobs);
    if (!result.section) return {error:`Uppdrag ${index+1}. ${result.error}`};
    if (sections.some(section => sameOfferJob(section,result.section))) {
      return {error:'Samla material för samma uppdragstyp och adress på ett uppdrag.'};
    }
    sections.push(result.section);
    plan.push(...result.plan);
    const matching = settings.findIndex(saved => sameOfferJob({kind:saved.kind,address:saved.destination.address},result.section));
    if (matching === -1) settings.push(result.settings);
    else settings[matching] = result.settings;
  }
  const [quick,...additionalJobs] = settings;
  return offerDocuments(access,date,details,sections,plan,{
    mode:'quick',quick,additionalJobs,workifyPrices:workifyPrices ?? [],
    draft:{...draft,...details,priceDate:date,materials:[],rounds:[]},
  },source);
}

export async function downloadAdvancedOffer(draft: TonPriceDraft, expectedPrices: number[], sourceId?: string) {
  if (!validOfferDetails(draft)) return {error:'Kontrollera offertuppgifterna.'};
  const access = await tonPriceAccess();
  if (!access) return {error:'Behörighet saknas.'};
  const revision = await revisionSource(access,sourceId);
  if (revision.error) return {error:revision.error};
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
  const groups = new Map<string,OfferSection>();
  for (const [index,line] of lines.entries()) {
    const input = draft.materials[index];
    const round = rounds.get(input.roundId)!;
    const kind = line.isTip ? 'tip' : 'purchase';
    const address = (line.isTip ? round.pickup : round.delivery).trim();
    const key = JSON.stringify([kind,address]);
    const section = groups.get(key) ?? {kind,address,lines:[]};
    section.lines.push(line);
    groups.set(key,section);
  }
  const priceDate = draft.priceDate || stockholmDate();
  return offerDocuments(access,priceDate,draft,[...groups.values()],plan,
    {mode:'advanced',draft:{...draft,priceDate}},revision.source);
}
