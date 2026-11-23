import type {QuarryComparison} from './quarry-comparison';

export type OfferDetails = {customer: string; project: string; validity: string; terms: string};
export const offerMoney = new Intl.NumberFormat('sv-SE', {minimumFractionDigits:2, maximumFractionDigits:2});
export const offerQuantity = new Intl.NumberFormat('sv-SE', {maximumFractionDigits:6});

export function parseOfferMarkup(value: string) {
  if (!/^\d{1,4}(?:[,.]\d{1,2})?$/.test(value.trim())) return null;
  const percent = Number(value.trim().replace(',', '.'));
  return percent <= 1000 ? percent : null;
}

const roundMoney = (value: number) => Math.round((value + Math.abs(value) * Number.EPSILON) * 100) / 100;

export function offerLines(comparison: QuarryComparison, markup: number) {
  return comparison.flatMap(row => {
    const winner = row.options[0];
    if (!winner) return [];
    const tonnes = Number(winner.tonnes.trim().replace(',', '.')) || null;
    const unitPrice = roundMoney(winner.total + winner.rate.price * markup / 100);
    return [{material:row.material, tonnes, unitPrice,
      amount:tonnes === null ? null : roundMoney(unitPrice * tonnes)}];
  });
}

export function offerTotal(lines: ReturnType<typeof offerLines>) {
  return lines.length > 0 && lines.every(line => line.amount !== null)
    ? roundMoney(lines.reduce((sum, line) => sum + (line.amount ?? 0), 0)) : null;
}
