// Calendar month in Swedish local time, including January and leap-year boundaries.
export function previousInternalMonth(now = new Date()) {
 const parts = new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Stockholm', year: 'numeric', month: 'numeric' }).formatToParts(now);
 const year = Number(parts.find(p => p.type === 'year')!.value);
 const month = Number(parts.find(p => p.type === 'month')!.value);
 return { from: new Date(Date.UTC(year, month - 2, 1)).toISOString().slice(0, 10), to: new Date(Date.UTC(year, month - 1, 0)).toISOString().slice(0, 10) };
}
