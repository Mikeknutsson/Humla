import test from 'node:test';
import assert from 'node:assert/strict';
// @ts-expect-error Node runs TypeScript directly.
import {emptyCustomerProfile,parseCustomerProfile} from '../src/lib/orderportal/customer-card.ts';

test('customer profile preserves document choices and normalizes contact and marking fields',()=>{
 const profile=emptyCustomerProfile();
 profile.contacts=[{name:' Testkontakt ',email:'test@example.com',phone:' 0100000000 '}];
 profile.markings=[{number:' A-17 ',description:' Arbetsplats '}];
 profile.documents.signature=true;
 const parsed=parseCustomerProfile(profile);
 assert.deepEqual(parsed.contacts,[{name:'Testkontakt',email:'test@example.com',phone:'0100000000'}]);
 assert.deepEqual(parsed.markings,[{number:'A-17',description:'Arbetsplats'}]);
 assert.equal(parsed.documents.signature,true);
});

test('customer profile rejects duplicate markings and invalid recipients',()=>{
 const profile=emptyCustomerProfile();
 profile.markings=[{number:'A-17',description:''},{number:' a-17 ',description:''}];
 assert.throws(()=>parseCustomerProfile(profile),/eget nummer/);
 profile.markings=[];
 profile.documents.recipient='felaktig adress';
 assert.throws(()=>parseCustomerProfile(profile),/giltig e-postadress/);
});
