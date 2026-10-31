import assert from 'node:assert/strict';
import {driverPeriod} from '../src/lib/hub/driver-self.ts';
assert.deepEqual(driverPeriod(undefined,'2026-10-30'),{from:'2026-10-26',to:'2026-10-30',mode:'week'});
assert.equal(driverPeriod('week','2026-10-30').from,'2026-10-26');
assert.equal(driverPeriod('week','2026-11-01').from,'2026-10-26');
assert.equal(driverPeriod('month','2024-02-29').from,'2024-02-01');
assert.equal(driverPeriod('four-weeks','2026-01-04').from,'2025-12-08');
assert.throws(()=>driverPeriod('year','2026-10-30'));
console.log('PASS: driver period boundaries, leap date, week and invalid mode');
