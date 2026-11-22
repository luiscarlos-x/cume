import type {Data} from './finance';

// Keep the original data intact for history, editing and restoring hidden accounts.
export function dashboardData(data: Data): Data {
  const hidden = new Set(data.accounts.filter(a => a.is_hidden).map(a => a.id));
  return {
    ...data,
    accounts: data.accounts.filter(a => !hidden.has(a.id)),
    transactions: data.transactions.filter(t => !hidden.has(t.account_id)),
    settlement_entries: data.settlement_entries.filter(t => !hidden.has(t.account_id)),
    account_adjustments: data.account_adjustments.filter(t => !hidden.has(t.account_id)),
    goal_cash_entries: data.goal_cash_entries.filter(t => !hidden.has(t.account_id)),
    reconciliations: data.reconciliations.filter(t => !hidden.has(t.account_id)),
  };
}
