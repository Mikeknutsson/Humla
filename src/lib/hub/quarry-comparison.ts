import {comparisonMaterial, effectiveSiteRates, sortergardenSiteIds, type MaterialPriceBank, type SiteRate} from './material-price-bank';
import {roundOfferMoney} from './ton-price-offer';
import {calculateRound, calculateTonPrices, newMaterial, type Round, type TonPriceDraft} from './ton-price';

export function compareQuarries(bank: MaterialPriceBank, date: string, materials: {name: string; tonnes: string}[],
  rounds: Round[], draft: TonPriceDraft, kind: SiteRate['kind'] = 'purchase') {
  const sites = new Map(bank.sites.filter(site => site.kind !== (kind === 'tip' ? 'quarry' : 'tip')).map(site => [site.id,site]));
  const sortergardenIds = sortergardenSiteIds(bank.sites,bank.rates);
  const active = effectiveSiteRates(bank.rates,date).filter(rate => rate.kind === kind && rate.unit === 'ton' && sites.has(rate.siteId));
  const roundsBySite = new Map(rounds.map(round => [kind === 'tip' ? round.deliverySiteId : round.pickupSiteId,round]));
  return materials.map(({name:material,tonnes}) => {
    const candidates = active.filter(rate => comparisonMaterial(rate) === material);
    const failures = new Map<string,string>();
    const options = candidates.flatMap(rate => {
      const site = sites.get(rate.siteId)!;
      const round = roundsBySite.get(site.id);
      if (!round) {failures.set(site.id,'Körsträcka saknas');return [];}
      const row = {...newMaterial(rate.id, round.id, 'trailer'), name:rate.material,purchase:String(rate.price),bankKind:kind,markup:'0',tonnes};
      const calculation = calculateTonPrices({...draft, rounds:[round], materials:[row]});
      const result = calculation.materials[0];
      const time = calculation.rounds[0].result;
      if (!result.selected || result.status || !time) {
        const reason = !time && round.returnLoad && calculateRound({...round,returnLoad:undefined})
          ? 'Kontrollera returlastens ton, nettointäkt och extra körning'
          : !time ? 'Kontrollera körsträcka och körtid'
          : !result.selected ? 'Kontrollera timpris, lastvikt och valt viktunderlag för bil + kärra'
          : result.status ?? 'Kontrollera kalkylunderlaget';
        failures.set(site.id,reason);
        return [];
      }
      const quotedFreight = (option: NonNullable<typeof result.selected>) => result.tonnes && option.trips
        ? option.freight * option.load * option.trips / result.tonnes
        : option.freight;
      const freight = quotedFreight(result.selected);
      const truck = result.options.find(option => option.id === 'truck')?.prices[draft.profile];
      const truckSupplement = truck ? roundOfferMoney(quotedFreight(truck) - freight) : null;
      return [{site, rate, round, time, tonnes, freight, truckSupplement, preferred:sortergardenIds.has(site.id), total:rate.price + freight}];
    }).sort((a,b) => Number(b.preferred)-Number(a.preferred) || a.total-b.total || a.site.name.localeCompare(b.site.name,'sv'));
    const availableSites = new Set<string>();
    const bestPerSite = options.filter(option => {
      if (availableSites.has(option.site.id)) return false;
      availableSites.add(option.site.id);
      return true;
    });
    const missing = [...new Set(candidates.filter(rate => !availableSites.has(rate.siteId))
      .map(rate => sites.get(rate.siteId)!.name))];
    const reasons = [...new Set([...failures].filter(([id]) => !availableSites.has(id)).map(([,reason]) => reason))];
    const problem = !candidates.length ? 'Aktivt tonpris saknas i Prisbanken' :
      reasons.length === 1 ? reasons[0] : 'Kontrollera körsträcka, ekipage och returlast';
    return {material, options:bestPerSite, missing, problem};
  });
}

export type QuarryComparison = ReturnType<typeof compareQuarries>;
