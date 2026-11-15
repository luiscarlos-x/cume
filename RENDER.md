# Implantar o CUME no Render

O site executa Next.js em Node. Banco PostgreSQL, autenticação e permissões continuam no Supabase existente. Não crie outro banco nem reaplique migrações no projeto que já está em uso.

## Implantação por Blueprint

1. No Render, escolha New → Blueprint e conecte `luiscarlos-x/cume`, branch `main`.
2. O arquivo `render.yaml` preenche runtime, plano free, comandos, health check e URL do Supabase.
3. Preencha `SUPABASE_ANON_KEY` com a chave pública/publicável (ou anon legada) do projeto CUME. Nunca use service_role ou chave secreta.
4. Revise e confirme a criação. Se o plano gratuito não estiver disponível na conta, escolha o plano conscientemente antes de criar o serviço.
5. Aguarde a URL real do serviço. Em Supabase → Authentication → URL Configuration, configure Site URL e os Redirect URLs exatos. Preserve retornos do endereço anterior se ainda for utilizá-lo.
6. Configure SMTP próprio no Supabase para cadastro de usuários fora da equipe do projeto.

## Configuração manual equivalente

- Web Service / Node / main.
- Build: `npm ci --include=dev && npm run build:render`
- Start: `npm run start:render`
- Health check: `/api/health`
- `NODE_VERSION=22.22.0`
- `SUPABASE_URL=https://idwddewoowdniospnjni.supabase.co`
- `SUPABASE_ANON_KEY`: chave pública no painel Render.

A porta é fornecida pelo Render através de PORT. Não é necessário inserir DATABASE_URL, senha do banco ou service_role. Não há migração automática nem dados locais persistentes.

## Verificações

`npm run build:render` compila com Next.js/webpack. `npm run start:render` inicia em 0.0.0.0. `/api/health` verifica que o serviço está respondendo; não verifica a conexão ao banco. `/api/config` fornece apenas URL e chave pública, sem cache, e rejeita chaves service_role/sb_secret.

Após a implantação, validar login e cadastro por e-mail, leitura dos dados existentes, navegação no celular e um lançamento. A demonstração está em `/?demo=1` e não grava dados reais.

A rota de configuração desta versão do GitHub usa `process.env`, própria para Node/Render. Não publicar este checkout no runtime Cloudflare sem adaptar novamente a leitura das variáveis. O site anterior não foi alterado por este commit.
