# Integração do PR #1 — Florales

A contribuição de `icarito/florales-cobija.pdv` (head `9e362f6`) foi integrada à versão atual, preservando a autoria e o histórico dos nove commits. O PDV usa o menu compacto, cartões com fotos, carrinho recolhível, total e cobrança no rodapé, moeda da venda e troco em tempo real.

## Decisões da revisão

- A configuração continua no projeto Supabase existente (`armovjqaqmhekescgtiy`). A troca para o projeto do fork não foi aplicada: ela apontaria o sistema a outra base, sem transferir os dados atuais.
- Os controles atuais de editar/cancelar vendas e redefinição de senha foram preservados. Vendas/pedidos também ficam acessíveis no novo menu.
- Ocultar o catálogo continua disponível por dispositivo/perfil; busca, setas, Escape e Enter funcionam nesse modo. O carrinho ocupa a largura inteira no celular.
- As vendas novas usam os preços próprios de BOB ou BRL. A fila antiga mantém o caminho v4 quando itens em BOB têm recebimento em outra moeda.
- Edição, cancelamento e conta do cliente respeitam a moeda dos itens. Cada item novo registra se houve controle de estoque, evitando devolver estoque fictício após alterar a configuração de um produto.
- O fechamento guarda o detalhamento completo no servidor. Estornos não monetários ficam separados das retiradas de dinheiro no cálculo do numerário esperado.
- Renovação de sessão concorrente é compartilhada. Falhas transitórias do servidor não apagam a sessão; uma renovação que termina depois do logout não restaura o acesso.
- Cupom e lista de vendas exibem a moeda da venda; versões de HTML, recursos e cache offline foram atualizadas em conjunto.

## Banco

Aplicada `20261023024138_integrate_tablet_sales_compatibility.sql` ao projeto existente. Inclui os requisitos do PR e os ajustes acima, com wrappers públicos `SECURITY INVOKER`, verificação de associação/administrador e implementação privilegiada no schema privado. Os avisos gerais anteriores do projeto não foram alterados.

A migração não reinterpreta vendas históricas. O código genérico OTRO é criado somente quando não existe; nenhum produto existente com esse código é transformado.

## Validação

- 64 testes Node passaram; sintaxe JavaScript e preparação de `dist` verificadas.
- `tests/sale-management.sql` e `tests/tablet-integration.sql` passaram no Supabase em transações com rollback: legado, BRL nativo, troco, estoque, conta do cliente, correção, repetição de cancelamento, permissões, valor inválido e fechamento.
- Nenhuma empresa temporária de teste permaneceu na base.
- Navegador em modo demonstração: 1440×900, 1024×768, 800×1280, 390×844 e 360×640; sem overflow horizontal e com cobrança dentro da tela.
- Navegador: abertura de caixa, produto, troca BOB/BRL, carrinho recolhível, catálogo oculto, busca/Enter/Escape, cobrança e cupom com troco; zero erros de JavaScript.
- Vendas comerciais reais não foram usadas como teste. Testes transacionais no banco e demonstração no navegador foram realizados separadamente.
