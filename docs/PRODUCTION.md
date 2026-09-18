# Ativação de produção com Supabase

O frontend permanece em `mode: 'demo'` até existir um projeto Supabase real. A ativação não exige — e não permite — colocar a chave `service_role` ou uma senha administrativa no navegador.

## 1. Criar e preparar o projeto

1. Crie um projeto Supabase novo para o FLORALES PDV & ERP.
2. Execute `supabase/schema.sql` no SQL Editor. Para uma instalação já existente, aplique também `supabase/migrations/20260821_auth_management.sql`.
3. Implante as Edge Functions `bootstrap-admin` e `manage-user`.
4. Configure os secrets abaixo somente no ambiente das funções:

```text
FLORALIS_SETUP_KEY=<segredo aleatório com 32 ou mais caracteres>
FLORALIS_ADMIN_EMAIL=admin@floralis.local
FLORALIS_ADMIN_PASSWORD=<senha temporária forte com 12 ou mais caracteres>
FLORALIS_BUSINESS_NAME=FLORALES Flores e Presentes
FLORALIS_LEGAL_NAME=FLORALES Flores e Presentes
ALLOWED_ORIGINS=https://floralis-pdv-erp.deltaspriggan.chatgpt.site
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY` e `SUPABASE_SERVICE_ROLE_KEY` são fornecidos automaticamente pelo ambiente das Edge Functions. Nunca grave o valor de `FLORALIS_ADMIN_PASSWORD` no Git ou em arquivos públicos.

## 2. Criar o primeiro administrador

Faça uma única chamada `POST` para `bootstrap-admin`, enviando o secret no cabeçalho `x-setup-key`. A função:

- recusa uma segunda inicialização;
- cria a empresa e suas configurações;
- cria o usuário no Supabase Auth;
- associa o usuário como administrador com todas as permissões;
- exige que a senha temporária seja trocada no primeiro acesso;
- desfaz a criação caso alguma etapa falhe.

Depois do primeiro acesso, remova `FLORALIS_ADMIN_PASSWORD` e `FLORALIS_SETUP_KEY` dos secrets ou exclua a função `bootstrap-admin`. O administrador pode alterar o próprio e-mail e a senha em **Configurações > Meu acesso**.

## 3. Ativar o frontend

Copie somente a URL e a chave pública/publishable em `config.js`:

```js
window.FLORALIS_CONFIG = {
  mode: 'supabase',
  supabaseUrl: 'https://SEU-PROJETO.supabase.co',
  supabasePublishableKey: 'SUA_CHAVE_PUBLICA'
}
```

O painel principal usa `index.html`; o terminal PDV separado usa `pdv.html`.

## 4. Funcionários e acessos

O administrador cadastra funcionários dentro do ERP informando e-mail, senha temporária, função e permissões. A Edge Function `manage-user` valida o token de quem fez a solicitação e só permite a operação para administradores ativos da mesma empresa. Senhas são tratadas exclusivamente pelo Supabase Auth e nunca são gravadas nas tabelas do ERP.

Ao criar um funcionário, o sistema exige a troca da senha temporária no primeiro login. Ao editar, deixar o campo de senha vazio conserva a senha atual. O último administrador ativo não pode ser rebaixado.

## 5. Segurança e operação

- Row Level Security isola os dados por empresa (`business_id`).
- Vendas são atômicas: validam e baixam estoque, registram itens, caixa, conta do cliente e métricas na mesma transação.
- Pedidos e orçamentos não baixam estoque nem movimentam caixa.
- Auditoria registra acessos e ações; a consulta completa é restrita a administradores.
- A chave administrativa fica apenas nos secrets das Edge Functions.
- Antes do uso real, configure domínio, recuperação de senha, SMTP, MFA para administradores, backups e retenção.
- Homologue regras fiscais, impressão e emissão documental aplicáveis à operação na Bolívia.
