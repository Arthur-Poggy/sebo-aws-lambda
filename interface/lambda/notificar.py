import os
import json
import boto3

sns = boto3.client("sns")
TOPIC_ARN = os.environ["TOPIC_ARN"]


def lambda_handler(event, context):
    email = event.get("email", "")
    mensagem = event.get("mensagem", "")
    sns.publish(
        TopicArn=TOPIC_ARN,
        Subject="Sebo - aviso",
        Message=f"Para: {email}\n\n{mensagem}",
    )
    return {"statusCode": 200, "body": json.dumps({"enviado": True})}
