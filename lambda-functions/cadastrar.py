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
