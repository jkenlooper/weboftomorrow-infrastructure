#!/usr/bin/env bash

SKIP_CHECKSUM=$1

set -o errexit -o pipefail -o nounset

source .env
#AWSCONFIG_PROFILE=artifact-pusher
#PARAMETERS_FILE=$1

ARTIFACT_BUCKET=$(aws configure get artifact_bucket --profile $AWSCONFIG_PROFILE)
REGION=$(aws configure get region --profile $AWSCONFIG_PROFILE)

STACK_NAME=weboftomorrow
# only a-z A-Z 0-9
CF_TEMPLATES="build-change-set.cfn.yaml security.cfn.yaml devops.cfn.yaml $STACK_NAME.cfn.yaml"

handle_no_build_change_set_error() {
  echo "Failed to start the build for ${STACK_NAME}-BuildChangeSet. Does it exist?"
  echo "Create the build change set stack in the AWS Console and use this template:"
  echo "https://${ARTIFACT_BUCKET}.s3-${REGION}.amazonaws.com/cloudformation/source-templates/${STACK_NAME}/build-change-set.cfn.yaml"
}
for template in $CF_TEMPLATES; do
  cfn-lint $template;
done

(
cd cleanup;
git clean -dx -f;
)

aws --profile $AWSCONFIG_PROFILE s3 cp $PARAMETERS_FILE "s3://${ARTIFACT_BUCKET}/cloudformation/source-templates/${STACK_NAME}/parameters.json"
for item in $CF_TEMPLATES; do
  aws --profile $AWSCONFIG_PROFILE s3 cp $item "s3://${ARTIFACT_BUCKET}/cloudformation/source-templates/${STACK_NAME}/"
done
aws --profile $AWSCONFIG_PROFILE s3 cp cleanup "s3://${ARTIFACT_BUCKET}/cloudformation/source-templates/${STACK_NAME}/cleanup/" --recursive

# TODO: only do this if the snippet isn't there.
# Create the snippet for the static website bucket policy.
SECRET_HEADER_STRING=$(aws --profile $AWSCONFIG_PROFILE \
  --output text \
  --query 'Parameter.Value' \
  ssm get-parameter --name "/${STACK_NAME}/secret-header-string")
TMP_DIR=$(mktemp -d)
cat << HERE > $TMP_DIR/resources.txt
arn:aws:s3:::$ARTIFACT_BUCKET/${STACK_NAME}/stage
arn:aws:s3:::$ARTIFACT_BUCKET/${STACK_NAME}/stage/*
arn:aws:s3:::$ARTIFACT_BUCKET/${STACK_NAME}/production
arn:aws:s3:::$ARTIFACT_BUCKET/${STACK_NAME}/production/*
HERE
jq --raw-input --null-input --raw-output \
  --arg stack_name $STACK_NAME \
  --arg secret_header_string "${SECRET_HEADER_STRING}" \
  '[inputs] | {
    Action: "s3:GetObject",
    Effect: "Allow",
    Principal: "*",
    Resource: .,
    Condition: {
      StringLike: {
        "aws:referer": $secret_header_string
      }
    }
  }' $TMP_DIR/resources.txt > $TMP_DIR/static-website-bucket-policy-statement.cfn.json
aws --profile $AWSCONFIG_PROFILE s3 cp $TMP_DIR/static-website-bucket-policy-statement.cfn.json "s3://${ARTIFACT_BUCKET}/cloudformation/source-templates/${STACK_NAME}/cfn-snippets/static-website-bucket-policy-statement.cfn.json"
rm -rf $TMP_DIR

# Assuming that the artifact bucket is in the same region.
for item in $CF_TEMPLATES; do
echo "https://${ARTIFACT_BUCKET}.s3-${REGION}.amazonaws.com/cloudformation/source-templates/${STACK_NAME}/$item"
done

# Trigger the codebuild for weboftomorrow-BuildChangeSet
aws --profile $AWSCONFIG_PROFILE \
  --output json \
  --query 'build.buildStatus' \
  codebuild start-build \
  --environment-variables-override "name=SKIP_CHECKSUM,value=$SKIP_CHECKSUM,type=PLAINTEXT" \
  --project-name ${STACK_NAME}-BuildChangeSet || handle_no_build_change_set_error
