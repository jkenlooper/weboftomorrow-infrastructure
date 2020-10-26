import os
import logging
import boto3


logger = logging.getLogger()
logger.setLevel(os.environ.get(LOGGING_LEVEL, logging.DEBUG))

#s3 = boto3.client('s3')
#s3.get_object(
#    Bucket=
#)
codepipeline = boto3.client('codepipeline')

def get_user_params(job_data):
    ""
    try:
        user_params = job_data["actionConfiguration"]["configuration"]["UserParameters"]
        decoded_params = json.loads(user_params)
    except json.decoder.JSONDecodeError as e:
        raise Exception("UserParameters could not be decoded as JSON. {}".format(e))
    return decoded_params

def put_job_success(job_id, message):
    logger.debug(message)
    codepipeline.put_job_success_result(
        jobId=job_id)

def put_job_failure(job_id, message):
    logger.error(message)
    codepipeline.put_job_failure_result(
        jobId=job_id,
        failureDetails={
            'message': message,
            'type': 'JobFailed'
        })


def handler(event, context):
    #"https://docs.aws.amazon.com/codepipeline/latest/userguide/actions-invoke-lambda-function.html"

    try:
        job_id = event["CodePipeline.job"]["id"]
        logger.debug(f"Job Id: {job_id}")
        job_data = event["CodePipeline.job"]["data"]
        logger.debug(f"Job data: {job_data}")

        user_params = get_user_params(job_data)
        logger.debug(f"user parameters: {user_params}")
    except Exception as e:
        put_job_failure(job_id, f"Function failed due to exception. {e}")

    logger.info("Complete")
    return "Complete"
