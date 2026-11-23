import type {QuarryComparison} from './quarry-comparison';
import type {calculateTonPrices, TonPriceDraft} from './ton-price';

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
  unitPrice: number;
  pickupKey: string;
  truckSupplement: number | null;
  quotedVehicle?: string;
};

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

export function offerLines(comparison: QuarryComparison, markup: number): OfferLine[] {
  return comparison.flatMap(row => {
    const winner = row.options[0];
    if (!winner) return [];
    const unitPrice = roundOfferMoney(winner.total + winner.rate.price * markup / 100);
    return [{material:row.material, unitPrice, pickupKey:`site:${winner.site.id}`, truckSupplement:winner.truckSupplement}];
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
      material:input.transportOnly ? input.name.trim() || 'Enbart transport' : input.name,
      unitPrice:roundOfferMoney(row.selected.delivered),
      pickupKey,
      quotedVehicle:input.vehicleId === 'trailer' ? undefined : draft.vehicles.find(vehicle => vehicle.id === input.vehicleId)?.name,
      truckSupplement:truck && trailer ? roundOfferMoney(truck.freight - trailer.freight) : null,
    }];
  });
}
