# boto3 is for python to communicate with aws services
import boto3
# os is for accessing environment variables
from os import environ
# genai is the google gemini api client library
from google import genai

# Defining constant variables
PROMPT = "Give me a funny fun fact about puppies in maximum 20 words."
BUCKET_NAME = environ['BUCKET_NAME']
GEMINI_API_KEY_ARN = environ['GEMINI_API_KEY_ARN']

# Creating clients (which are responsible for communicating with services)
# for AWS Secrets Manager, S3, and Gemini API
secrets_client = boto3.client('secretsmanager')
api_key = secrets_client.get_secret_value(SecretId=GEMINI_API_KEY_ARN)
gemini_client = genai.Client(api_key=api_key['SecretString'])
s3_client = boto3.client('s3')

# Lambda function handler which is the entry point for the AWS Lambda function
# Function to call Gemini API and store the result in the main S3 bucket within the file gemini.txt
def lambda_handler(event, context):
    gemini_response = gemini_client.models.generate_content(
        model="gemini-2.0-flash", contents=PROMPT
    )
    s3_client.put_object(
        Bucket=BUCKET_NAME,
        Key='gemini.txt',
        Body=gemini_response.text
    )

    return {'statusCode': 200}
