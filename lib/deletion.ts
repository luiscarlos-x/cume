import type {Data, Row} from './finance';

export type DeletableTable = 'transactions' | 'categories';

export function canDeleteRecord(table: DeletableTable, record: Row, uid: string, data: Data) {
  const author = table === 'transactions' ? record.user_id : record.owner_user_id;
  return author === uid && (!record.household_id || data.household_members.some(member => member.household_id === record.household_id && member.user_id === uid));
}

export function deletionBlock(table: DeletableTable, record: Row, data: Data): string {
  if (table === 'categories') {
    if (data.transactions.some(item => item.category_id === record.id)) return 'Esta categoria está em uso. Altere a categoria dos lançamentos vinculados antes de apagá-la.';
    if (data.budgets.some(item => item.category_id === record.id)) return 'Esta categoria tem um orçamento. Remova o orçamento em Planejamento antes de apagá-la.';
  } else {
    if (data.settlements.some(item => item.transaction_id === record.id)) return 'Este lançamento tem um histórico de acertos e não pode ser apagado.';
    if (data.transaction_splits.some(item => item.transaction_id === record.id)) return 'Remova o rateio em Rateios e acertos antes de apagar este lançamento.';
  }
  return '';
}

export function deletionError(table: DeletableTable, error: {code?: string; message: string}) {
  if (error.code === '23503') return table === 'categories'
    ? 'Esta categoria está vinculada a lançamentos ou orçamentos. Altere esses vínculos antes de apagá-la.'
    : 'Este lançamento está vinculado a um rateio ou acerto. Revise os vínculos em Rateios e acertos.';
  if (error.code === '42501') return 'Você não tem permissão para apagar este registro.';
  return error.message;
}
