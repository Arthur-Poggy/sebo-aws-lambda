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
