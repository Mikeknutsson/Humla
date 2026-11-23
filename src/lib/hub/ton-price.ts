export type Leg = {miles: string; driveMinutes: string};
export type Round = {
  id: string; pickup: string; delivery: string; returnTo: string;
  outbound: Leg; inbound: Leg; mirror: boolean;
  minutesPerMile: string; loading: string; unloading: string; waiting: string;
};
export type Vehicle = {
  id: string; name: string; hourly: string; referenceLoad: string;
  bk1Load: string; bk4Load: string; bk1Gross: string; bk4Gross: string;
};
export type Material = {
  id: string; name: string; roundId: string; vehicleId: string; transportOnly: boolean;
  listPrice: string; discount: string; purchase: string; markup: string; sale: string; tonnes: string;
};
export type TonPriceDraft = {
  customer: string; project: string; validity: string; terms: string;
  profile: 'reference' | 'bk1' | 'bk4';
  rounds: Round[]; vehicles: Vehicle[]; materials: Material[];
};

function number(value: string, max: number, min = 0) {
  if (typeof value !== 'string' || !/^\d{1,9}(?:[,.]\d{1,6})?$/.test(value.trim())) return null;
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

export function calculateRound(round: Round) {
  const speed = number(round.minutesPerMile, 1000, 0.01);
  const outbound = leg(round.outbound, speed);
  const inbound = round.mirror ? outbound : leg(round.inbound, speed);
  const loading = number(round.loading, 10000);
  const unloading = number(round.unloading, 10000);
  const waiting = number(round.waiting, 10000);
  if (!outbound || !inbound || loading === null || unloading === null || waiting === null) return null;
  const miles = outbound.miles + inbound.miles;
  const drive = outbound.minutes + inbound.minutes;
  const minutes = drive + loading + unloading + waiting;
  return minutes > 0 ? {miles, drive, minutes} : null;
}

function materialPrice(input: Material) {
  if (input.transportOnly) return {purchase: 0, sale: 0};
  if (!input.name.trim()) return null;
  const list = number(input.listPrice, 100000);
  const discount = number(input.discount, 100);
  const purchase = input.purchase.trim() === ''
    ? list === null || discount === null ? null : list * (1 - discount / 100)
    : number(input.purchase, 100000);
  if (purchase === null) return null;
  const markup = number(input.markup, 1000);
  const sale = input.sale.trim() === ''
    ? markup === null ? null : purchase * (1 + markup / 100)
    : number(input.sale, 100000);
  return sale === null ? null : {purchase, sale};
}

function vehicleLoad(vehicle: Vehicle, profile: TonPriceDraft['profile']) {
  if (profile === 'reference') return {load: number(vehicle.referenceLoad, 100, 0.001), gross: null};
  const load = number(vehicle[profile === 'bk1' ? 'bk1Load' : 'bk4Load'], 100, 0.001);
  const gross = number(vehicle[profile === 'bk1' ? 'bk1Gross' : 'bk4Gross'], 100, 0.001);
  return {load: load !== null && gross !== null && load < gross ? load : null, gross};
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
          if (!time || !price || hourly === null || load === null) return [profile, null];
          const freight = hourly * time.minutes / 60 / load;
          const delivered = price.sale + freight;
          const trips = tonnes === null ? null : Math.ceil(Math.round(tonnes * 1e6) / Math.round(load * 1e6));
          return [profile, {load, gross, freight, delivered, trips,
            miles: trips === null ? null : trips * time.miles,
            hours: trips === null ? null : trips * time.minutes / 60,
            freightAmount: tonnes === null ? null : freight * tonnes,
            materialEarnings: tonnes === null ? null : (price.sale - price.purchase) * tonnes,
            amount: tonnes === null ? null : delivered * tonnes}];
        })) as Record<TonPriceDraft['profile'], {
          load: number; gross: number | null; freight: number; delivered: number; trips: number | null;
          miles: number | null; hours: number | null; freightAmount: number | null;
          materialEarnings: number | null; amount: number | null;
        } | null>,
      };
    });
    const selected = options.find(option => option.id === material.vehicleId)?.prices[draft.profile];
    const status = !time ? 'Fyll i körsträcka och tid för rundan.'
      : !price ? 'Ange materialnamn och inköpspris eller listpris med rabatt.'
      : !selected ? 'Kontrollera ekipagets timpris och viktuppgifter.'
      : material.tonnes.trim() !== '' && tonnes === null ? 'Kontrollera mängden.'
      : null;
    return {id: material.id, price, tonnes, options, selected, status};
  });
  const quoted = materials.filter(row => row.selected && !row.status);
  const totals = quoted.reduce((sum, {selected}) => ({
    trips: sum.trips + (selected?.trips ?? 0),
    miles: sum.miles + (selected?.miles ?? 0),
    hours: sum.hours + (selected?.hours ?? 0),
    freightAmount: sum.freightAmount + (selected?.freightAmount ?? 0),
    materialEarnings: sum.materialEarnings + (selected?.materialEarnings ?? 0),
    amount: sum.amount + (selected?.amount ?? 0),
  }), {trips: 0, miles: 0, hours: 0, freightAmount: 0, materialEarnings: 0, amount: 0});
  return {rounds, materials, totals};
}

export const newRound = (id: string): Round => ({
  id, pickup: '', delivery: '', returnTo: '', mirror: true,
  outbound: {miles: '', driveMinutes: ''}, inbound: {miles: '', driveMinutes: ''},
  minutesPerMile: '11', loading: '15', unloading: '15', waiting: '0',
});
export const newMaterial = (id: string, roundId: string, vehicleId: string): Material => ({
  id, roundId, vehicleId, name: '', transportOnly: false,
  listPrice: '', discount: '10', purchase: '', markup: '10', sale: '', tonnes: '',
});
export const initialTonPriceDraft: TonPriceDraft = {
  customer: '', project: '', validity: '', terms: '',
  profile: 'reference',
  rounds: [newRound('round')],
  materials: [newMaterial('material', 'round', 'trailer')],
  vehicles: [
    {id: 'truck', name: 'Bil', hourly: '995', referenceLoad: '16'},
    {id: 'trailer', name: 'Bil + kärra', hourly: '1395', referenceLoad: '34'},
    {id: 'cassette', name: 'Kassett', hourly: '1480', referenceLoad: '38'},
  ].map(vehicle => ({...vehicle, bk1Load: '', bk4Load: '', bk1Gross: '', bk4Gross: ''})),
};
