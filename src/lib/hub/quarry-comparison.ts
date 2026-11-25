import {comparisonMaterial, effectiveSiteRates, type MaterialPriceBank} from './material-price-bank';
import {roundOfferMoney} from './ton-price-offer';
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
      const calculation = calculateTonPrices({...draft, rounds:[round], materials:[row]});
      const result = calculation.materials[0];
      const time = calculation.rounds[0].result;
      if (!result.selected || result.status || !time) return [];
      const quotedFreight = (option: NonNullable<typeof result.selected>) => result.tonnes && option.trips
        ? option.freight * option.load * option.trips / result.tonnes
        : option.freight;
      const freight = quotedFreight(result.selected);
      const truck = result.options.find(option => option.id === 'truck')?.prices[draft.profile];
      const truckSupplement = truck ? roundOfferMoney(quotedFreight(truck) - freight) : null;
      return [{site, rate, round, time, tonnes, freight, truckSupplement, total:rate.price + freight}];
    }).sort((a,b) => a.total-b.total || a.site.name.localeCompare(b.site.name,'sv'));
    const availableSites = new Set<string>();
    const bestPerSite = options.filter(option => {
      if (availableSites.has(option.site.id)) return false;
      availableSites.add(option.site.id);
      return true;
    });
    const missing = [...new Set(candidates.filter(rate => !availableSites.has(rate.siteId))
      .map(rate => sites.get(rate.siteId)!.name))];
    return {material, options:bestPerSite, missing};
  });
}

export type QuarryComparison = ReturnType<typeof compareQuarries>;
