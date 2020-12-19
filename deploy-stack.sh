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
