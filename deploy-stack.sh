#!/usr/bin/env bash

set -o errexit -o pipefail -o nounset

PARAMETERS_FILE=$1

TIMESTAMP=$(date "+%s")
ARTIFACT_BUCKET=$(jq -r '.[] | select(.ParameterKey == "ArtifactBucket") | .ParameterValue' $PARAMETERS_FILE)
STACK_NAME=$(jq -r '.[] | select(.ParameterKey == "ProjectSlug") | .ParameterValue' $PARAMETERS_FILE)
REGION=$(jq -r '.[] | select(.ParameterKey == "Region") | .ParameterValue' $PARAMETERS_FILE)
# only a-z A-Z 0-9
BLUE_VERSION=$(jq -r '.[] | select(.ParameterKey == "BlueVersion") | .ParameterValue' $PARAMETERS_FILE)
GREEN_VERSION=$(jq -r '.[] | select(.ParameterKey == "GreenVersion") | .ParameterValue' $PARAMETERS_FILE)

for item in build-changeset.yaml pipeline.yaml $PARAMETERS_FILE; do
  aws --profile ${STACK_NAME} s3 cp $item "s3://${ARTIFACT_BUCKET}/cloudformation/source-templates/${STACK_NAME}/"
done

#TODO: trigger the codebuild for build-changeset

exit 0




CHANGE_SET_NAME=$(echo "version-bump-${BLUE_VERSION}-to-${GREEN_VERSION}" | tr --squeeze-repeats [:punct:] '-')
echo "Creating Change Set: ${CHANGE_SET_NAME}"

#cfn-lint root.yaml
cfn-lint pipeline.yaml
#cfn-lint static.template.yaml

(
rm -rf package;
cd cleanup;
git clean -dX -f;
pip install --target ../package/python -r requirements.txt
)

aws s3 ls "s3://${ARTIFACT_BUCKET}" ||
  aws s3 mb "s3://${ARTIFACT_BUCKET}";

#aws cloudformation package \
#  --template-file root.yaml \
#  --s3-bucket $ARTIFACT_BUCKET \
#  --s3-prefix $STACK_NAME \
#  --output-template-file root.package.yml;
#
#aws cloudformation deploy \
#  --template-file root.package.yml \
#  --parameter-overrides file://../www.weboftomorrow.com-personal/parameters.json \
#  --stack-name $STACK_NAME-root \
#  --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND;

#aws cloudformation package \
#  --template-file static.template.yaml \
#  --s3-bucket $ARTIFACT_BUCKET \
#  --s3-prefix $STACK_NAME \
#  --output-template-file static.template.package.yml;
#aws cloudformation deploy \
#  --template-file static.template.package.yml \
#  --parameter-overrides file://../www.weboftomorrow.com-personal/parameters.json \
#  --stack-name $STACK_NAME-static \
#  --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND;

aws cloudformation package \
  --template-file pipeline.yaml \
  --s3-bucket $ARTIFACT_BUCKET \
  --s3-prefix $STACK_NAME \
  --output-template-file package.pipeline.yml;

aws cloudformation deploy \
  --template-file package.pipeline.yml \
  --parameter-overrides file://../www.weboftomorrow.com-personal/parameters.json \
  --stack-name $STACK_NAME-pipeline \
  --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND;
rm package.pipeline.yml

exit 0

aws s3 cp static.template.package.yml "s3://${ARTIFACT_BUCKET}/${STACK_NAME}/"

#aws cloudformation create-stack \
#  --stack-name $STACK_NAME \
#  --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
#  --parameters file://../www.weboftomorrow.com-personal/parameters.json \
#  --template-url "https://${ARTIFACT_BUCKET}.s3-${REGION}.amazonaws.com/${STACK_NAME}/static.template.package.yml"
#
#exit 0

#TODO aws cloudformation set-stack-policy

CHANGE_SET=$( \
aws cloudformation create-change-set \
  --change-set-name $CHANGE_SET_NAME \
  --stack-name $STACK_NAME \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameters file://../www.weboftomorrow.com-personal/parameters.json \
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
#  --parameter-overrides file://../www.weboftomorrow.com-personal/parameters.json \
#  --stack-name $STACK_NAME \
#  --capabilities CAPABILITY_NAMED_IAM;

