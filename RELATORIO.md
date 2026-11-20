# Relatório: sebo na AWS

Segundo Trabalho de Distribuição e Concorrência (2026/2)

Grupo: Arthur Hammond Aragão Poggy e Jayme Augusto Avelino de Paiva

Conta da AWS Academy com a implementação: 3336-9331-7353 (usuário `Arthur_Hammond_Arag__o_Poggy`, região us-east-1)

## 1. Descrição

A aplicação atende um sebo em que o cliente escolhe um livro e informa o e-mail. Se houver exemplar ele recebe um e-mail pedindo que compareça à livraria para efetivar a compra, caso não haja, ele entra em uma lista de espera e é avisado por e-mail quando o livro chegar. 
O colaborador registra a entrada e a saída de exemplares com o estoque e a lista de espera no DynamoDB.

Cada função Lambda tem uma responsabilidade só e são expostas por Function URL. 
Os e-mails saiem pelo SNS e a interface é um par de páginas HTML locais e chamam as funções pela web.

## 2. Arquitetura

Serviços usados: AWS Lambda (5 funções), DynamoDB (2 tabelas), SNS (e-mail) e Function URLs (HTTPS, em 4 das funções). Interfaces em HTML e JavaScript.

Só a `Notificar` não tem Function URL: ela é chamada apenas pela `Solicitar` e pela `Cadastrar`.

### 2.1 Responsabilidades das funções

Solicitar -> Recebe o pedido de um livro (código e e-mail do cliente) e consulta o estoque em Livros. Se há exemplar, pede à Notificar o aviso para o cliente comparecer à livraria, se não há, grava o cliente em ListaEspera e pede o aviso de que ele será chamado quando o livro chegar. Responde 400 para dados inválidos, 404 para livro inexistente e 502 se o aviso não puder ser enviado.

Cadastrar -> Registra a entrada ou a saída de exemplares. Soma a quantidade ao estoque e cria o livro se ele ainda não existir. Quando chega exemplar, avisa pela Notificar cada cliente que esperava aquele livro e o tira da ListaEspera. Uma saída maior que o estoque é recusada com 409, e dados inválidos recebem 400.

Notificar -> Publica a mensagem no tópico SNS, que entrega o e-mail. Envia junto o endereço do destinatário como atributo da mensagem, para que cada assinatura receba só o que é dela. Só a Solicitar e a Cadastrar chamam essa função.

Listar -> Devolve todos os livros com autor e quantidade, em ordem de título. A tela do cliente usa para montar a lista de livros, e a do colaborador para mostrar o estoque.

Inscrever -> Recebe um e-mail, confere se é válido e cria no tópico uma assinatura que só entrega as mensagens dirigidas a esse endereço. O SNS manda ao cliente um e-mail de confirmação. Responde 400 para e-mail inválido e 502 se a assinatura não puder ser criada.

### 2.2 Dados

`Livros` tem `id` (chave), `titulo`, `autor` e `quantidade`. 
`ListaEspera` tem `livro_id` (partição), `email` (classificação) e `data`.

A chave composta de `ListaEspera` impede duplicar o mesmo cliente para o mesmo livro. A saída de estoque usa uma condição no próprio `update_item` (`quantidade >= :min`), então o estoque não fica negativo nem com chamadas simultâneas.

### 2.3 Como o e-mail chega ao cliente

A `Notificar` publica a mensagem no tópico `LivrariaAvisos` com um atributo `email`, que é o endereço do destinatário. 
O SNS entrega uma cópia a cada assinatura confirmada. 
As assinaturas criadas pela `Inscrever` têm uma política de filtro com o endereço do inscrito, então cada cliente recebe só as mensagens dirigidas a ele.

### 2.4 Falha no envio do aviso

Quando a `Solicitar` ou a `Cadastrar` chama a `Notificar`, o `invoke` não gera erro se a função chamada quebrar. A falha aparece no campo `FunctionError` da resposta, e as duas funções conferem esse campo. A `Solicitar` responde 502, e o pedido na lista de espera continua registrado. A `Cadastrar` mantém na `ListaEspera` os clientes que não puderam ser avisados e devolve `status: parcial`, com os endereços em `falhas`. Eles são avisados na próxima chegada daquele livro.

## 3. Instalação

O ambiente foi montado à mão pelo console na primeira vez, porém ao entrar no lab depois de um tempo todas as funções e tabelas tinha desaparecido, para evitar retrabalho se isso acontecesse denovo optamos por criar um `recriar_sebo.sh` que recria todas funções e tabelas no banco.

### 3.1 Requisitos

Conta do Learner Lab com o lab ligado, região us-east-1, o CloudShell do console e um e-mail para receber os avisos.

### 3.2 Passos

1. Clicar em Start Lab, esperar a bolinha ficar verde e abrir o console pelo link AWS.
2. Abrir o CloudShell e enviar o arquivo `recriar_sebo.sh` (Ações, Fazer upload do arquivo) (esse passo e o próximo podem ser pulados caso as funções e tabelas já estejam no lab e não tenham sido apagadas como aconteceu anteriormente).
3. Rodar, com o e-mail que vai receber os avisos:
   ```
   bash recriar_sebo.sh seu@email.com
   ```
4. Abrir o e-mail e confirmar a inscrição.
5. Copiar as quatro URLs que o script imprime no final para `interface/config.js`: `URL_SOLICITAR`, `URL_CADASTRAR`, `URL_LISTAR` e `URL_INSCREVER`. (isso só precisa ser feito caso o script tenha que ter sido rodado pelo lab ter apagado as funções/tabelas, caso contrário não será necessário, já que o config.js já estará com as URLs corretas)
6. Abrir `interface/cliente.html` para ter acesso a interface.

### 3.3 Código-fonte

O código-fonte das funções está em `interface/lambda/` (apenas uma cópia para consulta/vista, ele não é usado em nenhum momento pelo código, as funções usadas são as funções lambda na AWS).

## 4. Operação

Considerando o lab ligado e as URLs corretas no `config.js`:

Para acessar a interface do cliente basta abrir `cliente.html`. 
Em "Receber avisos por e-mail", o cliente informa o endereço e clica em Cadastrar e-mail, depois abre o link de confirmação que chega por e-mail. 
Em "Pedir um livro", escolhe o livro na lista, informa o e-mail e clica em Solicitar. A tela mostra se o livro está disponível ou se o cliente entrou na lista de espera.

Para acessar a interface do colaborador basta abrir `colaborador.html`, ou trocar pra ela na interface do cliente. Nela é possível atualizar o estoque ao informar o código, título, autor e quantidade e clicar em Registrar. Quantidade positiva soma ao estoque e avisa quem estava na lista de espera daquele livro e quantidade negativa registra saída e é recusada se não houver exemplares suficientes. 
A tabela Estoque mostra os livros e é atualizada a cada registro.

## 5. O que funcionou

As funções lambda e tabelas funcionaram conforme o esperado, o envio de emails pelo serviço SNS também e a interface possibilita testar tudo, além funcionar como o esperado também. Ou seja, é possível cadastrar um email de forma que ele recebe a notificação e pode confirmar a inscrição, os emails de falta de estoque ou aviso para comparecer a loja funcionam também e só são enviados após o email ter confirmado a inscrição e as atualizações das tabelas pela interface também funcionam de acordo.

## 6. Problemas encontrados

Criamos as funções lambda e as tabelas no dia 14/11, ao voltar a acessar o lab no dia 20/11 elas tinham desaparecido. Para evitar problemas caso isso aconteça novamente criamos o script recriar_sebo.sh que foi citado nesse relatório para conseguir recriar tudo de forma rápida caso isso venha a acontecer novamente.

## 7. Limitações

- Como não estava no escopo do trabalho não usamos nenhuma proteção de autentificação para chamar as funções e/ou login para acessar a área de colaborador na interface.
- Todos os clientes da lista de espera não são avisados caso o livro volte a ficar fora de estoque novamente depois.
- Os recursos do Learner Lab podem desaparecer, como aconteceu entre 14 e 20/11. O `recriar_sebo.sh` refaz o ambiente, mas as URLs mudam, fazendo com que seja necessário atualizar elas no configs.js
