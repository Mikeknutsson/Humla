export type MaterialSite = {
  id: string; name: string; kind: 'quarry' | 'tip' | 'both'; address: string;
  locationNote: string; addressSource: string; mapPlaceId: string;
};
export type SiteRate = {
  id: string; siteId: string; kind: 'purchase' | 'tip'; material: string; unit: string;
  price: number; validFrom: string | null; validTo: string | null; source: string; imported: boolean;
};
export type MaterialPriceBank = {sites: MaterialSite[]; rates: SiteRate[]};

export function effectiveSiteRates(rates: SiteRate[], date: string) {
  const active = rates.filter(rate => (!rate.validFrom || rate.validFrom <= date) && (!rate.validTo || rate.validTo >= date));
  const latestList = new Map<string, string>();
  for (const rate of active) {
    if (rate.imported && (rate.validFrom ?? '') > (latestList.get(rate.siteId) ?? '')) {
      latestList.set(rate.siteId, rate.validFrom ?? '');
    }
  }
  const entries = new Map<string, SiteRate>();
  for (const rate of active) {
    if (rate.imported && (rate.validFrom ?? '') !== (latestList.get(rate.siteId) ?? '')) continue;
    const key = JSON.stringify([rate.siteId, rate.kind, rate.material.toLocaleLowerCase('sv-SE'), rate.unit]);
    const previous = entries.get(key);
    if (!previous || (rate.validFrom ?? '') > (previous.validFrom ?? '') ||
      (rate.validFrom === previous.validFrom && previous.imported && !rate.imported)) entries.set(key, rate);
  }
  return [...entries.values()];
}

export function stockholmDate() {
  return new Intl.DateTimeFormat('sv-SE', {timeZone: 'Europe/Stockholm', year: 'numeric', month: '2-digit', day: '2-digit'}).format(new Date());
}

export const materialGroups = [
  'Bärlager', 'Förstärkningslager', 'Slitlager', 'Bergkross och krossgrus', 'Makadam',
  'Stenmjöl', 'Sand och naturgrus', 'Fyllnad', 'Jord', 'Natursten', 'Tippavgifter', 'Övrigt',
] as const;

type MaterialGroup = typeof materialGroups[number];

// Bare fractions in the existing purchase lists use the same grades as the named rows.
const fractionNames = new Map<string,string>([
  ...['32','45','63'].map(size => ['0-'+size,'Bärlager 0-'+size] as const),
  ...['2','4','5','8'].map(size => ['0-'+size,'Stenmjöl 0-'+size] as const),
  ...['2-5','4-8','5-8','8-11','8-16','11-16','16-22','16-32','32-64','40-90','100-200']
    .map(fraction => [fraction,'Makadam '+fraction] as const),
  ['0-16','Bergkross 0-16'], ['0-90','Förstärkningslager 0-90'],
]);

const families: [prefix: RegExp, label: string, group: MaterialGroup][] = [
  [/^bärlager\b/i, 'Bärlager', 'Bärlager'],
  [/^förstärkning(?:slager)?\b/i, 'Förstärkningslager', 'Förstärkningslager'],
  [/^slitlager\b/i, 'Slitlager', 'Slitlager'],
  [/^bergkross\b/i, 'Bergkross', 'Bergkross och krossgrus'],
  [/^krossgrus\b/i, 'Krossgrus', 'Bergkross och krossgrus'],
  [/^makadam\b/i, 'Makadam', 'Makadam'],
  [/^stenmjöl\b/i, 'Stenmjöl', 'Stenmjöl'],
  [/^natur\s*singel\b/i, 'Natursingel', 'Sand och naturgrus'],
  [/^bakbar sandlådesand\b/i, 'Bakbar sandlådesand', 'Sand och naturgrus'],
  [/^dränering\b/i, 'Dränering', 'Sand och naturgrus'],
  [/^gjutgrus\b/i, 'Gjutgrus', 'Sand och naturgrus'],
  [/^murgrus\b/i, 'Murgrus', 'Sand och naturgrus'],
  [/^rörgrus\s*\/\s*kabelsand\b/i, 'Rörgrus/kabelsand', 'Sand och naturgrus'],
  [/^tvättad\b/i, 'Tvättad', 'Sand och naturgrus'],
  [/^grov\s*fyllnad\b/i, 'Grovfyllnad', 'Fyllnad'],
  [/^fyllnadsmaterial\b/i, 'Fyllnadsmaterial', 'Fyllnad'],
  [/^moränfyllnad\b/i, 'Moränfyllnad', 'Fyllnad'],
  [/^matjord\b/i, 'Matjord', 'Jord'],
  [/^kullersten\b/i, 'Kullersten', 'Natursten'],
  [/^stengärdsten\b/i, 'Stengärdsten', 'Natursten'],
];

export function standardMaterial(rate: Pick<SiteRate,'material'|'kind'>): {name: string; group: MaterialGroup} {
  const normalized = rate.material.normalize('NFC').trim()
    .replace(/(\d)\s*[/–—−-]\s*(\d)/g,'$1-$2')
    .replace(/\s+SS[- ]EN\s+\d+(?=\s|$)/gi,'')
    .replace(/\s+/g,' ');
  if (rate.kind === 'tip') {
    return {name:/^schakt(?: \(pukavik\))?$/i.test(normalized) ? 'Schakt' : normalized,group:'Tippavgifter'};
  }

  if (/^(?:(?:förstärkning(?:slager)?|bergkross) )?(?:0-(?:125|150)|0-125-150|0-125 eller 0-150|0-150 eller 0-125)$/i.test(normalized)) {
    return {name:'0-125/150',group:'Förstärkningslager'};
  }

  let name = fractionNames.get(normalized) ?? normalized;
  if (/^bergkross 0-(32|45|63)$/i.test(name)) name = name.replace(/^bergkross/i,'Bärlager');
  if (/^bergkross 0-(90|200)$/i.test(name)) name = name.replace(/^bergkross/i,'Förstärkningslager');
  name = name
    .replace(/^makadam tvättad (\d+-\d+)$/i,'Makadam $1 tvättad')
    .replace(/^tvättad \((dresss?and|fallsand)\) (.+)$/i,(_, sand: string, size: string) =>
      (sand.toLowerCase() === 'fallsand' ? 'Fallsand' : 'Dressand') + ' ' + size + ' tvättad')
    .replace(/\b(Tvättad|Torr|Klass|Diabas|Terminal|Svart|Special)\b/gi,word => word.toLocaleLowerCase('sv-SE'));
  if (/^(dressand|fallsand)\b/i.test(name)) return {name,group:'Sand och naturgrus'};
  const family = families.find(([pattern]) => pattern.test(name));
  return family ? {name:name.replace(family[0],family[1]),group:family[2]} : {name,group:'Övrigt'};
}

export function comparisonMaterial(rate: SiteRate) {
  return standardMaterial(rate).name;
}
