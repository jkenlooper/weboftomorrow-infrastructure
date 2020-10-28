#!/usr/bin/env bash

set -o errexit -o pipefail

ARTIFACT_BUCKET=build-artifacts-jkenlooper
STACK_NAME=weboftomorrow
REGION=us-west-2
TIMESTAMP=$(date "+%s")
# only a-z A-Z 0-9
BLUE_VERSION=$(jq -r '.[] | select(.ParameterKey == "BlueVersion") | .ParameterValue' parameters.json)
GREEN_VERSION=$(jq -r '.[] | select(.ParameterKey == "GreenVersion") | .ParameterValue' parameters.json)

CHANGE_SET_NAME=$(echo "version-bump-${BLUE_VERSION}-to-${GREEN_VERSION}" | tr --squeeze-repeats [:punct:] '-')
echo "Creating Change Set: ${CHANGE_SET_NAME}"

cfn-lint static.template.yaml

(
rm -rf package;
cd cleanup;
git clean -dX -f;
pip install --target ../package/python -r requirements.txt
)

aws s3 ls "s3://${ARTIFACT_BUCKET}" ||
  aws s3 mb "s3://${ARTIFACT_BUCKET}";

aws cloudformation package \
  --template-file static.template.yaml \
  --s3-bucket $ARTIFACT_BUCKET \
  --s3-prefix $STACK_NAME \
  --force-upload \
  --output-template-file static.template.package.yml;

aws s3 cp static.template.package.yml "s3://${ARTIFACT_BUCKET}/${STACK_NAME}/"

#aws cloudformation create-stack \
#  --stack-name $STACK_NAME \
#  --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
#  --parameters file://parameters.json \
#  --template-url "https://${ARTIFACT_BUCKET}.s3-${REGION}.amazonaws.com/${STACK_NAME}/static.template.package.yml"
#
#exit 0

#TODO aws cloudformation set-stack-policy

CHANGE_SET=$( \
aws cloudformation create-change-set \
  --change-set-name $CHANGE_SET_NAME \
  --stack-name $STACK_NAME \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameters file://parameters.json \
  --template-url "https://${ARTIFACT_BUCKET}.s3-${REGION}.amazonaws.com/${STACK_NAME}/static.template.package.yml" \
  --output text \
  --query 'Id' \
)

sleep 2s;
while [ $( \
aws cloudformation describe-change-set \
  --change-set-name "${CHANGE_SET}" \
  --stack-name $STACK_NAME \
  --output text \
  --query 'Status' \
) = 'CREATE_IN_PROGRESS' ]; do
  echo "create in progress...retrying in 5 seconds.";
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

