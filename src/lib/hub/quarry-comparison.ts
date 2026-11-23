import {comparisonMaterial, effectiveSiteRates, type MaterialPriceBank} from './material-price-bank';
import {calculateTonPrices, newMaterial, type Round, type TonPriceDraft} from './ton-price';

export function compareQuarries(bank: MaterialPriceBank, date: string, materials: {name: string; tonnes: string}[], rounds: Round[], draft: TonPriceDraft) {
  const sites = new Map(bank.sites.filter(site => site.kind !== 'tip').map(site => [site.id,site]));
  const active = effectiveSiteRates(bank.rates,date).filter(rate => rate.kind === 'purchase' && rate.unit === 'ton' && sites.has(rate.siteId));
  const roundsBySite = new Map(rounds.map(round => [round.pickupSiteId,round]));
  return materials.map(({name:material,tonnes}) => {
    const candidates = active.filter(rate => comparisonMaterial(rate) === material);
    const options = candidates.flatMap(rate => {
      const site = sites.get(rate.siteId)!;
      const round = roundsBySite.get(site.id);
      if (!round) return [];
      const row = {...newMaterial(rate.id, round.id, 'trailer'), name:rate.material,purchase:String(rate.price),markup:'0',tonnes};
      const result = calculateTonPrices({...draft, rounds:[round], materials:[row]}).materials[0];
      if (!result.selected || result.status) return [];
      const freight = result.tonnes && result.selected.trips
        ? result.selected.freight * result.selected.load * result.selected.trips / result.tonnes
        : result.selected.freight;
      return [{site, rate, round, tonnes, freight, total:rate.price + freight}];
    }).sort((a,b) => a.total-b.total || a.site.name.localeCompare(b.site.name,'sv'));
    const missing = [...new Set(candidates.filter(rate => !options.some(option => option.site.id === rate.siteId))
      .map(rate => sites.get(rate.siteId)!.name))];
    return {material, options, missing};
  });
}

export type QuarryComparison = ReturnType<typeof compareQuarries>;
