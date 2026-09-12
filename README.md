# FLORALIS PDV & ERP

Sistema unificado de vendas e gestão para floriculturas, lojas de buquês e presentes. A mesma base funciona na web, como PWA instalável, aplicativo Windows e aplicativo Android.

O sistema aceita bolivianos (`BOB` / `Bs`), reais (`BRL` / `R$`) e dólares (`USD` / `$`). O operador troca a moeda diretamente no cabeçalho do PDV; as cotações são configuradas pelo administrador e cada venda preserva a moeda e a taxa utilizadas.

## Funcionalidades disponíveis

- histórico de vendas como tela inicial, com pedidos e orçamentos;
- catálogo preparado para flores, buquês, arranjos, presentes e artigos complementares;
- troca de moeda no PDV entre BOB, BRL e USD, com conversão instantânea e câmbio configurável;
- login separado para administrador e funcionário, permissões e sessão persistente;
- PDV em tela cheia com pesquisa, leitura por código, carrinho, preço varejista/atacadista, abertura dedicada por `F3` e orçamento por `F7`;
- atalhos grandes e clicáveis, com alternativas próprias para notebook (`Alt+B` para buscar, `Alt+C` para cliente e `Ctrl+Enter` para finalizar), sem depender da tecla `Fn`;
- terminal independente em `pdv.html`, responsivo para celular, tablet e computador;
- editor visual do PDV com controles arrastáveis, posição lateral/inferior e densidade configurável;
- pagamentos por dinheiro, PIX, QR, transferência e conta do cliente, com escolha do cliente dentro do próprio pagamento;
- cadastro e controle de produtos, estoque mínimo, custo e dois preços de venda;
- cadastro de clientes com foto, classificação, data de nascimento e conta corrente de crédito/débito;
- lista de clientes com nome, débito/crédito, código, observações e nascimento visíveis já na busca;
- menu de contexto (botão direito ou botão ⋮ na linha) para pagar a dívida, imprimir demonstrativo de dívida, ver o extrato da conta, adicionar ou corrigir crédito e editar o cliente;
- cobrança de crediário em quatro passos — conta e movimentações, valor total ou parcial, forma de pagamento e confirmação — lançando o crédito no cliente e a entrada no caixa;
- venda em conta lançada automaticamente no banco e exibida no extrato do cliente selecionado;
- cadastro de funcionários com foto e métricas individuais de vendas, faturamento, ticket médio e metas;
- fluxo financeiro com entradas, saídas, saldo e fechamento de caixa;
- central de relatórios simplificada, com resumo rápido, rentabilidade, caixa, meios de pagamento, vendedor, produto, estoque e fechamentos;
- relatórios imprimíveis em padrão oficial tabular, com fundo branco, cabeçalhos cinza, bordas pretas e modelos de resumo de caixa, recibo A4 e factura comercial de Zona Franca;
- personalização whitelabel de nome, razão social, NIT e cidade;
- modo claro, escuro ou automático, cinco paletas e escala proporcional Pequena/Média/Grande (Média preserva o visual original);
- tipografia operacional grande em Arial, caixa alta e números tabulares alinhados no ERP, PDV, recibos e relatórios;
- escala do documento em cinco níveis (85% a 155%) no editor de documentos, aumentando texto e altura das linhas também nos modelos oficiais A4;
- ao concluir uma venda real, o operador escolhe e visualiza um dos dois recibos oficiais A4 tabulares; o modelo padrão é configurável e o cupom térmico fica restrito a simulações;
- importação universal de produtos e clientes com prévia, mapeamento de colunas, modelos CSV e suporte a CSV, TSV, XLS e XLSX;
- logs de auditoria com usuário, horário, módulo, terminal/dispositivo e console de eventos somente leitura;
- exportação CSV de produtos, clientes e funcionários;
- backup e restauração completa em JSON;
- layout compacto inspirado no fluxo operacional do NEX Web e responsivo para computador, tablet e celular;
- navegação SPA sem recarregar a página ou voltar para o início durante cadastros;
- persistência local para que a demonstração continue funcionando após atualizar a página;
- demonstração sem baixa de estoque por padrão, com simulação opcional nas configurações;
- PWA instalável com shell offline;
- integração Supabase preparada, com PostgreSQL, RLS multiempresa e venda transacional com baixa obrigatória e atômica de estoque.

## Acessos da demonstração

| Perfil | E-mail | Senha |
|---|---|---|
| Administrador | `admin@example.invalid` | `admin123` |
| Funcionário | `employee@example.invalid` | `func123` |

O modo demonstração é definido em `config.js`. Não use essas credenciais como usuários reais.

## Executar localmente

Não há dependências ou processo de build. Abra `index.html` diretamente ou use um servidor estático:

```bash
python3 -m http.server 4173
```

Depois acesse:

- painel ERP: `http://localhost:4173/index.html`;
- terminal PDV separado: `http://localhost:4173/pdv.html`.

## Aplicativo único para Windows e Android

O aplicativo nativo abre o ERP em uma janela própria. O botão de nova venda abre o PDV dentro do mesmo aplicativo, e o botão **VOLTAR AO ERP** retorna ao painel sem perder a sessão. A versão Android usa exatamente o mesmo fluxo e o mesmo banco Supabase.

```bash
npm ci
npm run desktop:start
```

Os instaladores são gerados automaticamente ao atualizar a branch `main`. Também é possível abrir **Actions → Aplicativos Windows e Android → Run workflow** para gerar uma nova cópia manualmente. Ao concluir, a execução disponibiliza:

- `FLORALIS-Windows`: instalador `.exe` e executável portátil `.exe`;
- `FLORALIS-Android`: APK instalável para Android.

O PWA e o terminal separado continuam disponíveis como alternativas. Nenhuma chave `service_role` é empacotada; o aplicativo usa somente a chave pública do frontend e as políticas RLS do Supabase.

## Publicação

O projeto é estático e funciona diretamente no GitHub Pages ou na Vercel.

### GitHub Pages

O workflow `.github/workflows/pages.yml` publica automaticamente o conteúdo de `dist`.
Em **Settings → Pages**, selecione **GitHub Actions** em **Source**. Depois disso, cada atualização da branch `main` gera uma nova publicação.

Se o repositório estiver privado, a disponibilidade do Pages depende do plano da conta. Para publicação gratuita e pública, altere a visibilidade do repositório para **Public** antes de ativar o Pages.

### Vercel

Importe o repositório e mantenha as configurações padrão. O arquivo `vercel.json` já está incluído.

## Integração Supabase opcional

O sistema continua operacional sem um projeto Supabase. Quando houver um projeto disponível, siga [docs/PRODUCTION.md](docs/PRODUCTION.md). A preparação inclui:

- `backend.js`: adaptador entre modo local e Supabase;
- `supabase/schema.sql`: tabelas, índices, RLS, permissões e RPCs atômicas;
- `supabase/bootstrap.sql.example`: criação segura da primeira empresa/administrador;
- `supabase/functions/invite-user`: base para convite de funcionários sem expor `service_role`.

O resumo de caixa e o recibo usam os dados já registrados no ERP e podem ser impressos ou salvos em PDF. A factura de Zona Franca é um modelo comercial: código de autorização e QR fiscal só devem ser emitidos por uma integração homologada com o SIN.

Pendências antes de uma operação comercial real: homologar a emissão fiscal com o SIN na Bolívia, cancelamentos/devoluções, fila de vendas offline e backups monitorados.

## Aviso

Os dados incluídos são fictícios e existem apenas para demonstração da interface e dos fluxos.
