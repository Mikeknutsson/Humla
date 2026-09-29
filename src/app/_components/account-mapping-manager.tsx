"use client";

import { useState } from "react";
import { AlertTriangle, CheckCircle2, Power, Plus } from "lucide-react";
import {
  ACCOUNT_CATEGORIES, CALCULATION_ROLES,
  type AccountCategory, type AccountMapping, type CalculationRole,
} from "@/lib/kpi/account-mapping";

type UnmappedAccount = { account: string; description?: string | null; row_count: number; amount: number };

const currency = new Intl.NumberFormat("sv-SE", { style: "currency", currency: "SEK", maximumFractionDigits: 0 });

export function AccountMappingManager({ mappings, unmapped, canManage }: { mappings: AccountMapping[]; unmapped: UnmappedAccount[]; canManage: boolean }) {
  const [busy, setBusy] = useState<string | null>(null);
  const [message, setMessage] = useState<{ type: "error" | "success"; text: string } | null>(null);
  const [role, setRole] = useState<CalculationRole>("cost");
  const [category, setCategory] = useState<AccountCategory>("other");

  async function submit(formData: FormData) {
    try {
    setBusy("create");
    setMessage(null);
    const accountFrom = String(formData.get("accountFrom") ?? "");
    const accountTo = String(formData.get("accountTo") ?? "") || accountFrom;
    const response = await fetch("/api/kpi/account-mappings", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        accountFrom, accountTo,
        name: formData.get("name"),
        calculationRole: role,
        costCategory: category,
        includeInVehicleResult: formData.get("includeInVehicleResult") === "on",
        priority: formData.get("priority"),
        validFrom: formData.get("validFrom"),
        validTo: formData.get("validTo"),
        notes: formData.get("notes"),
      }),
    });
    const result = await response.json();
    if (!response.ok) {
      setMessage({ type: "error", text: result.error ?? "Regeln kunde inte sparas." });
      setBusy(null);
      return;
    }
    setMessage({ type: "success", text: "Kontoregeln har sparats och börjar gälla enligt giltighetsdatumet." });
    window.location.reload();
    } catch {
      setMessage({ type: "error", text: "Anslutningen avbröts. Ladda om och kontrollera regelregistret innan du försöker igen." });
    } finally { setBusy(null); }
  }

  async function toggle(mapping: AccountMapping) {
    try {
    setBusy(mapping.id);
    setMessage(null);
    const response = await fetch("/api/kpi/account-mappings", {
      method: "PATCH",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ id: mapping.id, action: "toggle", enabled: !mapping.enabled }),
    });
    const result = await response.json();
    if (!response.ok) {
      setMessage({ type: "error", text: result.error ?? "Regeln kunde inte uppdateras." });
      setBusy(null);
      return;
    }
    window.location.reload();
    } catch {
      setMessage({ type: "error", text: "Anslutningen avbröts. Ladda om för att kontrollera regelns status." });
    } finally { setBusy(null); }
  }

  function changeRole(next: CalculationRole) {
    setRole(next);
    if (next === "fuel") setCategory("fuel");
  }

  const categoryOptions = Object.entries(ACCOUNT_CATEGORIES).filter(([key]) => role === "fuel" ? key === "fuel" : true);

  return <div className="account-layout">
    {unmapped.length > 0 && <section className="panel unmapped-panel"><div className="panel-head"><div><span className="section-kicker">Fail-closed</span><h2>Ej mappade konton</h2></div><AlertTriangle size={20}/></div><p>Dessa kostnader påverkar inte KPI eller resultat förrän de har fått en aktiv, verifierad kontoregel.</p><div className="table-wrap"><table><thead><tr><th>Status</th><th>Konto</th><th>Beskrivning</th><th>Rader</th><th>Belopp</th></tr></thead><tbody>{unmapped.map((item) => <tr key={item.account}><td><span className="unmapped-pill">Ej mappad</span></td><td><strong>{item.account}</strong></td><td>{item.description ?? "–"}</td><td>{item.row_count}</td><td>{currency.format(Number(item.amount))}</td></tr>)}</tbody></table></div></section>}

    {canManage && <section className="panel"><div className="panel-head"><div><span className="section-kicker">Ny regel</span><h2>Koppla konto eller kontointervall</h2></div><Plus size={20}/></div><form className="account-form" action={submit}>
      <label>Från konto<input name="accountFrom" inputMode="numeric" pattern="[0-9]+" required placeholder="Ex. 5010"/></label>
      <label>Till konto<input name="accountTo" inputMode="numeric" pattern="[0-9]+" placeholder="Samma som från"/></label>
      <label className="wide">Regelnamn<input name="name" required maxLength={120} placeholder="Ex. Diesel och drivmedel"/></label>
      <label>Beräkningsroll<select value={role} onChange={(event) => changeRole(event.target.value as CalculationRole)}>{Object.entries(CALCULATION_ROLES).map(([key, label]) => <option value={key} key={key}>{label}</option>)}</select></label>
      <label>Kategori<select value={category} onChange={(event) => setCategory(event.target.value as AccountCategory)}>{categoryOptions.map(([key, label]) => <option value={key} key={key}>{label}</option>)}</select></label>
      <label>Gäller från<input name="validFrom" type="date" required defaultValue="2026-09-01"/></label>
      <label>Gäller till<input name="validTo" type="date"/></label>
      <label>Prioritet<input name="priority" type="number" min="0" max="10000" defaultValue="100" required/></label>
      <label className="check-line"><input name="includeInVehicleResult" type="checkbox" defaultChecked/>Ta med i fordonsresultat</label>
      <label className="wide">Anteckning<input name="notes" maxLength={500} placeholder="Valfri förklaring av regeln"/></label>
      <div className="wide form-actions"><button className="primary" disabled={busy === "create"}>{busy === "create" ? "Sparar…" : "Spara kontoregel"}</button></div>
    </form></section>}

    {message && <div className={`message ${message.type}`}>{message.type === "success" ? <CheckCircle2 size={18}/> : <AlertTriangle size={18}/>} {message.text}</div>}

    <section className="panel account-rules"><div className="panel-head"><div><span className="section-kicker">Regelregister</span><h2>Aktiva och historiska kontomappningar</h2></div><span className="row-count">{mappings.length} regler</span></div>{mappings.length ? <div className="table-wrap"><table><thead><tr><th>Konto</th><th>Namn</th><th>Roll</th><th>Kategori</th><th>Fordon</th><th>Giltighet</th><th>Prioritet</th><th>Status</th></tr></thead><tbody>{mappings.map((mapping) => <tr className={mapping.enabled ? "" : "disabled-row"} key={mapping.id}><td><strong>{mapping.account_from === mapping.account_to ? mapping.account_from : `${mapping.account_from}–${mapping.account_to}`}</strong></td><td>{mapping.name}</td><td>{CALCULATION_ROLES[mapping.calculation_role]}</td><td>{ACCOUNT_CATEGORIES[mapping.cost_category]}</td><td>{mapping.include_in_vehicle_result ? "Ja" : "Nej"}</td><td>{mapping.valid_from} – {mapping.valid_to ?? "tills vidare"}</td><td>{mapping.priority}</td><td>{canManage ? <button className={`rule-toggle ${mapping.enabled ? "on" : ""}`} disabled={busy === mapping.id} onClick={() => toggle(mapping)}><Power size={13}/>{mapping.enabled ? "Aktiv" : "Avstängd"}</button> : mapping.enabled ? "Aktiv" : "Avstängd"}</td></tr>)}</tbody></table></div> : <p className="muted-line">Inga kontoregler är skapade ännu. Kostnadsrader hålls utanför KPI-resultatet tills de har mappats.</p>}</section>
  </div>;
}
