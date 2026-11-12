import test from 'node:test';
import assert from 'node:assert/strict';
// @ts-expect-error Node TypeScript runner.
import {maintenanceOrders,maintenanceTime} from '../src/lib/orderportal/maintenance.ts';
// @ts-expect-error Node TypeScript runner.
import {conflicts,emptyOrder} from '../src/lib/orderportal/model.ts';
// @ts-expect-error Node TypeScript runner.
import {canPlan} from '../src/lib/orderportal/planning.ts';
const record={id:'canonical-order',version:1,updatedAt:'2026-11-12T12:00:00Z',vehicleId:'canonical-vehicle',vehicle:'LMT31J',missing:false,raw:{id:123,title:'Service',start:'2026-10-01T07:00:00Z',end:'2026-10-01T09:00:00Z'}};
test('source UTC converts to Stockholm with seasonal offsets; unzoned values are not guessed',()=>{
 assert.equal(maintenanceTime('2026-10-01T07:00:00Z'),'2026-10-01T09:00');
 assert.equal(maintenanceTime('2026-11-01T07:00:00Z'),'2026-11-01T08:00');
 assert.equal(maintenanceTime('2026-11-01T07:00:00'),'');
});
test('maintenance keeps canonical identity, is nonbillable and cannot be dragged',()=>{
 const [o]=maintenanceOrders([record]);assert.equal(o.id,'canonical-order');assert.equal(o.vehicleId,'canonical-vehicle');assert.equal(o.amount,0);assert.deepEqual(o.lines,[]);assert.equal(canPlan(o),false);
 const native={...emptyOrder(),id:'native',vehicleId:o.vehicleId,start:'2026-10-01T10:00',end:'2026-10-01T12:00'};
 assert.equal(conflicts([o,native]).has('native'),true);
 assert.equal(conflicts([{...o,status:'Utförd'},native]).size,0);
});
test('missing times and source disappearance are explicit; no guessed end or cancellation',()=>{
 const [o]=maintenanceOrders([{...record,missing:true,vehicleId:null,raw:{...record.raw,end:null}}]);
 assert.equal(o.end,'');assert.equal(o.status,'Kontrollera källa');assert.equal(o.issues.length,3);assert.equal(o.vehicleId,'');
});

test('a booking without start does not invent an interval before its end',()=>{
 const [o]=maintenanceOrders([{...record,raw:{...record.raw,start:null}}]);
 assert.equal(conflicts([o,{...emptyOrder(),id:'native',vehicleId:o.vehicleId}]).size,0);
});
