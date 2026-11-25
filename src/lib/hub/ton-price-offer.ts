import type {QuarryComparison} from './quarry-comparison';
import type {calculateTonPrices, TonPriceDraft} from './ton-price';
import {standardMaterial} from './material-price-bank';

export type OfferDetails = {customer: string; project: string; validity: string; terms: string};
export const offerMoney = new Intl.NumberFormat('sv-SE', {maximumFractionDigits:0,signDisplay:'negative'});

export function parseOfferMarkup(value: string) {
  if (!/^\d{1,4}(?:[,.]\d{1,2})?$/.test(value.trim())) return null;
  const percent = Number(value.trim().replace(',', '.'));
  return percent <= 1000 ? percent : null;
}

export function roundOfferMoney(value: number) {
  const rounded = Math.round(Math.abs(value));
  return value < 0 && rounded !== 0 ? -rounded : rounded;
}

export type OfferLine = {
  material: string;
  isTip?: boolean;
  unitPrice: number;
  pickupKey: string;
  truckSupplement: number | null;
  quotedVehicle?: string;
};

export type OfferSection = {address: string; kind: 'purchase' | 'tip'; lines: OfferLine[]};

export function truckSupplementArticles(lines: OfferLine[]) {
  const groups = new Map<string, {price: number | null; materials: Set<string>}>();
  for (const line of lines) {
    const key = JSON.stringify([line.pickupKey,line.truckSupplement]);
    let group = groups.get(key);
    if (!group) {
      group = {price:line.truckSupplement,materials:new Set()};
      groups.set(key,group);
    }
    group.materials.add(line.material);
  }
  return [...groups].map(([key,group]) => ({
    key,
    price:group.price,
    label:groups.size > 1 ? [...group.materials].join(', ') : '',
  }));
}

export type WorkifyOfferPrice = {article: string; label: string; material: string; price: number; includesFreight: boolean};
export type QuarryPricing = {
  mode: 'markup' | 'workify';
  markup: string;
  overrides: Record<string,{source: string; markup: string}>;
};

export function priceQuarryOffer(comparison: QuarryComparison, pricing: QuarryPricing, workifyPrices: WorkifyOfferPrice[]) {
  return comparison.map(row => {
    const winner = row.options[0];
    if (!winner) return {error:row.problem};
    const override = Object.hasOwn(pricing.overrides,row.material) ? pricing.overrides[row.material] : undefined;
    const source = override?.source || '';
    const useWorkify = source.startsWith('workify:') || (!source && pricing.mode === 'workify');
    let materialPrice: number;
    let deliveredPrice: number;
    let pricingSource: string;
    if (winner.rate.kind === 'tip' || (winner.preferred && useWorkify)) {
      materialPrice = winner.rate.price;
      deliveredPrice = winner.total;
      pricingSource = winner.preferred ? 'Sortergårdens prislista' : 'Prisbanken';
    } else if (useWorkify) {
      const matches = workifyPrices.filter(price => price.material === row.material);
      const price = source ? matches.find(price => source === 'workify:' + price.article) :
        matches.find(price => !price.includesFreight) ?? matches[0];
      if (!price) return {error:'Workify-pris saknas för fraktionen'};
      materialPrice = price.price - (price.includesFreight ? winner.freight : 0);
      deliveredPrice = price.price + (price.includesFreight ? 0 : winner.freight);
      pricingSource = `Workify STD · ${price.article} · ${price.includesFreight ? 'inkl. transport' : 'materialpris'}`;
    } else {
      const markup = parseOfferMarkup(source === 'markup' && override?.markup.trim() ? override.markup : pricing.markup);
      if (markup === null) return {error:'Ange ett påslag mellan 0 och 1 000 %'};
      materialPrice = winner.rate.price * (1 + markup / 100);
      deliveredPrice = materialPrice + winner.freight;
      pricingSource = (winner.preferred ? 'Sortergårdens prislista · ' : '') + `Materialpåslag ${markup.toLocaleString('sv-SE')} %`;
    }
    const unitPrice = roundOfferMoney(deliveredPrice);
    const line: OfferLine = {material:row.material,isTip:winner.rate.kind === 'tip' || undefined,unitPrice,
      pickupKey:`site:${winner.site.id}`,truckSupplement:winner.truckSupplement};
    return {line,materialPrice,pricingSource};
  });
}

export function advancedOfferLines(draft: TonPriceDraft, result: ReturnType<typeof calculateTonPrices>): OfferLine[] {
  const rounds = new Map(draft.rounds.map(round => [round.id,round]));
  return result.materials.flatMap((row,index) => {
    if (row.status || !row.selected) return [];
    const input = draft.materials[index];
    const round = rounds.get(input.roundId);
    const pickup = round?.pickup.trim().replace(/\s+/g,' ').toLocaleLowerCase('sv-SE');
    const pickupKey = round?.pickupSiteId ? `site:${round.pickupSiteId}` : round?.pickupPlaceId ? `place:${round.pickupPlaceId}`
      : pickup ? `address:${pickup}` : `round:${input.roundId}`;
    const truck = row.options.find(option => option.id === 'truck')?.prices[draft.profile];
    const trailer = row.options.find(option => option.id === 'trailer')?.prices[draft.profile];
    return [{
      material:input.transportOnly ? input.name.trim() || 'Enbart transport' :
        input.bankRateId ? standardMaterial({material:input.name,kind:input.bankKind ?? 'purchase'}).name : input.name,
      isTip:input.bankKind === 'tip' || undefined,
      unitPrice:roundOfferMoney(row.selected.delivered),
      pickupKey,
      quotedVehicle:input.vehicleId === 'trailer' ? undefined : draft.vehicles.find(vehicle => vehicle.id === input.vehicleId)?.name,
      truckSupplement:truck && trailer ? roundOfferMoney(truck.freight - trailer.freight) : null,
    }];
  });
}
