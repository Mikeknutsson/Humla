import municipalities from '../swedish-municipalities.json';

export const receiverOptions = [
  {name:'Ragn-Sells Recycling Ab', address:'Heljestorp 150, 462 93 Vänersborg', organisation:'556057-3452', municipality:'1487'},
  {name:'Njudung Energi Vetlanda AB', address:'Flishult Avfallsanläggning 1, 574 94 Vetlanda', organisation:'556107-7248', municipality:'0685'},
  {name:'Halmstads Energi och Miljö', address:'Kornhillsvägen 60, 302 44 Halmstad', organisation:'556528-3248', municipality:'1380'},
  {name:'Affärsverken Karlskrona Aktiebolag', address:'Tippvägen, 373 43 Rödeby', organisation:'556049-4733', municipality:'1080'},
  {name:'Stena Recycling AB', address:'Östersjövägen 24-15, 374 31 Karlshamn', organisation:'556132-1752', municipality:'1082'},
  {name:'Moskogen Miljö AB', address:'Moskogen 101, 395 91 Kalmar', organisation:'559176-0029', municipality:'0880'},
  {name:'Hässleholm Miljö AB', address:'Avfallsanläggningen 281 95 Vankiva', organisation:'556555-0349', municipality:'1293'},
];

export type Party = {name: string; address: string; organisation: string};
export type Location = {value: string; municipality: string};
export type Waste = {code: string; name: string; estimatedKg: string; weighedKg: string; packages: string; packaging: string};

export type DocumentFields = {
  date: string;
  workifyOrderNumber: string;
  registration: string;
  carrier: Party;
  consignor: Party | null;
  receiver: Party;
  origin: Location;
  destination: Location;
  deliveryNumber: string;
  adrReference: string;
  waste: Waste[];
  carrierSigner: string;
  consignorSigner: string;
};

export type HubChoice = {id: string; label: string; value: string};

export const elleholms: Party = {
  name:'Elleholms Maskin AB',
  address:'Karlshamnsvägen 329, 294 93 Sölvesborg',
  organisation:'556863-2383',
};
export const emptyParty: Party = {name:'', address:'', organisation:''};
export const emptyLocation: Location = {value:'', municipality:''};
export const emptyWaste: Waste = {code:'',name:'',estimatedKg:'',weighedKg:'',packages:'',packaging:''};

// Codes and names from SCB, Län och kommuner i kodnummerordning 2026.
export const municipalityOptions = Object.entries(municipalities)
  .sort(([,a],[,b]) => a.localeCompare(b,'sv'));

function municipalityName(name: string) {
  return name.trim().toLocaleLowerCase('sv')
    .replace(/(?: kommun| municipality| stad)$/, '')
    .replace(/[\s-]+/g,'');
}

export function municipalityFor(components: {long_name: string; types: string[]}[]) {
  if (!components.some(component => component.types.includes('country') &&
    ['sverige','sweden'].includes(component.long_name.toLowerCase()))) return '';
  for (const component of components) {
    if (!component.types.includes('administrative_area_level_2') &&
        !component.types.includes('administrative_area_level_3')) continue;
    const key = municipalityName(component.long_name);
    const code = municipalityOptions.find(([,name]) => municipalityName(name) === key)?.[0] ??
      municipalityOptions.find(([,name]) => municipalityName(name) === key.replace(/s$/,''))?.[0];
    if (code) return code;
  }
  return '';
}

export const isMunicipality = (code: string) => Object.hasOwn(municipalities,code);
