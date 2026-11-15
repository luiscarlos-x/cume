# CUME

Aplicativo de finanças pessoais e familiares em português. React e TypeScript com Vinext, Cloudflare Workers e Supabase.

## Recursos existentes

- Contas, receitas/despesas, categorias e visões pessoal/casa.
- Convites, permissões, auditoria e Row Level Security.
- Orçamento, calendário, projeções, rateios/reembolsos e reconciliação.
- Montanha: metas, aportes, resgates e compromissos voluntários.

## Melhorias para celular

- Navegação inferior: Início, Extrato, Registrar, Montanha e Menu.
- Registro acessível com um toque; seleção automática da conta quando existe somente uma opção válida.
- Menu lateral com fechamento, Escape, foco contido e bloqueio da rolagem de fundo.
- Formulários em uma coluna, teclado decimal para valores e campos de pelo menos 16px.
- Áreas de toque maiores, ações de salvar acessíveis no formulário e respeito à área segura do celular.
- Melhor adaptação de filtros, metas e painéis em telas pequenas; tabelas largas rolam dentro do painel.

Somente melhorias de uso no celular foram acrescentadas à Etapa 4. Cartões, importação/exportação, backup e integração AÇAIANO não fazem parte desta alteração.

## Desenvolvimento

Requer Node.js >=22.13.0.

```sh
npm ci
npm run dev
```

Acesse `/?demo=1` para usar dados fictícios em memória, sem gravar no banco.

Para dados reais, configure `SUPABASE_URL` e `SUPABASE_ANON_KEY` em `.dev.vars` local ou nas variáveis do runtime Cloudflare. Nunca use a chave service role no cliente. O arquivo de variáveis não deve ser versionado. Aplique as migrações de `supabase/migrations` em ordem em um banco novo.

```sh
npm run typecheck
npm test
npm run build
```

O projeto contém configuração para Sites/Cloudflare. Enviar código ao GitHub não publica automaticamente uma nova versão do site e não configura variáveis de ambiente, autenticação ou SMTP. Configurar URLs de autenticação e e-mails no Supabase para o domínio de implantação.

## Validação desta alteração

TypeScript e compilação de produção. A experiência ainda deve ser conferida em aparelhos reais, especialmente com teclado aberto e diferentes tamanhos de tela.
