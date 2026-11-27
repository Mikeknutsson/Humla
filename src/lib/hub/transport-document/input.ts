import {isMunicipality, type DocumentFields, type Location, type Party, type Waste} from './fields';
import {wasteCodeAt} from './waste-codes';

function record(value: unknown) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Dokumentet innehåller ofullständiga uppgifter.');
  return value as Record<string,unknown>;
}

function text(value: unknown, max: number, label: string, required = false) {
  if (typeof value !== 'string' || value.trim().length > max || (required && !value.trim())) {
    throw new Error(`Kontrollera ${label}.`);
  }
  return value.normalize('NFC').trim().replace(/\s+/g,' ').replace(/[\u00ad\u200b]/g,'');
}

function party(value: unknown, role: string): Party {
  const data = record(value);
  const organisation = text(data.organisation,30,`identifieringsnumret för ${role}`,true);
  const compact = organisation.replace(/[\s+-]/g,'').toUpperCase();
  const swedish = /^(\d{6}|\d{8})(\d{4})$/.exec(compact);
  const taxNumber = /^(?=.*\d)[A-Z0-9 .-]{3,30}$/i.test(organisation);
  if (!swedish && !taxNumber) {
    throw new Error(`Ange ett person-, organisations- eller skatteregistreringsnummer för ${role}.`);
  }
  const formatted = swedish ? swedish[1] + (organisation.includes('+') ? '+' : '-') + swedish[2] : organisation.toUpperCase();
  return {name:text(data.name,110,`namnet på ${role}`,true),
    address:text(data.address,220,`postadressen för ${role}`,true),organisation:formatted};
}

function location(value: unknown, label: string): Location {
  const data = record(value);
  const address = text(data.value,240,label,true);
  const coordinate = address.match(/^(-?\d{1,3}(?:\.\d+)?),\s*(-?\d{1,3}(?:\.\d+)?)$/);
  if (coordinate && (Math.abs(Number(coordinate[1])) > 90 || Math.abs(Number(coordinate[2])) > 180)) {
    throw new Error(`Kontrollera koordinaterna för ${label}.`);
  }
  const municipality = text(data.municipality,4,`kommunkoden för ${label}`);
  if (municipality && !isMunicipality(municipality)) throw new Error(`Välj en giltig kommunkod för ${label}.`);
  return {value:address,municipality};
}

function weight(value: unknown, label: string) {
  const kg = text(value,18,label).replace(/ /g,'').replace(',','.');
  if (kg && (!/^\d{1,10}(?:\.\d{1,3})?$/.test(kg) || Number(kg) <= 0)) {
    throw new Error(`Ange ${label} i kg.`);
  }
  return kg;
}

function wasteItem(value: unknown, date: string, index: number): Waste {
  const row = record(value);
  const label = `avfallsrad ${index+1}`;
  const code = wasteCodeAt(text(row.code,15,`avfallskoden på ${label}`,true),date);
  if (!code) throw new Error(`Avfallskoden på ${label} saknas i avfallsförteckningen för transportdatumet.`);
  const estimatedKg = weight(row.estimatedKg ?? '',`uppskattad vikt på ${label}`);
  const weighedKg = weight(row.weighedKg ?? '',`invägd vikt på ${label}`);
  if (!estimatedKg && !weighedKg) throw new Error(`Ange uppskattad eller invägd vikt på ${label}.`);
  const packages = text(row.packages,10,`antal kollin på ${label}`);
  if (packages && (!/^\d+$/.test(packages) || Number(packages) <= 0)) throw new Error(`Kontrollera antal kollin på ${label}.`);
  return {code,estimatedKg,weighedKg,packages,
    name:text(row.name,180,`benämningen på ${label}`,true),packaging:text(row.packaging,45,`emballaget på ${label}`)};
}

export function parseTransportDocument(value: unknown): DocumentFields {
  const data = record(value);
  const date = text(data.date,10,'transportdatumet',true);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || !Number.isFinite(Date.parse(date)) ||
      new Date(date).toISOString().slice(0,10) !== date) throw new Error('Kontrollera transportdatumet.');
  if (!Array.isArray(data.waste) || !data.waste.length || data.waste.length > 100) throw new Error('Ange mellan 1 och 100 avfallsrader.');
  const consignor = data.consignor === null ? null : party(data.consignor,'lämnaren');
  return {
    date,consignor,carrier:party(data.carrier,'transportören'),receiver:party(data.receiver,'mottagaren'),
    workifyOrderNumber:text(data.workifyOrderNumber ?? '',50,'Workifys ordernummer'),
    registration:text(data.registration,24,'registreringsnumret').toUpperCase(),
    origin:location(data.origin,'hämtplatsen'),destination:location(data.destination,'den slutliga mottagningsplatsen'),
    deliveryNumber:text(data.deliveryNumber,50,'inleveransnumret'),adrReference:text(data.adrReference,70,'ADR-referensen'),
    waste:data.waste.map((row,index) => wasteItem(row,date,index)),carrierSigner:text(data.carrierSigner,100,'transportörens namnförtydligande'),
    consignorSigner:consignor ? text(data.consignorSigner,100,'lämnarens namnförtydligande') : '',
  };
}
