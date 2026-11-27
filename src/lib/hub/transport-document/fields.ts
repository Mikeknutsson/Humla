import municipalities from '../swedish-municipalities.json';

export const receiverOptions = [
  {name:'Ragn-Sells Recycling Ab', address:'Heljestorp 150, 462 93 Vänersborg', organisation:'556057-3452', municipality:'1487'},
  {name:'Njudung Energi Vetlanda AB', address:'Flishult Avfallsanläggning 1, 574 94 Vetlanda', organisation:'556107-7248', municipality:'0685'},
  {name:'Halmstads Energi ocn Miljö', address:'Kornhillsvägen 60, 302 44 Halmstad', organisation:'556528-3248', municipality:'1380'},
  {name:'Affärsverken Karlskrona Aktiebolag', address:'Tippvägen, 373 43 Rödeby', organisation:'556049-4733', municipality:'1080'},
  {name:'Stena Recycling AB', address:'Östersjövägen 24-15, 374 31 Karlshamn', organisation:'556132-1752', municipality:'1082'},
  {name:'Moskogen Miljö AB', address:'Moskogen 101, 395 91 Kalmar', organisation:'559176-0029', municipality:'0880'},
  {name:'Hässleholm Miljö AB', address:'Avfallsanläggningen 281 95 Vankiva', organisation:'556555-0349', municipality:'1293'},
];

export const wasteOptions = [
  ['Asbest','170605*'],
  ['Tryckimpregnerat','170204*'],
  ['PCB','170902*'],
  ['Bitumenblandningar som innehåller PAH','170301*'],
  ['Hydrauloljor som innehåller PCB','130101*'],
  ['Eldningsolja och diesel.','130701*'],
  ['Bensin.','130702*'],
  ['Absorbermedel, torkdukar och skyddskläder förorenade av olja','150202*'],
  ['Lysrör och annat kvicksilverhaltigt avfall.','200121*'],
  ['Spillolja','130203*'],
  ['Lösningsmedel, färg- och lackrester','200113*'],
  ['Elektronikskrot','200135*'],
  ['Isoleroljor','130310*'],
  ['Freoner','160211*'],
  ['Batteri','200133*'],
  ['Bly batterier','160601*'],
  ['Radioaktiva ämnen','160213*'],
  ['Blåbetong','170106*'],
  ['CFC-frigolit','170603*'],
  ['Plast innehållande Ftalater','170204*'],
  ['IFA Aska','170504'],
] as const;

export type Party = typeof receiverOptions[number];
export type Waste = {
  row: number;
  packages: string;
  packaging: string;
  estimatedKg: string;
  weighedKg: string;
  adr: '' | 'label' | 'none';
  adrLabel: string;
};
export type StrokePoint = [number, number];
export type Signoff = {date: string; name: string; strokes: StrokePoint[][]};
export type DocumentFields = {
  createdBy: string;
  project: string;
  registration: string;
  sender: Party;
  receiver: Party;
  receiverRow: number;
  deliveryNumber: string;
  waste: Waste[];
  senderSignoff: Signoff;
  receiverSignoff: Signoff;
};
export type HubChoice = {id: string; label: string; value: string};

export const customReceiver = receiverOptions.length;
export const emptyParty: Party = {name:'', address:'', organisation:'', municipality:''};
export const emptySignoff: Signoff = {date:'',name:'',strokes:[]};

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
