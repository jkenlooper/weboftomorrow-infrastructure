import os
import json
import logging
import boto3

# TODO:
#   Any files in the sourceZip root should have invalidations.

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOGGING_LEVEL", logging.DEBUG))


def get_user_params(job_data):
    ""
    try:
        user_params = job_data["actionConfiguration"]["configuration"]["UserParameters"]
        decoded_params = json.loads(user_params)
    except json.decoder.JSONDecodeError as e:
        raise Exception("UserParameters could not be decoded as JSON. {}".format(e))
    return decoded_params

def get_source_params(s3, job_data):
    """
    """
    try:
        parametersJSONArtifact = list(filter(lambda item: item["name"] == "parametersJSON", job_data["inputArtifacts"])).pop()
    except Exception as err:
        logger.error(f"parametersJSON input artifact not found in job data. {job_data}")
        raise err

    s3Loc = parametersJSONArtifact["location"]["s3Location"]
    args = {
        "Bucket": s3Loc["bucketName"],
        "Key": s3Loc["objectKey"]
    }

    get_response = s3.get_object(**args)
    logger.debug(f"S3 get object response: {get_response}")
    parameters = json.load(get_response["Body"])
    logger.debug(f"response body: {parameters}")

    return dict(map(lambda x: [x["ParameterKey"], x["ParameterValue"]], parameters))

def put_job_success(codepipeline, job_id, message):
    logger.debug(message)
    try:
        codepipeline.put_job_success_result(
            jobId=job_id)
    except Exception as err:
        put_job_failure(codepipeline, job_id, f"Exception with put_job_success() with message: '{message}'. {err}")

def put_job_failure(codepipeline, job_id, message):
    logger.error(message)
    codepipeline.put_job_failure_result(
        jobId=job_id,
        failureDetails={
            'message': message,
            'type': 'JobFailed'
        })

def list_objects_at_prefix(s3, bucket_name, prefix, continuation_token=None, object_list=[]):
    args = {
        "Bucket": bucket_name,
        "Prefix": prefix
    }
    if continuation_token:
        args["ContinuationToken"] = continuation_token

    list_objects_response = s3.list_objects_v2(**args)
    if list_objects_response.get('KeyCount', 0) == 0:
        return object_list

    objects = list(map(lambda x: x['Key'], list_objects_response['Contents']))
    if list_objects_response.get('IsTruncated'):
        objects = objects + list_objects_at_prefix(s3, bucket_name, prefix, continuation_token=list_objects_response.NextContinuationToken, object_list=objects)
    return objects

def delete_files(s3, bucket_name, prefix, continuation_token=None):
    "List and delete objects from s3. Limited to 1000 objects at a time."
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
        put_job_failure(codepipeline, job_id, f"Failed to delete files. {response}")
    if list_objects_response.get('IsTruncated'):
        logger.info("More than 1000 objects to delete. Deleting next chunk.")
        delete_files(s3, bucket_name, prefix, continuation_token=list_objects_response.NextContinuationToken)

def find_prefix_not_in_set(common_path, keep_set, keys):
    "Given a list of s3 object keys return the prefix that is not in the keep_set."
    return list(set(map(lambda x: x[len(common_path):].split('/', maxsplit=1)[0], keys)).difference(keep_set))

def handler(event, context):
    #"https://docs.aws.amazon.com/codepipeline/latest/userguide/actions-invoke-lambda-function.html"
    s3 = boto3.client('s3')
    codepipeline = boto3.client('codepipeline')

    try:
        job_id = event["CodePipeline.job"]["id"]
        logger.debug(f"Job Id: {job_id}")
        job_data = event["CodePipeline.job"]["data"]
        logger.debug(f"Job data: {job_data}")

        user_params = get_user_params(job_data)

        # TODO: get the input artifact for the parametersJSON
        source_params = get_source_params(s3, job_data)
        logger.debug(f"source parameters: {source_params}")

        logger.debug(f"user parameters: {user_params}")

        production_prefix = '{ProjectSlug}/production/'.format(**source_params)
        keys = list_objects_at_prefix(s3, user_params["StaticSiteFiles"], production_prefix)
        prefix_to_delete = find_prefix_not_in_set(production_prefix, set([source_params.get('BlueVersion'), source_params.get('GreenVersion')]), keys)
        for old_prefix in prefix_to_delete:
            delete_files(s3, user_params["StaticSiteFiles"], production_prefix + old_prefix)

        put_job_success(codepipeline, job_id, "Complete")
    except Exception as e:
        put_job_failure(codepipeline, job_id, f"Function failed due to exception. {e}")

