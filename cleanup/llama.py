import os
import json
import logging
import boto3

# TODO:
#   Any files in the sourceZip root should have invalidations.
# - Copy 'error.html' from GreenVersion to StaticSiteFiles path "${ProjectSlug}/error.html".

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOGGING_LEVEL", logging.DEBUG))

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
    try:
        codepipeline.put_job_success_result(
            jobId=job_id)
    except Exception as err:
        put_job_failure(job_id, f"Exception with put_job_success() with message: '{message}'. {err}")

def put_job_failure(job_id, message):
    logger.error(message)
    codepipeline.put_job_failure_result(
        jobId=job_id,
        failureDetails={
            'message': message,
            'type': 'JobFailed'
        })


def delete_files(bucket_name, prefix, continuation_token=None):
    "List and delete objects from s3. Limited to 1000 objects at a time."
    s3 = boto3.client('s3')

    args = {
        "Bucket": bucket_name,
        "Prefix": prefix
    }
    if continuation_token:
        args["ContinuationToken"] = continuation_token

    list_objects_response = s3.list_objects_v2(**args)
    if list_objects_response.get('KeyCount', 0) == 0:
        logger.warn(f"Nothing to delete for '{prefix}' prefix in {bucket_name}")
        return

    objects_to_delete = list(map(lambda x: {'Key':x['Key']}, list_objects_response['Contents']))

    logger.info(f"Deleting {len(objects_to_delete)} objects in '{prefix}' prefix")
    response = s3.delete_objects(
        Bucket=bucket_name,
        Delete={
            "Quiet": True,
            "Objects": objects_to_delete,
        }
    )
    if response['ResponseMetadata']['HTTPStatusCode'] != 200:
        logger.error('failed. {response}')
        put_job_failure(job_id, f"Failed to delete files. {response}")
    if list_objects_response.get('IsTruncated'):
        logger.info("More than 1000 objects to delete. Deleting next chunk.")
        delete_files(bucket_name, prefix, continuation_token=list_objects_response.NextContinuationToken)


def handler(event, context):
    #"https://docs.aws.amazon.com/codepipeline/latest/userguide/actions-invoke-lambda-function.html"

    try:
        job_id = event["CodePipeline.job"]["id"]
        logger.debug(f"Job Id: {job_id}")
        job_data = event["CodePipeline.job"]["data"]
        logger.debug(f"Job data: {job_data}")

        user_params = get_user_params(job_data)
        logger.debug(f"user parameters: {user_params}")
        delete_files(user_params["StaticSiteFiles"], 'weboftomorrow/stage/')
        put_job_success(job_id, "Complete")
    except Exception as e:
        put_job_failure(job_id, f"Function failed due to exception. {e}")

