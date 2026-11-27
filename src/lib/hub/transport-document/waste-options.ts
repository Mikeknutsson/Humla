import {availableWasteCodes} from './waste-codes';

// Preserve the order of the codes in Elleholms' Word template. A code appears once,
// even where the template lists more than one material under it.
const favorites = [
  ['17 06 05*','Byggmaterial med asbest'],
  ['17 02 04*','Glas, plast eller trä med farliga ämnen','tryckimpregnerat trä plast med ftalater'],
  ['17 09 02*','Bygg- och rivningsavfall med PCB','fogmassa isolerrutor'],
  ['17 03 01*','Bitumenblandning med stenkolstjära','tjärasfalt PAH'],
  ['13 01 01*','Hydraulolja med PCB'],
  ['13 07 01*','Eldningsolja och diesel'],
  ['13 07 02*','Bensin'],
  ['15 02 02*','Förorenade absorbenter, torkdukar och skyddskläder','olja oljeabsorbent'],
  ['20 01 21*','Lysrör och annat kvicksilverhaltigt avfall'],
  ['20 01 13*','Lösningsmedel'],
  ['20 01 35*','Elavfall med farliga komponenter','elektronikskrot'],
  ['13 03 10*','Övriga isoler- och värmeöverföringsoljor'],
  ['16 02 11*','Kasserad utrustning med CFC, HCFC eller HFC','freon kylanläggning'],
  ['20 01 33*','Batterier och ackumulatorer med farligt innehåll'],
  ['16 06 01*','Blybatterier'],
  ['16 02 13*','Kasserad utrustning med farliga komponenter'],
  ['17 01 06*','Betong, tegel, klinker eller keramik med farliga ämnen','blåbetong'],
  ['17 06 03*','Annat isolermaterial med farliga ämnen','CFC frigolit cellplast'],
  ['17 05 04','Övrig jord och sten','schaktmassor jord schakt'],
] as const;

const construction = [
  ['17 01 01','Betong'],
  ['17 01 02','Tegel'],
  ['17 01 03','Klinker och keramik'],
  ['17 01 07','Övriga blandningar av betong, tegel, klinker och keramik'],
  ['17 02 01','Trä','returträ virke'],
  ['17 02 02','Glas'],
  ['17 02 03','Plast'],
  ['17 03 02','Övriga bitumenblandningar','asfalt asfaltskross'],
  ['17 03 03*','Stenkolstjära och tjärprodukter'],
  ['17 04 01','Koppar, brons och mässing'],
  ['17 04 02','Aluminium'],
  ['17 04 03','Bly'],
  ['17 04 04','Zink'],
  ['17 04 05','Järn och stål'],
  ['17 04 06','Tenn'],
  ['17 04 07','Blandade metaller'],
  ['17 04 09*','Metallavfall förorenat av farliga ämnen'],
  ['17 04 10*','Kablar med olja, tjära eller andra farliga ämnen'],
  ['17 04 11','Övriga kablar'],
  ['17 05 03*','Jord och sten med farliga ämnen','förorenade schaktmassor jord schakt'],
  ['17 05 05*','Muddermassor med farliga ämnen'],
  ['17 05 06','Övriga muddermassor'],
  ['17 05 07*','Spårballast med farliga ämnen'],
  ['17 05 08','Övrig spårballast'],
  ['17 06 01*','Isolermaterial med asbest'],
  ['17 06 04','Övrigt isolermaterial','mineralull stenull glasull'],
  ['17 08 01*','Gipsbaserat byggmaterial förorenat av farliga ämnen'],
  ['17 08 02','Övrigt gipsbaserat byggmaterial','gipsskivor gips'],
  ['17 09 01*','Bygg- och rivningsavfall med kvicksilver'],
  ['17 09 03*','Övrigt bygg- och rivningsavfall med farliga ämnen'],
  ['17 09 04','Övrigt blandat bygg- och rivningsavfall'],
] as const;

const related = [
  ['08 01 11*','Färg- och lackavfall med lösningsmedel eller andra farliga ämnen'],
  ['08 01 12','Övrigt färg- och lackavfall'],
  ['08 04 09*','Lim- och fogmasseavfall med lösningsmedel eller andra farliga ämnen'],
  ['08 04 10','Övrigt lim- och fogmasseavfall'],
  ['13 02 04*','Klorerade mineralbaserade motor-, transmissions- och smörjoljor','spillolja'],
  ['13 02 05*','Icke-klorerade mineralbaserade motor-, transmissions- och smörjoljor','spillolja'],
  ['13 02 06*','Syntetiska motor-, transmissions- och smörjoljor','spillolja'],
  ['13 02 07*','Biologiskt lättnedbrytbara motor-, transmissions- och smörjoljor','spillolja'],
  ['13 02 08*','Övriga motor-, transmissions- och smörjoljor','spillolja'],
  ['15 01 01','Pappers- och kartongförpackningar'],
  ['15 01 02','Plastförpackningar'],
  ['15 01 03','Träförpackningar'],
  ['15 01 04','Metallförpackningar'],
  ['15 01 06','Blandade förpackningar'],
  ['15 01 07','Glasförpackningar'],
  ['15 01 10*','Förpackningar med rester av eller förorenade av farliga ämnen'],
  ['15 01 11*','Metallförpackningar med farlig fast porös fyllning'],
  ['15 02 03','Övriga absorbenter, filtermaterial, torkdukar och skyddskläder'],
  ['16 02 09*','Transformatorer och kondensatorer med PCB'],
  ['16 02 10*','Annan kasserad utrustning med PCB'],
  ['16 02 14','Övrig kasserad elektrisk och elektronisk utrustning'],
  ['16 02 15*','Farliga komponenter från kasserad utrustning'],
  ['16 02 16','Övriga komponenter från kasserad utrustning'],
  ['19 13 01*','Fast avfall med farliga ämnen från marksanering'],
  ['19 13 02','Övrigt fast avfall från marksanering'],
  ['19 13 03*','Marksaneringsslam med farliga ämnen'],
  ['19 13 04','Övrigt marksaneringsslam'],
  ['19 13 05*','Grundvattensanering – slam med farliga ämnen'],
  ['19 13 06','Övrigt slam från grundvattensanering'],
  ['19 13 07*','Grundvattensanering – vätska med farliga ämnen'],
  ['19 13 08','Övrig vätska från grundvattensanering'],
  ['20 01 27*','Färg, tryckfärg, lim och hartser med farliga ämnen'],
  ['20 01 28','Övrig färg, tryckfärg, lim och hartser'],
  ['20 01 34','Övriga batterier och ackumulatorer'],
  ['20 01 36','Övrig kasserad elektrisk och elektronisk utrustning'],
  ['20 02 01','Biologiskt nedbrytbart trädgårds- och parkavfall','ris grenar växtdelar'],
  ['20 02 02','Jord och sten från trädgårds- och parkavfall'],
] as const;

export function wasteChoices(date: string) {
  const groups = [
    {label:'Favoriter',items:favorites},
    {label:'Mark och rivning',items:construction},
    {label:'Relaterade avfallskoder',items:related},
  ] as const;
  const available = new Set(availableWasteCodes(date));
  const choices = groups.flatMap(({label,items}) => items.flatMap(([code,name,keywords]) => {
    if (!available.delete(code)) return [];
    return [{value:code,label:`${code} – ${name}`,name,keywords,group:label as string}];
  }));
  return [
    ...choices,
    ...[...available].map(code => ({value:code,label:code,name:'',keywords:undefined,group:'Övriga avfallskoder'})),
  ];
}
