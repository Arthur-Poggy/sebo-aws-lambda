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
