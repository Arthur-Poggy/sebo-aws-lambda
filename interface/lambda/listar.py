import json
import boto3

dynamodb = boto3.resource("dynamodb")
livros = dynamodb.Table("Livros")


def resposta(status, corpo):
    return {"statusCode": status, "body": json.dumps(corpo, ensure_ascii=False)}


def lambda_handler(event, context):
    itens = []
    kwargs = {}
    while True:
        r = livros.scan(**kwargs)
        itens.extend(r.get("Items", []))
        if "LastEvaluatedKey" not in r:
            break
        kwargs["ExclusiveStartKey"] = r["LastEvaluatedKey"]

    lista = [
        {
            "id": i["id"],
            "titulo": i.get("titulo", ""),
            "autor": i.get("autor", ""),
            "quantidade": int(i.get("quantidade", 0)),
        }
        for i in itens
    ]
    lista.sort(key=lambda l: l["id"])
    return resposta(200, {"livros": lista})
