#!/usr/bin/env bash

set -o errexit -o pipefail -o nounset

PARAMETERS_FILE=$1
ARTIFACT_BUCKET=$2

TIMESTAMP=$(date "+%s")
STACK_NAME=$(jq -r '.[] | select(.ParameterKey == "ProjectSlug") | .ParameterValue' $PARAMETERS_FILE)
REGION=$(jq -r '.[] | select(.ParameterKey == "Region") | .ParameterValue' $PARAMETERS_FILE)
# only a-z A-Z 0-9
BLUE_VERSION=$(jq -r '.[] | select(.ParameterKey == "BlueVersion") | .ParameterValue' $PARAMETERS_FILE)
GREEN_VERSION=$(jq -r '.[] | select(.ParameterKey == "GreenVersion") | .ParameterValue' $PARAMETERS_FILE)
CF_TEMPLATES="build-change-set.yaml pipeline.yaml static-website.yaml"

handle_no_build_change_set_error() {
  echo "Failed to start the build for ${STACK_NAME}-BuildChangeSet. Does it exist?"
  echo "Create the build change set stack in the AWS Console and use this template:"
  echo "https://${ARTIFACT_BUCKET}.s3-${REGION}.amazonaws.com/cloudformation/source-templates/${STACK_NAME}/build-change-set.yaml"
}
for template in $CF_TEMPLATES; do
  cfn-lint $template;
done

(
cd cleanup;
git clean -dx -f;
)

aws --profile artifact-pusher s3 cp $PARAMETERS_FILE "s3://${ARTIFACT_BUCKET}/cloudformation/source-templates/${STACK_NAME}/parameters.json"
for item in $CF_TEMPLATES; do
  aws --profile artifact-pusher s3 cp $item "s3://${ARTIFACT_BUCKET}/cloudformation/source-templates/${STACK_NAME}/"
done
aws --profile artifact-pusher s3 cp cleanup "s3://${ARTIFACT_BUCKET}/cloudformation/source-templates/${STACK_NAME}/cleanup/" --recursive

# Trigger the codebuild for build-change-set
aws --profile artifact-pusher \
  --output json \
  --query 'build.buildStatus' \
  codebuild start-build \
  --project-name ${STACK_NAME}-BuildChangeSet || handle_no_build_change_set_error
