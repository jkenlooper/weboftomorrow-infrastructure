#!/usr/bin/env bash

set -o errexit -o pipefail

ARTIFACT_BUCKET=build-artifacts-jkenlooper
STACK_NAME=weboftomorrow
REGION=us-west-2

cfn-lint static.template.yaml

aws s3 ls "s3://${ARTIFACT_BUCKET}" ||
  aws s3 mb "s3://${ARTIFACT_BUCKET}";


aws cloudformation package \
  --template-file static.template.yaml \
  --s3-bucket $ARTIFACT_BUCKET \
  --s3-prefix $STACK_NAME \
  --force-upload \
  --output-template-file static.template.package.yml;

aws s3 cp static.template.package.yml "s3://${ARTIFACT_BUCKET}/${STACK_NAME}/"

CHANGE_SET=$( \
aws cloudformation create-change-set \
  --change-set-name weboftomorrow-test-1 \
  --stack-name $STACK_NAME \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameters file://parameters.json \
  --template-url "https://${ARTIFACT_BUCKET}.s3-${REGION}.amazonaws.com/${STACK_NAME}/static.template.package.yml" \
  --output json \
  | jq -r '.Id' \
)
echo $CHANGE_SET

sleep 2s;
while [ $( \
aws cloudformation describe-change-set \
  --change-set-name "${CHANGE_SET}" \
  --stack-name $STACK_NAME \
  --output json \
  | jq -r '.Status' \
) = 'CREATE_IN_PROGRESS' ]; do
  sleep 5s;
done;
aws cloudformation describe-change-set \
  --change-set-name "${CHANGE_SET}" \
  --stack-name $STACK_NAME | cat;

read -n 1 -p "Execute the change set? y/n: " EXECUTE
if [ $EXECUTE = 'y' ]; then
aws cloudformation execute-change-set \
  --change-set-name "${CHANGE_SET}" \
  --stack-name $STACK_NAME;
fi



#aws cloudformation deploy \
#  --template-file static.template.package.yml \
#  --parameter-overrides file://parameters.json \
#  --stack-name $STACK_NAME \
#  --capabilities CAPABILITY_NAMED_IAM;

