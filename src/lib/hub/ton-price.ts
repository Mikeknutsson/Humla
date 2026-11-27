export type ReturnLoad = {material: string; tonnes: string; share: string; contribution: string; extraMiles: string; extraMinutes: string};
export const emptyReturnLoad: ReturnLoad = {material:'',tonnes:'',share:'100',contribution:'',extraMiles:'0',extraMinutes:'0'};
export type Leg = {miles: string; driveMinutes: string};
export const pukavikStartAddress = 'Karlshamnsvägen 329, 294 93 Sölvesborg';
export const zeroStartLeg: Leg = {miles:'0',driveMinutes:'0'};
export type Round = {
  id: string; pickup: string; delivery: string; returnTo: string;
  pickupPoint?: {lat: number; lng: number};
  deliveryPoint?: {lat: number; lng: number};
  returnLoad?: ReturnLoad;
  start?: Leg;
  autoHandling?: boolean;
  pickupSiteId?: string; deliverySiteId?: string; pickupPlaceId?: string; deliveryPlaceId?: string; returnPlaceId?: string;
  outbound: Leg; inbound: Leg; mirror: boolean;
  minutesPerMile: string; loading: string; unloading: string; waiting: string;
};
export type Vehicle = {
  id: string; name: string; hourly: string; referenceLoad: string;
  bk1Load: string; bk4Load: string; bk1Gross: string; bk4Gross: string;
};
export type Material = {
  id: string; name: string; roundId: string; vehicleId: string; transportOnly: boolean;
  bankRateId?: string; bankSiteId?: string; bankKind?: 'purchase' | 'tip';
  listPrice: string; discount: string; purchase: string; markup: string; sale: string; tonnes: string;
};
export type TonPriceDraft = {
  customer: string; project: string; validity: string; terms: string;
  offerTermsInitialized?: true;
  priceDate?: string; specialCassette?: boolean; showBk4?: boolean;
  profile: 'reference' | 'bk1' | 'bk4';
  rounds: Round[]; vehicles: Vehicle[]; materials: Material[];
};

export const offerTermsMaxLength = 4000;
export const defaultOfferTerms = [
  'Förutsättningar:',
  'I priset ingår 10 min lastning med bil + släp.',
  'Tippning i hög. Vid spridning, tippning på olika ställen eller lång backning tillkommer mer kostnad.',
  'Priserna förutsätter normal arbetstid vardagar. I händelse av kostnadsökningar utanför vår kontroll förbehåller vi oss rätten till motsvarande prisjusteringar.',
  'Lagstadgad mervärdesskatt tillkommer.',
  'Övriga villkor enligt Alltrans 2007. Faktura förfaller till betalning på i densamma angiven förfallodag, såvida annat ej överenskommits.',
  'Efter förfallodagen debiteras dröjsmålsränta med diskontot + 8 %. Lagstadgad mervärdesskatt tillkommer.',
].join('\n\n');

function number(value: string, max: number, min = 0) {
  if (typeof value !== 'string' || !/^-?\d{1,9}(?:[,.]\d{1,6})?$/.test(value.trim())) return null;
  const parsed = Number(value.trim().replace(',', '.'));
  return parsed >= min && parsed <= max ? parsed : null;
}

function leg(input: Leg, minutesPerMile: number | null) {
  const miles = number(input.miles, 1000);
  const minutes = input.driveMinutes.trim() === ''
    ? miles === null || minutesPerMile === null ? null : miles * minutesPerMile
    : number(input.driveMinutes, 100000);
  return miles === null || minutes === null ? null : {miles, minutes};
}

export function calculateStartLeg(round: Round) {
  return round.start ? leg(round.start,number(round.minutesPerMile,1000,0.01)) : null;
}

export function calculateRound(round: Round) {
  const speed = number(round.minutesPerMile, 1000, 0.01);
  const start = round.start ? calculateStartLeg(round) : {miles:0,minutes:0};
  const outbound = leg(round.outbound, speed);
  const inbound = round.mirror ? outbound : leg(round.inbound, speed);
  const standardHandling = outbound && outbound.miles < 1.2 ? 10 : 15;
  const loading = round.autoHandling ? standardHandling : number(round.loading, 10000);
  const unloading = round.autoHandling ? standardHandling : number(round.unloading, 10000);
  const waiting = number(round.waiting, 10000);
  if (!start || !outbound || !inbound || loading === null || unloading === null || waiting === null) return null;
  const miles = outbound.miles + inbound.miles;
  const drive = outbound.minutes + inbound.minutes;
  const minutes = drive + loading + unloading + waiting;
  if (minutes <= 0) return null;
  const load = round.returnLoad;
  if (!load) return {miles, drive, minutes, outbound, inbound, start, returnCredit:0, returnTonnes:0, returnLoadWeight:0};
  const tonnes = number(load.tonnes, 100, 0.001);
  const share = number(load.share, 100);
  const contribution = number(load.contribution, 100000, -100000);
  const extraMiles = number(load.extraMiles, 1000);
  const extraMinutes = number(load.extraMinutes, 10000);
  if (tonnes === null || share === null || contribution === null || extraMiles === null || extraMinutes === null) return null;
  const fraction = share / 100;
  return {miles:miles + extraMiles * fraction, drive, minutes:minutes + extraMinutes * fraction, outbound, inbound, start,
    returnCredit:tonnes * contribution * fraction, returnTonnes:tonnes * fraction, returnLoadWeight:fraction > 0 ? tonnes : 0};
}

function materialPrice(input: Material) {
  if (input.transportOnly) return {purchase: 0, sale: 0};
  if (!input.name.trim()) return null;
  const list = number(input.listPrice, 100000);
  const discount = number(input.discount, 100);
  const purchase = input.purchase.trim() === ''
    ? list === null || discount === null ? null : list * (1 - discount / 100)
    : number(input.purchase, 100000, input.bankKind === 'tip' ? -100000 : 0);
  if (purchase === null) return null;
  const markup = number(input.markup, 1000);
  const sale = input.sale.trim() === ''
    ? markup === null ? null : (purchase + Math.abs(purchase) * markup / 100)
    : number(input.sale, 100000, input.bankKind === 'tip' ? -100000 : 0);
  return sale === null ? null : {purchase, sale};
}

function vehicleLoad(vehicle: Vehicle, profile: TonPriceDraft['profile']) {
  if (profile === 'reference') return {load: number(vehicle.referenceLoad, 100, 0.001), gross: null};
  const load = number(vehicle[profile === 'bk1' ? 'bk1Load' : 'bk4Load'], 100, 0.001);
  const gross = number(vehicle[profile === 'bk1' ? 'bk1Gross' : 'bk4Gross'], 100, 0.001);
  return {load: load !== null && gross !== null && load < gross ? load : null, gross};
}

export function quickReferenceLoad(draft: TonPriceDraft): number | null {
  const vehicle = draft.vehicles.find(item => item.id === 'trailer');
  if (!vehicle || draft.profile === 'reference' || vehicleLoad(vehicle,draft.profile).load !== null ||
    number(vehicle.hourly,100000) === null) return null;
  return vehicleLoad(vehicle,'reference').load;
}

export function calculateTonPrices(draft: TonPriceDraft) {
  const rounds = draft.rounds.map(round => ({id: round.id, result: calculateRound(round)}));
  const roundById = new Map(rounds.map(round => [round.id, round.result]));
  const profiles = ['reference', 'bk1', 'bk4'] as const;
  const materials = draft.materials.map(material => {
    const time = roundById.get(material.roundId);
    const price = materialPrice(material);
    const tonnes = number(material.tonnes, 10000000);
    const options = draft.vehicles.map(vehicle => {
      const hourly = number(vehicle.hourly, 100000);
      return {
        id: vehicle.id,
        prices: Object.fromEntries(profiles.map(profile => {
          const {load, gross} = vehicleLoad(vehicle, profile);
          if (!time || !price || hourly === null || load === null || time.returnLoadWeight > load) return [profile, null];
          const trips = tonnes === null ? null : Math.ceil(Math.round(tonnes * 1e6) / Math.round(load * 1e6));
          const roundFreight = (hourly * time.minutes / 60 - time.returnCredit) / load;
          const startFreight = hourly * time.start.minutes / 60 / (tonnes || load);
          const freight = roundFreight + startFreight;
          const delivered = price.sale + freight;
          return [profile, {load, gross, freight, roundFreight, startFreight, delivered, trips,
            miles: trips === null ? null : trips * time.miles + (trips ? time.start.miles : 0),
            hours: trips === null ? null : (trips * time.minutes + (trips ? time.start.minutes : 0)) / 60,
            returnTonnes: trips === null ? null : trips * time.returnTonnes,
            freightAmount: tonnes === null ? null : freight * tonnes,
            materialEarnings: tonnes === null ? null : (price.sale - price.purchase) * tonnes,
            amount: tonnes === null ? null : delivered * tonnes}];
        })) as Record<TonPriceDraft['profile'], {
          load: number; gross: number | null; freight: number; roundFreight: number; startFreight: number; delivered: number; trips: number | null;
          miles: number | null; hours: number | null; returnTonnes: number | null; freightAmount: number | null;
          materialEarnings: number | null; amount: number | null;
        } | null>,
      };
    });
    const selected = options.find(option => option.id === material.vehicleId)?.prices[draft.profile];
    const status = !time ? 'Fyll i körsträcka och tid för rundan.'
      : !price ? 'Ange materialnamn och inköpspris eller listpris med rabatt.'
      : !selected ? 'Kontrollera ekipagets timpris, vikt och eventuell returlast.'
      : material.tonnes.trim() !== '' && tonnes === null ? 'Kontrollera mängden.'
      : null;
    return {id: material.id, price, tonnes, options, selected, status};
  });
  const quoted = materials.filter(row => row.selected && !row.status);
  const totals = quoted.reduce((sum, {selected}) => ({
    trips: sum.trips + (selected?.trips ?? 0),
    miles: sum.miles + (selected?.miles ?? 0),
    hours: sum.hours + (selected?.hours ?? 0),
    returnTonnes: sum.returnTonnes + (selected?.returnTonnes ?? 0),
    freightAmount: sum.freightAmount + (selected?.freightAmount ?? 0),
    materialEarnings: sum.materialEarnings + (selected?.materialEarnings ?? 0),
    amount: sum.amount + (selected?.amount ?? 0),
  }), {trips: 0, miles: 0, hours: 0, returnTonnes: 0, freightAmount: 0, materialEarnings: 0, amount: 0});
  return {rounds, materials, totals};
}

export const newRound = (id: string): Round => ({
  id, pickup: '', delivery: '', returnTo: '', mirror: true,
  outbound: {miles: '', driveMinutes: ''}, inbound: {miles: '', driveMinutes: ''},
  minutesPerMile: '11', autoHandling:true, loading: '15', unloading: '15', waiting: '0',
});
export const newMaterial = (id: string, roundId: string, vehicleId: string): Material => ({
  id, roundId, vehicleId, name: '', transportOnly: false,
  listPrice: '', discount: '10', purchase: '', markup: '10', sale: '', tonnes: '',
});
export const initialTonPriceDraft: TonPriceDraft = {
  customer: '', project: '', validity: '', terms: defaultOfferTerms, offerTermsInitialized: true,
  profile: 'reference',
  rounds: [newRound('round')],
  materials: [newMaterial('material', 'round', 'trailer')],
  vehicles: [
    {id: 'truck', name: 'Bil', hourly: '995', referenceLoad: '16'},
    {id: 'trailer', name: 'Bil + kärra', hourly: '1395', referenceLoad: '34'},
    {id: 'cassette', name: 'Kassett', hourly: '1480', referenceLoad: '38'},
  ].map(vehicle => ({...vehicle, bk1Load: '', bk4Load: '', bk1Gross: '', bk4Gross: ''})),
};
