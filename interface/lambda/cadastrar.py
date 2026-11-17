# ATENÇÃO: versão de referência reescrita a partir da descrição do resumo T1-T7.
# A função publicada na AWS é a que vale; confira este arquivo com ela antes de entregar.
import os, json, boto3
from boto3.dynamodb.conditions import Key
from botocore.exceptions import ClientError

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
    dados = json.loads(event["body"]) if "body" in event else event
    livro_id = dados.get("id")
    titulo = dados.get("titulo")
    autor = dados.get("autor", "")
    try:
        delta = int(dados.get("quantidade"))
    except (TypeError, ValueError):
        return resposta(400, {"erro": "quantidade deve ser um inteiro"})
    if not livro_id or not titulo:
        return resposta(400, {"erro": "id e titulo são obrigatórios"})

    try:
        if delta < 0:
            # saída: só acontece se houver exemplares suficientes (condição atômica)
            r = livros.update_item(
                Key={"id": livro_id},
                UpdateExpression="ADD quantidade :d",
                ConditionExpression="attribute_exists(id) AND quantidade >= :min",
                ExpressionAttributeValues={":d": delta, ":min": -delta},
                ReturnValues="ALL_NEW",
            )
        else:
            r = livros.update_item(
                Key={"id": livro_id},
                UpdateExpression="SET titulo = :t, autor = :a ADD quantidade :d",
                ExpressionAttributeValues={":t": titulo, ":a": autor, ":d": delta},
                ReturnValues="ALL_NEW",
            )
    except ClientError as e:
        if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return resposta(409, {"erro": "estoque insuficiente"})
        raise

    quantidade = int(r["Attributes"]["quantidade"])
    avisados = 0
    if delta > 0 and quantidade > 0:
        fila = espera.query(KeyConditionExpression=Key("livro_id").eq(livro_id)).get("Items", [])
        for cliente in fila:
            notificar(cliente["email"],
                      f"O livro '{titulo}' chegou! Compareça à livraria para efetivar a compra.")
            espera.delete_item(Key={"livro_id": livro_id, "email": cliente["email"]})
            avisados += 1

    return resposta(200, {"id": livro_id, "quantidade": quantidade, "avisados": avisados})
