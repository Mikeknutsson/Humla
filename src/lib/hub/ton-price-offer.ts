import type {QuarryComparison} from './quarry-comparison';
import type {calculateTonPrices, TonPriceDraft} from './ton-price';

export type OfferDetails = {customer: string; project: string; validity: string; terms: string};
export const offerMoney = new Intl.NumberFormat('sv-SE', {minimumFractionDigits:2, maximumFractionDigits:2});

export function parseOfferMarkup(value: string) {
  if (!/^\d{1,4}(?:[,.]\d{1,2})?$/.test(value.trim())) return null;
  const percent = Number(value.trim().replace(',', '.'));
  return percent <= 1000 ? percent : null;
}

export const roundOfferMoney = (value: number) => Math.round((value + Math.abs(value) * Number.EPSILON) * 100) / 100;

export type OfferLine = {material: string; unitPrice: number; truckSupplement: number | null; quotedVehicle?: string};

export function offerLines(comparison: QuarryComparison, markup: number): OfferLine[] {
  return comparison.flatMap(row => {
    const winner = row.options[0];
    if (!winner) return [];
    const unitPrice = roundOfferMoney(winner.total + winner.rate.price * markup / 100);
    return [{material:row.material, unitPrice, truckSupplement:winner.truckSupplement}];
  });
}

export function advancedOfferLines(draft: TonPriceDraft, result: ReturnType<typeof calculateTonPrices>): OfferLine[] {
  return result.materials.flatMap((row,index) => {
    if (row.status || !row.selected) return [];
    const input = draft.materials[index];
    const truck = row.options.find(option => option.id === 'truck')?.prices[draft.profile];
    const trailer = row.options.find(option => option.id === 'trailer')?.prices[draft.profile];
    return [{
      material:input.transportOnly ? input.name.trim() || 'Enbart transport' : input.name,
      unitPrice:roundOfferMoney(row.selected.delivered),
      quotedVehicle:input.vehicleId === 'trailer' ? undefined : draft.vehicles.find(vehicle => vehicle.id === input.vehicleId)?.name,
      truckSupplement:truck && trailer ? roundOfferMoney(truck.freight - trailer.freight) : null,
    }];
  });
}
