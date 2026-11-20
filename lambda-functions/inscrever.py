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