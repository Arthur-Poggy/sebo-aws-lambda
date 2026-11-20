#!/usr/bin/env bash
# recriar_sebo.sh
# Recria o back-end do sebo no AWS Academy Learner Lab:
#   - tabelas DynamoDB Livros e ListaEspera
#   - tópico SNS LivrariaAvisos com uma assinatura de e-mail
#   - Lambdas Notificar, Solicitar, Cadastrar, Listar e Inscrever (usando a LabRole)
#   - Function URLs da Solicitar, da Cadastrar, da Listar e da Inscrever
#
# Uso, no CloudShell:  bash recriar_sebo.sh seu@email.com
#
# Pode ser rodado de novo sem estragar nada: o que já existe é mantido,
# e o código das Lambdas é atualizado.

set -euo pipefail

EMAIL="${1:-}"
if [ -z "$EMAIL" ]; then
  echo "Uso: bash recriar_sebo.sh seu@email.com"
  exit 1
fi

export AWS_DEFAULT_REGION="us-east-1"
export AWS_PAGER=""

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/LabRole"
WORK="$(mktemp -d)"

echo "Conta: ${ACCOUNT_ID}  |  Região: ${AWS_DEFAULT_REGION}"
echo "Role das Lambdas: ${ROLE_ARN}"

# ---------------------------------------------------------------- DynamoDB
echo
echo "[1/4] Tabelas DynamoDB"

criar_tabela() {
  local nome="$1"; shift
  if aws dynamodb describe-table --table-name "$nome" >/dev/null 2>&1; then
    echo "  ${nome}: já existe, mantida"
  else
    aws dynamodb create-table --table-name "$nome" \
      --billing-mode PAY_PER_REQUEST "$@" >/dev/null
    aws dynamodb wait table-exists --table-name "$nome"
    echo "  ${nome}: criada"
  fi
}

criar_tabela Livros \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH

criar_tabela ListaEspera \
  --attribute-definitions AttributeName=livro_id,AttributeType=S AttributeName=email,AttributeType=S \
  --key-schema AttributeName=livro_id,KeyType=HASH AttributeName=email,KeyType=RANGE

# Livros de teste. Só entram se o id ainda não existir, para não zerar o estoque.
semear() {
  local out
  if out="$(aws dynamodb put-item --table-name Livros --item "$1" \
        --condition-expression "attribute_not_exists(id)" 2>&1)"; then
    echo "  livro $2: cadastrado"
  elif echo "$out" | grep -q "ConditionalCheckFailed"; then
    echo "  livro $2: já existia, mantido"
  else
    echo "  livro $2: ERRO: $out"
    return 1
  fi
}

semear '{"id":{"S":"L001"},"titulo":{"S":"Dom Casmurro"},"autor":{"S":"Machado de Assis"},"quantidade":{"N":"1"}}' L001
semear '{"id":{"S":"L002"},"titulo":{"S":"O Hobbit"},"autor":{"S":"J.R.R. Tolkien"},"quantidade":{"N":"0"}}' L002

# --------------------------------------------------------------------- SNS
echo
echo "[2/4] Tópico SNS"

TOPIC_ARN="$(aws sns create-topic --name LivrariaAvisos --query TopicArn --output text)"
aws sns subscribe --topic-arn "$TOPIC_ARN" --protocol email \
  --notification-endpoint "$EMAIL" >/dev/null
echo "  tópico: ${TOPIC_ARN}"
echo "  assinatura enviada para ${EMAIL} (falta confirmar pelo link no e-mail)"

# ------------------------------------------------------------ código Lambda
mkdir -p "$WORK/notificar" "$WORK/solicitar" "$WORK/cadastrar" "$WORK/listar" "$WORK/inscrever"

cat > "$WORK/notificar/lambda_function.py" << 'PYEOF'
import os, json, boto3

sns = boto3.client("sns")
TOPIC_ARN = os.environ["TOPIC_ARN"]

def lambda_handler(event, context):
    email = event["email"]
    mensagem = event["mensagem"]
    # o atributo permite que cada assinatura filtre só as mensagens dirigidas ao seu e-mail
    sns.publish(
        TopicArn=TOPIC_ARN,
        Subject="Sebo - aviso sobre livro",
        Message=f"Para: {email}\n\n{mensagem}",
        MessageAttributes={"email": {"DataType": "String", "StringValue": email.strip().lower()}},
    )
    return {"statusCode": 200, "body": json.dumps({"enviado_para": email})}
PYEOF

cat > "$WORK/solicitar/lambda_function.py" << 'PYEOF'
import os, json, boto3
from datetime import datetime, timezone
from botocore.exceptions import ClientError

dynamodb = boto3.resource("dynamodb")
livros = dynamodb.Table("Livros")
espera = dynamodb.Table("ListaEspera")
lambda_client = boto3.client("lambda")
NOTIFICAR = os.environ.get("NOTIFICAR_FN", "Notificar")

def notificar(email, mensagem):
    try:
        r = lambda_client.invoke(
            FunctionName=NOTIFICAR,
            InvocationType="RequestResponse",
            Payload=json.dumps({"email": email, "mensagem": mensagem}),
        )
    except ClientError as e:
        print(f"Não foi possível invocar a Notificar: {e}")
        return False
    # invoke não levanta erro se a função chamada quebrar: a falha vem em FunctionError
    if "FunctionError" in r:
        print(f"Notificar falhou: {r['Payload'].read().decode()}")
        return False
    return True

def resposta(status, corpo):
    return {"statusCode": status, "body": json.dumps(corpo, ensure_ascii=False)}

def lambda_handler(event, context):
    # aceita chamada pela Function URL (event["body"]) ou teste direto
    try:
        dados = json.loads(event["body"]) if "body" in event else event
    except (TypeError, json.JSONDecodeError):
        return resposta(400, {"erro": "o corpo da requisição não é um JSON válido"})
    if not isinstance(dados, dict):
        return resposta(400, {"erro": "o corpo deve ser um objeto JSON"})

    livro_id = dados.get("livro_id")
    email = dados.get("email")
    if not isinstance(livro_id, str) or not isinstance(email, str) or not livro_id or not email:
        return resposta(400, {"erro": "livro_id e email são obrigatórios e devem ser texto"})

    item = livros.get_item(Key={"id": livro_id}).get("Item")
    if item is None:
        return resposta(404, {"erro": "livro não encontrado"})

    titulo = item.get("titulo", livro_id)

    if int(item.get("quantidade", 0)) > 0:
        if not notificar(email, f"O livro '{titulo}' está disponível. "
                                "Compareça à livraria para efetivar a compra."):
            return resposta(502, {"erro": "não foi possível enviar o e-mail de aviso"})
        return resposta(200, {"status": "disponivel"})

    espera.put_item(Item={
        "livro_id": livro_id,
        "email": email,
        "data": datetime.now(timezone.utc).isoformat(),
    })
    if not notificar(email, f"O livro '{titulo}' não está disponível no momento. "
                            "Você será avisado por e-mail quando ele chegar."):
        return resposta(502, {"erro": "pedido registrado na lista de espera, "
                                      "mas não foi possível enviar o e-mail"})
    return resposta(200, {"status": "lista_de_espera"})
PYEOF

cat > "$WORK/cadastrar/lambda_function.py" << 'PYEOF'
import os, json, boto3
from boto3.dynamodb.conditions import Key
from botocore.exceptions import ClientError

dynamodb = boto3.resource("dynamodb")
livros = dynamodb.Table("Livros")
espera = dynamodb.Table("ListaEspera")
lambda_client = boto3.client("lambda")
NOTIFICAR = os.environ.get("NOTIFICAR_FN", "Notificar")

def notificar(email, mensagem):
    try:
        r = lambda_client.invoke(
            FunctionName=NOTIFICAR,
            InvocationType="RequestResponse",
            Payload=json.dumps({"email": email, "mensagem": mensagem}),
        )
    except ClientError as e:
        print(f"Não foi possível invocar a Notificar: {e}")
        return False
    # invoke não levanta erro se a função chamada quebrar: a falha vem em FunctionError
    if "FunctionError" in r:
        print(f"Notificar falhou: {r['Payload'].read().decode()}")
        return False
    return True

def resposta(status, corpo):
    return {"statusCode": status, "body": json.dumps(corpo, ensure_ascii=False)}

def lambda_handler(event, context):
    try:
        dados = json.loads(event["body"]) if "body" in event else event
    except (TypeError, json.JSONDecodeError):
        return resposta(400, {"erro": "o corpo da requisição não é um JSON válido"})
    if not isinstance(dados, dict):
        return resposta(400, {"erro": "o corpo deve ser um objeto JSON"})

    livro_id = dados.get("id")
    titulo = dados.get("titulo")
    autor = dados.get("autor", "")
    if (not isinstance(livro_id, str) or not isinstance(titulo, str)
            or not isinstance(autor, str) or not livro_id or not titulo):
        return resposta(400, {"erro": "id e titulo são obrigatórios e id, titulo e autor devem ser texto"})
    try:
        qtd = int(dados.get("quantidade", 1))
    except (TypeError, ValueError):
        return resposta(400, {"erro": "quantidade deve ser um número inteiro"})

    valores = {":t": titulo, ":a": autor, ":q": qtd}
    condicao = {}
    if qtd < 0:
        # saída de estoque: só permite se houver exemplares suficientes
        condicao["ConditionExpression"] = "quantidade >= :min"
        valores[":min"] = -qtd

    # soma ao estoque (cria o livro se não existir)
    try:
        livros.update_item(
            Key={"id": livro_id},
            UpdateExpression="SET titulo = :t, autor = :a ADD quantidade :q",
            ExpressionAttributeValues=valores,
            **condicao,
        )
    except dynamodb.meta.client.exceptions.ConditionalCheckFailedException:
        return resposta(409, {"erro": "estoque insuficiente para essa saída"})

    avisados, falhas = [], []
    if qtd > 0:
        r = espera.query(KeyConditionExpression=Key("livro_id").eq(livro_id))
        for cliente in r["Items"]:
            email = cliente["email"]
            if notificar(email, f"O livro '{titulo}' chegou! Compareça à livraria para efetivar a compra."):
                espera.delete_item(Key={"livro_id": livro_id, "email": email})
                avisados.append(email)
            else:
                # continua na ListaEspera: será avisado na próxima chegada
                falhas.append(email)

    status = "parcial" if falhas else "ok"
    return resposta(200, {"status": status, "clientes_avisados": avisados, "falhas": falhas})
PYEOF

cat > "$WORK/listar/lambda_function.py" << 'PYEOF'
import json, unicodedata, boto3

dynamodb = boto3.resource("dynamodb")
livros = dynamodb.Table("Livros")

def ordenavel(titulo):
    decomposto = unicodedata.normalize("NFD", titulo.lower())
    return "".join(c for c in decomposto if not unicodedata.combining(c))

def lambda_handler(event, context):
    r = livros.scan()
    itens = r["Items"]
    while "LastEvaluatedKey" in r:
        r = livros.scan(ExclusiveStartKey=r["LastEvaluatedKey"])
        itens.extend(r["Items"])

    lista = [
        {
            "id": i["id"],
            "titulo": i.get("titulo", ""),
            "autor": i.get("autor", ""),
            "quantidade": int(i.get("quantidade", 0)),
        }
        for i in itens
    ]
    lista.sort(key=lambda livro: ordenavel(livro["titulo"]))
    return {"statusCode": 200, "body": json.dumps({"livros": lista}, ensure_ascii=False)}
PYEOF

cat > "$WORK/inscrever/lambda_function.py" << 'PYEOF'
import os, re, json, boto3
from botocore.exceptions import ClientError

sns = boto3.client("sns")
TOPIC_ARN = os.environ["TOPIC_ARN"]
PADRAO_EMAIL = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")

def resposta(status, corpo):
    return {"statusCode": status, "body": json.dumps(corpo, ensure_ascii=False)}

def lambda_handler(event, context):
    try:
        dados = json.loads(event["body"]) if "body" in event else event
    except (TypeError, json.JSONDecodeError):
        return resposta(400, {"erro": "o corpo da requisição não é um JSON válido"})
    if not isinstance(dados, dict):
        return resposta(400, {"erro": "o corpo deve ser um objeto JSON"})

    email = dados.get("email")
    if not isinstance(email, str):
        return resposta(400, {"erro": "email é obrigatório e deve ser texto"})
    email = email.strip().lower()
    if len(email) > 254 or not PADRAO_EMAIL.match(email):
        return resposta(400, {"erro": "e-mail inválido"})

    try:
        sns.subscribe(
            TopicArn=TOPIC_ARN,
            Protocol="email",
            Endpoint=email,
            Attributes={"FilterPolicy": json.dumps({"email": [email]})},
        )
    except ClientError as e:
        print(f"Falha ao inscrever {email}: {e}")
        return resposta(502, {"erro": "não foi possível cadastrar o e-mail"})
    return resposta(200, {"status": "confirmacao_enviada"})
PYEOF

# ------------------------------------------------------------------ Lambdas
echo
echo "[3/4] Funções Lambda"

# implantar NOME PASTA ["Variables={...}"]
implantar() {
  local nome="$1" dir="$2" env="${3:-}"
  local zip="$WORK/${nome}.zip"
  local args=()
  if [ -n "$env" ]; then
    args=(--environment "$env")
  fi
  (cd "$WORK/$dir" && python3 -m zipfile -c "$zip" lambda_function.py)

  if aws lambda get-function --function-name "$nome" >/dev/null 2>&1; then
    aws lambda update-function-code --function-name "$nome" \
      --zip-file "fileb://${zip}" >/dev/null
    aws lambda wait function-updated --function-name "$nome"
    aws lambda update-function-configuration --function-name "$nome" \
      --timeout 15 ${args[@]+"${args[@]}"} >/dev/null
    aws lambda wait function-updated --function-name "$nome"
    echo "  ${nome}: já existia, código e configuração atualizados"
  else
    aws lambda create-function --function-name "$nome" \
      --runtime python3.13 --role "$ROLE_ARN" \
      --handler lambda_function.lambda_handler --timeout 15 \
      --zip-file "fileb://${zip}" ${args[@]+"${args[@]}"} >/dev/null
    aws lambda wait function-active-v2 --function-name "$nome"
    echo "  ${nome}: criada"
  fi
}

implantar Notificar notificar "Variables={TOPIC_ARN=${TOPIC_ARN}}"
implantar Solicitar solicitar "Variables={NOTIFICAR_FN=Notificar}"
implantar Cadastrar cadastrar "Variables={NOTIFICAR_FN=Notificar}"
implantar Listar listar
implantar Inscrever inscrever "Variables={TOPIC_ARN=${TOPIC_ARN}}"

# ------------------------------------------------------------ Function URLs
echo
echo "[4/4] Function URLs (Auth NONE, CORS ligado)"

# Desde out/2025, uma URL com Auth NONE precisa de duas permissões públicas:
# lambda:InvokeFunctionUrl e lambda:InvokeFunction.
permitir() {
  local out
  if ! out="$(aws lambda add-permission "$@" 2>&1)"; then
    if echo "$out" | grep -q "ResourceConflictException"; then
      return 0
    fi
    echo "  AVISO: ${out}"
  fi
  return 0
}

criar_url() {
  local nome="$1" url
  url="$(aws lambda get-function-url-config --function-name "$nome" \
          --query FunctionUrl --output text 2>/dev/null || true)"
  if [ -z "$url" ] || [ "$url" = "None" ]; then
    url="$(aws lambda create-function-url-config --function-name "$nome" \
            --auth-type NONE \
            --cors '{"AllowOrigins":["*"],"AllowMethods":["*"],"AllowHeaders":["content-type"]}' \
            --query FunctionUrl --output text)"
  fi
  permitir --function-name "$nome" --statement-id UrlPublicInvokeUrl \
    --action lambda:InvokeFunctionUrl --principal "*" --function-url-auth-type NONE
  permitir --function-name "$nome" --statement-id UrlPublicInvokeFunction \
    --action lambda:InvokeFunction --principal "*" --invoked-via-function-url
  echo "$url"
}

URL_SOLICITAR="$(criar_url Solicitar)"
URL_CADASTRAR="$(criar_url Cadastrar)"
URL_LISTAR="$(criar_url Listar)"
URL_INSCREVER="$(criar_url Inscrever)"

# ------------------------------------------------------------------- final
echo
echo "================================================================"
echo "Pronto."
echo
echo "URL da Solicitar: ${URL_SOLICITAR}"
echo "URL da Cadastrar: ${URL_CADASTRAR}"
echo "URL da Listar: ${URL_LISTAR}"
echo "URL da Inscrever: ${URL_INSCREVER}"
echo
echo "================================================================"

rm -rf "$WORK"
