import assert from 'node:assert/strict';
import {driverPeriod,selectDriverPeriod} from '../src/lib/hub/driver-self.ts';
assert.deepEqual(driverPeriod(undefined,'2026-10-30'),{from:'2026-10-26',to:'2026-10-30',mode:'week'});
assert.equal(driverPeriod('week','2026-10-30').from,'2026-10-26');
assert.equal(driverPeriod('week','2026-11-01').from,'2026-10-26');
assert.equal(driverPeriod('month','2024-02-29').from,'2024-02-01');
assert.equal(driverPeriod('four-weeks','2026-01-04').from,'2025-12-08');
assert.throws(()=>driverPeriod('year','2026-10-30'));
console.log('PASS: driver period boundaries, leap date, week and invalid mode');

const periods=[{from:'2026-09-30',to:'2026-10-27',mode:'four-weeks'},{from:'2026-10-21',to:'2026-10-27',mode:'week'}];
assert.equal(selectDriverPeriod(periods,undefined,'2026-11-04').to,'2026-10-27');
assert.equal(selectDriverPeriod(periods,'week','2026-11-04').from,'2026-10-21');
assert.equal(selectDriverPeriod(periods,'2026-10-21:2026-10-27','2026-11-04').from,'2026-10-21');
assert.equal(selectDriverPeriod(periods,'2026-11-01:2026-11-04','2026-11-04').to,'2026-10-27');
console.log('PASS: actual imported period selected instead of empty current week, including old links and person switches');
