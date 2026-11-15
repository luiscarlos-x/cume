# Montanha — entrega funcional

- Metas por casa com nome, valor-alvo, prazo opcional e identificação da caixinha. Criador edita a meta; participantes registram apenas movimentações e compromissos próprios.
- Reserva segregada no livro do aplicativo. Cada aporte debita a conta pessoal de origem; resgates creditam a conta pessoal de destino. Não geram receita/despesa. Não cadastrar o mesmo dinheiro como saldo inicial em outra conta.
- Saldo inicial da meta começa em zero: dinheiro já reservado deve ser transferido da conta onde está contabilizado. Contas bancárias não são movimentadas pelo aplicativo; usuário confirma movimentos já realizados.
- Aportes e resgates atômicos, idempotentes por identificador, com centavos inteiros e motivo obrigatório. Resgates limitados à contribuição líquida própria, inclusive no histórico retroativo. Desfazer preserva o registro.
- Progresso real e silhueta projetada separados; projeção usa compromissos voluntários de membros ativos, sem rendimentos. Nenhum dado de renda ou despesa privada é usado na meta.
- Conferência manual compara extrato e registro sem ajuste implícito. Corrigir divergências por movimentos documentados, nunca por animações.
- Compromissos da meta não alteram automaticamente a reserva planejada em Planejamento: aquele campo continua sendo a decisão pessoal de quanto reservar no ciclo.
- UI inclui participantes, cumprimento mensal, marcos de contribuição/percentual, histórico e pausa de animações. Indicadores comportamentais de 30 dias conciliados e orçamento sem desvios não são certificados pela Montanha.

Validação: TypeScript, build e cenário de integração PostgreSQL local para privacidade, saldo, resgate, escrita direta negada e idempotência. RLS verificado no banco remoto. Advisor sem alertas novos de tabelas/funções; proteção de senhas vazadas do Auth permanece desativada (configuração preexistente).
