import os, json, boto3
from datetime import datetime, timezone

dynamodb = boto3.resource("dynamodb")
livros = dynamodb.Table("Livros")
espera = dynamodb.Table("ListaEspera")
lambda_client = boto3.client("lambda")
NOTIFICAR = os.environ.get("NOTIFICAR_FN", "Notificar")


def notificar(email, mensagem):
    lambda_client.invoke(
        FunctionName=NOTIFICAR,
        InvocationType="RequestResponse",
        Payload=json.dumps({"email": email, "mensagem": mensagem}),
    )


def resposta(status, corpo):
    return {"statusCode": status, "body": json.dumps(corpo, ensure_ascii=False)}


def lambda_handler(event, context):
    # aceita chamada pela Function URL (event["body"]) ou teste direto
    dados = json.loads(event["body"]) if "body" in event else event
    livro_id = dados.get("livro_id")
    email = dados.get("email")
    if not livro_id or not email:
        return resposta(400, {"erro": "livro_id e email são obrigatórios"})

    item = livros.get_item(Key={"id": livro_id}).get("Item")
    if item is None:
        return resposta(404, {"erro": "livro não encontrado"})

    titulo = item.get("titulo", livro_id)

    if int(item.get("quantidade", 0)) > 0:
        notificar(email, f"O livro '{titulo}' está disponível. "
                         "Compareça à livraria para efetivar a compra.")
        return resposta(200, {"status": "disponivel"})

    espera.put_item(Item={
        "livro_id": livro_id,
        "email": email,
        "data": datetime.now(timezone.utc).isoformat(),
    })
    notificar(email, f"O livro '{titulo}' não está disponível no momento. "
                     "Você será avisado por e-mail quando ele chegar.")
    return resposta(200, {"status": "lista_de_espera"})
