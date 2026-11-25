export type YardAddressClue = {
  source: 'Flintab' | 'Next' | 'Workify' | 'AAK';
  reference: string | null;
  name: string | null;
  address: string | null;
  reason: string;
};
export type AddressSide = 'origin' | 'destination';
export type YardAddressQuery = {
  query: string;
  street: string | undefined;
  number: string | undefined;
  postcode: string | undefined;
  locality: string | undefined;
  side: AddressSide | undefined;
  clue: YardAddressClue;
};

const streetPattern = /(?<![\p{L}\p{N}])(?:(?:södra|norra|östra|västra|gamla|nya|stora|lilla)\s+)?[\p{L}][\p{L}'’-]*(?:vägen|gatan|gränden|stigen|leden|allén|torget|backen|väg|gata|v\.|v)(?!\p{L})/giu;
const localityPattern = /(?<!\p{L})(?:as[aä]rum|björkenäs|bromölla|bräkne-hoby|hällevik|jämshög|kallinge|karlshamn|karlskrona|kristianstad|mjällby|mör[r]?um|norje|näsum|olofström|pukavik|ronneby|sölve|sölvesborg|trensum|sturk[öo]|växjö)(?!\p{L})/iu;

export function yardAddressKey(value: string) {
  return value.toLocaleLowerCase('sv-SE').replace(/[^\p{L}\p{N}]/gu,'');
}

export function yardAddressQueries(clues: YardAddressClue[]) {
  const queries = new Map<string,YardAddressQuery>();
  function add(query: Omit<YardAddressQuery,'clue'>, clue: YardAddressClue) {
    const key = yardAddressKey(query.query) + ':' + (query.side ?? '');
    if (!queries.has(key)) queries.set(key,{...query,clue});
  }
  const rowLocality = clues.filter(clue => clue.source==='Flintab').map(clue => clue.name?.match(localityPattern)?.[0]).find(Boolean);
  for (const clue of clues) {
    for (const [raw,structured] of [[clue.address,true],[clue.name,false]] as const) {
      for (const fragment of raw?.split(/[\n\r;|→]+/) ?? []) {
        if (fragment.length>240 || /https?:\/\//i.test(fragment)) continue;
        const side: AddressSide | undefined = /^(?:från|hämtning|lastning)\s*:/i.test(fragment.trim()) ? 'origin'
          : /^(?:till|leverans|lämning|lossning)\s*:/i.test(fragment.trim()) ? 'destination' : undefined;
        const postalArea = structured ? fragment.match(/(?<!\d)(\d{3} ?\d{2})\s+([\p{L}][\p{L} -]{1,45})(?=\s*(?:,|$))/u) : null;
        const locality = postalArea?.[2].trim() ?? fragment.match(localityPattern)?.[0] ?? (clue.source==='Flintab' ? rowLocality : undefined);
        const postcode = postalArea?.[1];
        const streets = [...fragment.matchAll(streetPattern)];
        for (const match of streets) {
          const original = match[0];
          const abbreviated = /v\.$/i.test(original) || (original.length>=6 && /V$/.test(original) && original===original.toLocaleUpperCase('sv-SE'));
          if (!abbreviated && /v$/i.test(original) && !/väg$/i.test(original)) continue;
          const normalized = abbreviated ? original.replace(/v\.?$/i,'vägen') : original;
          const street = original===original.toLocaleUpperCase('sv-SE')
            ? normalized.toLocaleLowerCase('sv-SE').replace(/(^|\s)\p{L}/gu,letter=>letter.toLocaleUpperCase('sv-SE'))
            : normalized;
          const number = fragment.slice(match.index + original.length).match(/^\s+(\d{1,4}(?:\s?[a-z](?!\p{L}))?)(?![\p{L}\d]|\s?\d{2}\s+[\p{L}])/iu)?.[1];
          add({query:[[street,number].filter(Boolean).join(' '),[postcode,locality].filter(Boolean).join(' ')].filter(Boolean).join(', '),street,number,postcode,locality,side},clue);
        }
        if (structured && !streets.length && (postalArea || /^[23456789CFGHJMPQRVWX]{4}\+[23456789CFGHJMPQRVWX]{2,3}\s+\p{L}/iu.test(fragment.trim()))) {
          add({query:fragment.trim(),street:undefined,number:undefined,postcode,locality,side},clue);
        }
      }
    }
  }
  const all = [...queries.values()];
  return [...all.filter(item => item.clue.source!=='Flintab').slice(0,5),...all.filter(item => item.clue.source==='Flintab').slice(0,3)].slice(0,8);
}
