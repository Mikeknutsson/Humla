import test from 'node:test';
import assert from 'node:assert/strict';
// @ts-expect-error Node runs TypeScript directly.
import {emptyOrder} from '../src/lib/orderportal/model.ts';
// @ts-expect-error Node runs TypeScript directly.
import {moveOrderDay,canPlan,copyOrderForTest,appearsOnResource,overlapsCalendarDay} from '../src/lib/orderportal/planning.ts';
test('dragging a later day of a multi-day order moves by the grabbed day, preserving duration and clocks',()=>{
 const order={...emptyOrder(),start:'2026-10-24T07:00',end:'2026-10-26T09:30'};
 const moved=moveOrderDay(order,'2026-10-25','2026-11-01');
 assert.equal(moved.start,'2026-10-31T07:00');assert.equal(moved.end,'2026-11-02T09:30');assert.equal(moved.lines,order.lines);assert.equal(order.start,'2026-10-24T07:00');
});
test('planning preserves article dates/prices and excludes imports and completed orders',()=>{
 const order=emptyOrder();assert.equal(canPlan(order),true);
 assert.equal(canPlan({...order,source:'workify'}),false);
 assert.equal(canPlan({...order,status:'Utförd'}),false);
 assert.throws(()=>moveOrderDay({...order,source:'workify'},'2026-10-01','2026-10-02'));
 assert.throws(()=>moveOrderDay(order,'2026-02-30','2026-10-02'));
});

test('dragging an import prepares a new test identity, preserves provenance and leaves the import unchanged',()=>{
 const imported={...emptyOrder(),id:'workify:123',number:'123',source:'workify' as const,status:'Fakturerad',vehicleId:'unmapped',vehicle:'Importfordon',version:0,lines:[{id:'import-line',sourceId:'source-row',fingerprint:'fingerprint',date:'2026-10-01',article:'a',label:'Material',quantity:1,unit:'ton',price:100,amount:100,comment:'',valid:true,errors:[]}]};
 let count=0;const copy=copyOrderForTest(imported,[],()=>`test-${++count}`);const moved=moveOrderDay(copy,'2026-10-01','2026-10-02');
 assert.equal(moved.source,'humla');assert.equal(moved.id,'');assert.equal(moved.number,'');assert.equal(moved.status,'Utkast');assert.equal(moved.copiedFrom,'Workify 123');assert.equal(moved.vehicleId,'');assert.equal(moved.lines[0].sourceId,undefined);assert.notEqual(moved.lines[0].id,imported.lines[0].id);assert.equal(moved.lines[0].date,'2026-10-01');assert.equal(imported.source,'workify');assert.equal(imported.lines[0].sourceId,'source-row');assert.equal(imported.start,'2026-10-01T07:00');
});

test('multi-day jobs ending at midnight do not occupy the next day',()=>{
 const order={start:'2026-10-24T07:00',end:'2026-10-26T00:00'};
 assert.equal(overlapsCalendarDay(order,'2026-10-25'),true);
 assert.equal(overlapsCalendarDay(order,'2026-10-26'),false);
 assert.equal(overlapsCalendarDay({...order,end:'2026-10-26T00:30'},'2026-10-26'),true);
 assert.equal(overlapsCalendarDay({...order,end:''},'2026-10-24'),true);
});
test('maintenance appears in the vehicle calendar without an unassigned driver card',()=>{
 assert.equal(appearsOnResource({source:'fordonskontrollen'},'vehicle'),true);
 assert.equal(appearsOnResource({source:'fordonskontrollen'},'driver'),false);
 assert.equal(appearsOnResource({source:'humla'},'driver'),true);
});
