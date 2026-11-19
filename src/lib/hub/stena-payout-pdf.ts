/** Require a single date explicitly marked as the payout date. */
export function stenaPdfPayoutDate(text: string) {
 const matches = text.matchAll(/\butbetalnings[ \t]*datum[\s:]*((?:20\d{2}[-/.]\d{1,2}[-/.]\d{1,2})|(?:\d{1,2}[-/.]\d{1,2}[-/.]20\d{2}))(?!\d)/giu);
 const dates = new Set<string>();
 for (const [,value] of matches) {
  const parts = value.split(/[-/.]/);
  const [year,month,day] = parts[0].length === 4 ? parts : parts.reverse();
  const iso = year+'-'+month.padStart(2,'0')+'-'+day.padStart(2,'0');
  const parsed = new Date(iso+'T00:00:00Z');
  if (!Number.isFinite(parsed.valueOf()) || parsed.toISOString().slice(0,10)!==iso) return null;
  dates.add(iso);
 }
 return dates.size===1 ? [...dates][0] : null;
}
