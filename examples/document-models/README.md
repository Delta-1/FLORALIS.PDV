# Exemplos de modelos de documentos

Estes arquivos servem como referência editável para os modelos do centro **Documentos** do FLORALES PDV & ERP. Eles usam o mesmo formato exportado pelo editor visual do sistema.

## Exemplos incluídos

- `presupuesto-a4.json`: orçamento/cotação em A4 vertical.
- `comprobante-termico-80mm.json`: comprovante de venda para impressora térmica de 80 mm.
- `estoque-a4-horizontal.json`: relatório de posição atual do estoque em A4 horizontal.

## Propriedades editáveis

- `title`: nome exibido no documento.
- `format`: `a4`, `landscape`, `thermal80`, `thermal58` ou `label`.
- `style`: `modern`, `classic`, `compact` ou `minimal`.
- `accent`: cor principal em hexadecimal.
- `fontSize`: `small`, `medium` ou `large`.
- `showLogo`, `showBusiness`, `showPeriod` e `showSignature`: elementos opcionais.
- `footer`: texto do rodapé.
- `fields`: campos e colunas, na ordem em que devem aparecer.

Os modelos visuais são próprios do FLORALES. Eles podem ser alterados no editor do sistema ou diretamente nestes JSONs para criar novas variações.
