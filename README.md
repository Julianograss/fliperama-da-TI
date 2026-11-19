# ERP Base

Base de um ERP empresarial: **Flutter** + **Supabase** (auth e banco) + **Vercel** (hospedagem web).

Já inclui: login, cadastro, menu lateral com módulos (Dashboard, Estoque, Setores, Compras, Vendas, Financeiro, RH), CRUD básico de Setores e Produtos, e o schema do banco com RLS.

## 1. Preparar o projeto

O zip traz só a pasta `web/`. Gere as demais plataformas (Android, iOS...) sem sobrescrever nada:

```bash
flutter create . --platforms=web,android,ios --project-name erp_base
flutter pub get
```

## 2. Supabase

1. Crie um projeto em https://supabase.com
2. Abra **SQL Editor**, cole o conteúdo de `supabase/schema.sql` e execute.
3. Em **Project Settings → API**, copie a *Project URL* e a *anon public key*.
4. Copie `env.example.json` para `env.json` e preencha (esse arquivo não vai pro Git).
5. (Opcional, para testar rápido) Em **Authentication → Providers → Email**, desative "Confirm email".

## 3. Rodar localmente (VS Code)

```bash
flutter run -d chrome --dart-define-from-file=env.json
```

Ou use a configuração **ERP (Chrome)** em Run and Debug.

## 4. GitHub

```bash
git init
git add .
git commit -m "Base do ERP"
git branch -M main
git remote add origin https://github.com/SEU_USUARIO/SEU_REPO.git
git push -u origin main
```

## 5. Deploy na Vercel

1. Em https://vercel.com, **Add New → Project** e importe o repositório.
2. Em **Environment Variables**, crie `SUPABASE_URL` e `SUPABASE_ANON_KEY`.
3. Deploy. O `vercel.json` + `vercel_build.sh` instalam o Flutter e geram o build web (o primeiro deploy demora alguns minutos).
4. No Supabase, em **Authentication → URL Configuration**, coloque a URL da Vercel em *Site URL*.

## Estrutura

```
lib/
  core/        config (env), tema e rotas (go_router)
  features/    auth, home (shell + dashboard), inventory, sectors
  shared/      widgets reutilizáveis
supabase/schema.sql   tabelas, triggers e políticas RLS
```

## Próximos passos sugeridos

- Definir o ramo da empresa e ajustar os módulos
- Movimentações de estoque (entrada/saída) usando a tabela `stock_movements`
- Permissões por papel (`profiles.role`) e por setor nas políticas RLS
- Cadastro de clientes e fornecedores
