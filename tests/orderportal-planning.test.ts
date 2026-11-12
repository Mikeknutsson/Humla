import test from 'node:test';
import assert from 'node:assert/strict';
// @ts-expect-error Node runs TypeScript directly.
import {emptyOrder} from '../src/lib/orderportal/model.ts';
// @ts-expect-error Node runs TypeScript directly.
import {moveOrderDay,canPlan} from '../src/lib/orderportal/planning.ts';
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
