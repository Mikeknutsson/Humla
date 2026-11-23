'use server';

import {tonPriceAccess} from './access';
import {readPriceBank} from '@/lib/hub/material-price-bank-server';
import {effectiveSiteRates, stockholmDate} from '@/lib/hub/material-price-bank';
import {compareQuarries} from '@/lib/hub/quarry-comparison';
import {calculateTonPrices, type Round, type TonPriceDraft} from '@/lib/hub/ton-price';

export async function recalculateTonPrices(draft: TonPriceDraft) {
  const access = await tonPriceAccess();
  if (!access) return {error: 'Behörighet saknas.'};
  if (!draft || !Array.isArray(draft.rounds) || !Array.isArray(draft.materials) ||
    !Array.isArray(draft.vehicles) || draft.rounds.length > 30 || draft.materials.length > 100 ||
    draft.vehicles.length !== 3 || !['reference', 'bk1', 'bk4'].includes(draft.profile)) {
    return {error: 'Kalkylen kunde inte läsas.'};
  }
  try {
    if (draft.materials.some(row => row.bankRateId)) {
      const bank = await readPriceBank(access);
      if (!bank) return {error: 'Prisbanken kunde inte hämtas.'};
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
    return {result: calculateTonPrices(draft)};
  } catch {
    return {error: 'Kalkylen innehåller ogiltiga värden.'};
  }
}

export async function calculateQuarryComparison(date: string, materials: {name: string; tonnes: string}[], rounds: Round[], draft: TonPriceDraft) {
  const access = await tonPriceAccess();
  if (!access) return {error:'Behörighet saknas.'};
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || materials.length > 100 || rounds.length > 100 ||
    !['reference','bk1','bk4'].includes(draft.profile) || draft.vehicles.length !== 3) return {error:'Ogiltigt jämförelseunderlag.'};
  const bank = await readPriceBank(access);
  if (!bank) return {error:'Prisbanken kunde inte hämtas.'};
  try {return {comparison:compareQuarries(bank,date,materials,rounds,draft)};}
  catch {return {error:'Kontrollera mil, ekipage och returparametrar.'};}
}
