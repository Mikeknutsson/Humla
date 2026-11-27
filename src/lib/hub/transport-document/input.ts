import {customReceiver, isMunicipality, receiverOptions, wasteOptions, type DocumentFields, type Party, type Signoff, type StrokePoint, type Waste} from './fields';

function record(value: unknown) {
  if (typeof value !== 'object' || !value || Array.isArray(value)) throw new Error('Dokumentet innehåller ofullständiga uppgifter.');
  return value as Record<string,unknown>;
}

function text(value: unknown, max: number, label: string, required = false) {
  if (typeof value !== 'string' || value.trim().length > max || (required && !value.trim())) {
    throw new Error(`Kontrollera fältet ${label}.`);
  }
  return value.normalize('NFC').trim().replace(/\s+/g,' ');
}

function party(value: unknown, label: string): Party {
  const data = record(value);
  const organisation = text(data.organisation,18,`organisationsnummer för ${label}`,true);
  if (!/^\d{6}-?\d{4}$/.test(organisation)) throw new Error(`Ange ett organisationsnummer med tio siffror för ${label}.`);
  const municipality = text(data.municipality,4,`kommunkod för ${label}`,true);
  if (!isMunicipality(municipality)) throw new Error(`Välj en kommunkod för ${label}.`);
  return {name:text(data.name,80,label,true),address:text(data.address,160,`postadress för ${label}`,true),
    organisation:organisation.replace(/^(\d{6})-?(\d{4})$/,'$1-$2'),municipality};
}

function signoff(value: unknown): Signoff {
  const data = record(value);
  const date = text(data.date,10,'datum');
  if (date && (!/^\d{4}-\d{2}-\d{2}$/.test(date) || !Number.isFinite(Date.parse(date)) ||
    new Date(date).toISOString().slice(0,10) !== date)) throw new Error('Kontrollera datumet i underskriftsrutan.');
  const name = text(data.name,90,'namnförtydligande');
  if (!Array.isArray(data.strokes) || data.strokes.length > 80) throw new Error('Underskriften är för stor.');
  let count = 0;
  const strokes = data.strokes.map((stroke: unknown) => {
    if (!Array.isArray(stroke) || (count += stroke.length) > 3500) throw new Error('Underskriften är för stor.');
    return stroke.map((point: unknown): StrokePoint => {
      if (!Array.isArray(point) || point.length !== 2 ||
        !point.every(n => typeof n === 'number' && Number.isFinite(n) && n >= 0 && n <= 1)) {
        throw new Error('Underskriften kunde inte läsas.');
      }
      return [point[0],point[1]];
    });
  });
  if (count && (!date || !name)) throw new Error('Ange datum och namnförtydligande för varje inskriven underskrift.');
  return {date,name,strokes};
}

function quantity(value: unknown, label: string, whole = false) {
  const raw = text(value,18,label).replace(/ /g,'');
  const format = whole ? /^\d+$/ : /^\d+(?:[.,]\d{1,3})?$/;
  if (raw && !format.test(raw)) throw new Error(`Ange ${label} som ett tal.`);
  return raw.replace('.',',');
}

export function parseTransportDocument(value: unknown): DocumentFields {
  const data = record(value);
  const receiverRow = data.receiverRow;
  if (typeof receiverRow !== 'number' || !Number.isInteger(receiverRow) || receiverRow < 0 || receiverRow > customReceiver) {
    throw new Error('Välj mottagare.');
  }
  if (!Array.isArray(data.waste) || data.waste.length === 0 || data.waste.length > wasteOptions.length) {
    throw new Error('Välj minst ett avfallsslag.');
  }
  const seen = new Set<number>();
  const waste = data.waste.map((item: unknown): Waste => {
    const entry = record(item);
    const row = entry.row;
    if (typeof row !== 'number' || !Number.isInteger(row) || !wasteOptions[row] || seen.has(row)) {
      throw new Error('Kontrollera valda avfallsslag.');
    }
    seen.add(row);
    const {adr} = entry;
    if (adr !== '' && adr !== 'label' && adr !== 'none') throw new Error('Kontrollera ADR-valet.');
    return {row,packages:quantity(entry.packages,'antal kollin',true),packaging:text(entry.packaging,28,'emballage'),
      estimatedKg:quantity(entry.estimatedKg,'uppskattad vikt'),weighedKg:quantity(entry.weighedKg,'invägd vikt'),
      adr,adrLabel:adr === 'label' ? text(entry.adrLabel,24,'ADR-etikett',true) : ''};
  });
  return {
    createdBy:text(data.createdBy,90,'dokument skapat av',true),
    project:text(data.project,28,'projekt',true),registration:text(data.registration,24,'registreringsnummer',true).toUpperCase(),
    sender:party(data.sender,'avsändaren'), receiver:receiverRow === customReceiver ? party(data.receiver,'mottagaren') : receiverOptions[receiverRow],
    receiverRow, deliveryNumber:text(data.deliveryNumber,30,'inleveransnummer'), waste,
    senderSignoff:signoff(data.senderSignoff), receiverSignoff:signoff(data.receiverSignoff),
  };
}
