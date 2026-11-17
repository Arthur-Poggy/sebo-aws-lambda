# Sebo na AWS: instalação e operação

Região: **us-east-1** (AWS Academy Learner Lab). Código das funções em `interface/lambda/`.

## 1. Instalação

### 1.1 DynamoDB
| Tabela | Chave de partição | Chave de classificação |
|---|---|---|
| `Livros` | `id` (String) | n/a |
| `ListaEspera` | `livro_id` (String) | `email` (String) |

Cadastre livros de teste em `Livros` (por exemplo `L001` com quantidade 1 e `L002` com quantidade 0), com os atributos `titulo`, `autor` e `quantidade` (Number).

### 1.2 SNS
1. Crie o tópico **Padrão** `LivrariaAvisos`.
2. Crie uma assinatura de protocolo E-mail com o endereço de teste.
3. Abra o e-mail "AWS Notification - Subscription Confirmation" (veja o spam) e clique em *Confirm subscription*. O status deve ficar **Confirmado**.
4. Copie o ARN do tópico.

Para inscrever outro e-mail depois: Tópicos → LivrariaAvisos → Assinaturas → Criar assinatura, e confirme pelo link recebido. Não é preciso mexer nas Lambdas.

### 1.3 Lambdas
Todas em Python, com a função de execução existente **LabRole**.

| Função | Arquivo | Configuração |
|---|---|---|
| `Notificar` | `notificar.py` | Variável de ambiente `TOPIC_ARN` = ARN completo, sem espaços nem aspas |
| `Solicitar` | `solicitar.py` | Timeout 15 s |
| `Cadastrar` | `cadastrar.py` | Timeout 15 s |
| `Listar` | `listar.py` | Padrão |

Cole o código, clique em **Deploy**. Para `Solicitar`, `Cadastrar` e `Listar`, crie a **URL da função** com Auth type **NONE** e **CORS** ligado, e copie os endereços.

### 1.4 Interfaces
1. Edite `interface/config.js` e preencha `URL_SOLICITAR`, `URL_CADASTRAR` e `URL_LISTAR`.
2. Abra `interface/cliente.html` e `interface/colaborador.html` no navegador (não precisa de servidor).

## 2. Operação

### Cliente (`cliente.html`)
Informe o código do livro e o e-mail e clique em **Solicitar**.
- Livro com estoque: o inscrito recebe o e-mail pedindo que compareça à livraria.
- Livro sem estoque: o cliente entra na lista de espera e recebe o e-mail "você será avisado".

### Colaborador (`colaborador.html`)
- **Entrada**: informe código, título, autor e quantidade positiva. O estoque é somado, e quem estava na lista de espera daquele livro é avisado e removido da lista.
- **Saída**: quantidade negativa. Se não houver exemplares suficientes, a operação é recusada (409).
- A tabela **Estoque** lista os livros (exige a Lambda `Listar`).

### Teste por linha de comando
Em uma linha só:
```
curl -X POST "URL-DA-SOLICITAR" -H "Content-Type: application/json" -d '{"livro_id": "L001", "email": "seu@email.com"}'
```

## 3. Observações
- O Learner Lab desliga ao fim da sessão. Os recursos costumam permanecer, mas confira as URLs ao retomar.
- Todo inscrito no tópico recebe todos os avisos (o SNS não escolhe destinatário por mensagem); o enunciado simplifica isso.
