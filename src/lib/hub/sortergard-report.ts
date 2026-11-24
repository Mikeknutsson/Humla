export type Candidate = {address:string; source:string; reference:string|null; score:number; reason:string};
export type Weighing = {
  id:string; trans_id:string; day:string; reg:string|null; sender:string|null; recipient:string|null; material:string|null;
  tonnes:number; stock:string|null; kind:string; status:'verified'|'likely'|'missing'|'pending';
  origin:string; destination:string; source:string; reason:string; confidence:number; candidates:Candidate[]; raw:Record<string,unknown>;
};
export type ReportVersion = {id:string; year:number; version:number; created_at:string; created_by_label:string; incomplete:boolean};
export const statusLabels = {verified:'Verifierad',likely:'Sannolik',missing:'Adress saknas',pending:'Obehandlad'};
export const yardNumber = new Intl.NumberFormat('sv-SE',{maximumFractionDigits:3});
export function yardTotals(rows: Weighing[]) {
  const totals = {in:0,out:0,external:0,verified:0,likely:0,missing:0,pending:0};
  for (const row of rows) {
    totals[row.status]++;
    if (row.kind === 'Inleverans') totals.in += row.tonnes;
    if (row.kind === 'Utleverans') totals.out += row.tonnes;
    if (row.kind === 'Externleverans') totals.external += row.tonnes;
  }
  return totals;
}
export function yardMaterials(rows: Weighing[]) {
  const groups = new Map<string,{material:string; stock:string; in:number; out:number; external:number; count:number; unverified:number}>();
  for (const row of rows) {
    const material = row.material || 'Material saknas';
    const stock = row.stock || 'Lagerplats saknas';
    const key = JSON.stringify([material,stock]);
    const item = groups.get(key) ?? {material,stock,in:0,out:0,external:0,count:0,unverified:0};
    item.count++;
    if (row.status !== 'verified') item.unverified++;
    if (row.kind === 'Inleverans') item.in += row.tonnes;
    if (row.kind === 'Utleverans') item.out += row.tonnes;
    if (row.kind === 'Externleverans') item.external += row.tonnes;
    groups.set(key,item);
  }
  return [...groups.values()].sort((a,b)=>a.stock.localeCompare(b.stock,'sv') || a.material.localeCompare(b.material,'sv'));
}
export function reportAddress(row: Weighing) {
  return row.kind === 'Externleverans' ? [row.origin && 'Från '+row.origin,row.destination && 'Till '+row.destination].filter(Boolean).join(' → ')
    : row.kind === 'Inleverans' ? row.origin : row.destination;
}
