import type {Data,Row} from './finance';
export const monthEnd=(m:string)=>new Date(Date.UTC(+m.slice(0,4),+m.slice(5,7),0)).toISOString().slice(0,10);
export const addDays=(d:string,n:number)=>new Date(Date.parse(d+'T12:00:00Z')+n*86400000).toISOString().slice(0,10);
export const daysBetween=(a:string,b:string)=>Math.round((Date.parse(b+'T12:00:00Z')-Date.parse(a+'T12:00:00Z'))/86400000);
export const inputMoney=(n:number)=>(Number(n||0)/100).toFixed(2).replace('.',',');
export function monthDate(date:string,offset:number){const d=new Date(date+'T12:00:00Z'),m=new Date(Date.UTC(d.getUTCFullYear(),d.getUTCMonth()+offset,1)).toISOString().slice(0,7);return m+'-'+String(Math.min(d.getUTCDate(),+monthEnd(m).slice(-2))).padStart(2,'0')}
export function allocate(total:number,weights:number[]){
 if(!Number.isSafeInteger(total)||total<=0||!weights.length||weights.some(w=>!Number.isSafeInteger(w)||w<0)||weights.reduce((a,b)=>a+b,0)<=0)throw new Error('Rateio inválido.');
 const sum=BigInt(weights.reduce((a,b)=>a+b,0)),raw=weights.map(w=>BigInt(total)*BigInt(w)),base=raw.map(n=>Number(n/sum));
 const order=raw.map((n,i)=>({i,r:n%sum})).sort((a,b)=>a.r===b.r?a.i-b.i:a.r>b.r?-1:1);
 for(let n=total-base.reduce((a,b)=>a+b,0),i=0;n>0;n--,i++)base[order[i].i]++;
 return base;
}
export function accountBalance(a:Row,d:Data,until='9999-12-31'){
 if(a.opening_on>until)return 0;
 return (d.goal_cash_entries||[]).filter(t=>t.account_id===a.id&&t.active&&t.occurred_on<=until).reduce((s,t)=>s+Number(t.amount_cents),0)+Number(a.opening_balance_cents)+d.transactions.filter(t=>t.account_id===a.id&&t.status==='confirmed'&&t.occurred_on>=a.opening_on&&t.occurred_on<=until).reduce((s,t)=>s+(t.kind==='income'?1:-1)*Number(t.amount_cents),0)+d.settlement_entries.filter(t=>t.account_id===a.id&&t.active&&t.occurred_on<=until).reduce((s,t)=>s+(t.direction==='in'?1:-1)*Number(t.amount_cents),0)+d.account_adjustments.filter(t=>t.account_id===a.id&&t.occurred_on<=until).reduce((s,t)=>s+Number(t.amount_cents),0);
}
export function debts(d:Data,house?:string):Row[]{return d.transaction_splits.flatMap(s=>{
 const tx=d.transactions.find(t=>t.id===s.transaction_id&&t.status==='confirmed'&&(!house||t.household_id===house));if(!tx||s.user_id===tx.user_id)return [];
 const payments=d.settlements.filter(x=>x.transaction_id===tx.id&&x.debtor_id===s.user_id&&x.status!=='cancelled'),confirmed=payments.filter(x=>x.status==='confirmed').reduce((v,x)=>v+Number(x.amount_cents),0),pending=payments.filter(x=>x.status==='pending').reduce((v,x)=>v+Number(x.amount_cents),0);
 return [{...s,tx,creditor_id:tx.user_id,confirmed,pending,open:Math.max(0,Number(s.share_cents)-confirmed-pending)}];
})}
export function safeSpending(d:Data,uid:string,now:string){
 const saved=d.spending_plans.find(p=>p.owner_user_id===uid),expired=!!saved&&saved.horizon_on<now,plan=saved||{horizon_on:monthEnd(now.slice(0,7)),essential_remaining_cents:0,buffer_cents:0,goal_cents:0},until=expired?now:plan.horizon_on;
 const available=d.accounts.filter(a=>a.owner_user_id===uid&&!a.household_id).reduce((s,a)=>s+accountBalance(a,d,now),0),pending=d.transactions.filter(t=>t.user_id===uid&&t.status==='planned'&&t.kind==='expense'&&t.occurred_on<=until&&!d.accounts.find(a=>a.id===t.account_id)?.household_id).reduce((s,t)=>s+Number(t.amount_cents),0),owing=debts(d).filter(s=>s.user_id===uid).reduce((s,x)=>s+x.open,0);
 const extra=Number(plan.essential_remaining_cents),buffer=Number(plan.buffer_cents),goal=Number(plan.goal_cents),free=available-pending-owing-extra-buffer-goal,days=Math.max(1,daysBetween(now,until)+1);
 return {configured:!!saved,expired,plan,until,available,pending,owing,extra,buffer,goal,free,days,daily:expired?0:Math.floor(Math.max(0,free)/days)};
}
export function budgetState(b:Row,d:Data,now:string){
 const start=b.month,end=monthEnd(start.slice(0,7)),days=daysBetween(start,end)+1,tx=d.transactions.filter(t=>t.category_id===b.category_id&&t.kind==='expense'&&t.status==='confirmed'&&t.occurred_on>=start&&t.occurred_on<=end&&(b.household_id?t.scope==='household'&&t.household_id===b.household_id:t.user_id===b.owner_user_id)),spent=tx.reduce((s,t)=>s+Number(t.amount_cents),0);
 let first:string|null=null,over=0,acc=0;for(let day=start;day<=end&&day<=now;day=addDays(day,1)){acc+=tx.filter(t=>t.occurred_on===day).reduce((s,t)=>s+Number(t.amount_cents),0);const ceiling=b.discretionary?Math.floor(Number(b.limit_cents)*(daysBetween(start,day)+1)/days):Number(b.limit_cents);if(!first&&acc>ceiling){first=day;over=acc-ceiling}}
 return {spent,remaining:Number(b.limit_cents)-spent,first,over};
}
export function dailySeries(d:Data,uid:string,house:string,scope:string,month:string,now:string){
 const accounts=d.accounts.filter(a=>scope==='household'?a.household_id===house:a.owner_user_id===uid&&!a.household_id),ids=new Set(accounts.map(a=>a.id)),txs=d.transactions.filter(t=>scope==='household'?t.household_id===house&&t.scope==='household':t.user_id===uid),base=accounts.reduce((s,a)=>s+accountBalance(a,d,now),0),out:Row[]=[];
 for(let date=month+'-01';date<=monthEnd(month);date=addDays(date,1)){const tx=txs.filter(t=>t.occurred_on===date),sum=(kind:string,status:string)=>tx.filter(t=>t.kind===kind&&t.status===status).reduce((s,t)=>s+Number(t.amount_cents),0);out.push({date,day:date.slice(-2),income:sum('income','confirmed'),expense:sum('expense','confirmed'),plannedIncome:sum('income','planned'),plannedExpense:sum('expense','planned'),balance:date<=now&&accounts.every(a=>a.opening_on<=date)?accounts.reduce((s,a)=>s+accountBalance(a,d,date),0):null,projected:date<now?null:base+(date===now?0:d.transactions.filter(t=>ids.has(t.account_id)&&t.status==='planned'&&t.occurred_on<=date).reduce((s,t)=>s+(t.kind==='income'?1:-1)*Number(t.amount_cents),0))})}
 return out;
}
export function simulate(safe:ReturnType<typeof safeSpending>,price:number,installments:number,recurring:number,first:string,now:string){
 if(price<=0||!Number.isSafeInteger(price)||!Number.isInteger(installments)||installments<1||installments>60||recurring<0||!Number.isSafeInteger(recurring)||!/^\d{4}-\d{2}-\d{2}$/.test(first)||first<now)throw new Error('Confira preço, parcelas e data da compra.');
 const schedule=allocate(price,Array(installments).fill(1)).map((amount,i)=>({date:monthDate(first,i),amount})),cycleInstallments=schedule.filter(x=>x.date<=safe.until).reduce((s,x)=>s+x.amount,0);let recurringCount=0;
 for(let i=0;i<14&&monthDate(first,i)<=safe.until;i++)recurringCount++;
 const inCycle=cycleInstallments+recurringCount*recurring,free=safe.free-inCycle;
 return {schedule,inCycle,free,first,daily:safe.expired?0:Math.floor(Math.max(0,free)/safe.days),future:price-cycleInstallments,total:price,recurring,delay:safe.goal>0?Math.ceil(price/safe.goal):null};
}
