import test from 'node:test';
import assert from 'node:assert/strict';
import {dashboardData} from '../lib/visibility.ts';
import {emptyData,totals} from '../lib/finance.ts';
import {accountBalance} from '../lib/intelligence.ts';

test('hidden accounts exclude balances and movements without deleting history; restore reverses it',()=>{
 const data=emptyData();
 data.accounts=[{id:'visible',opening_on:'2020-01-01',opening_balance_cents:10000},{id:'hidden',is_hidden:true,opening_on:'2020-01-01',opening_balance_cents:50000}];
 data.transactions=[{id:'v',account_id:'visible',kind:'expense',status:'confirmed',amount_cents:1000,occurred_on:'2020-02-01'},{id:'h',account_id:'hidden',kind:'income',status:'confirmed',amount_cents:7000,occurred_on:'2020-02-01'}];
 data.goal_cash_entries=[{account_id:'hidden',amount_cents:-300,active:true,occurred_on:'2020-02-01'}];
 const visible=dashboardData(data);
 assert.equal(visible.accounts.length,1);
 assert.equal(totals(visible.transactions).income,0);
 assert.equal(totals(visible.transactions).expense,1000);
 assert.equal(accountBalance(visible.accounts[0],visible),9000);
 assert.equal(visible.goal_cash_entries.length,0);
 assert.equal(data.transactions.length,2);
 assert.equal(data.accounts.length,2);
 data.accounts[1].is_hidden=false;
 assert.equal(dashboardData(data).accounts.length,2);
 assert.equal(totals(dashboardData(data).transactions).income,7000);
});
