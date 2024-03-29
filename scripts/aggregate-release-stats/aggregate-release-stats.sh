#!/usr/bin/env bash

if [ "$DEBUG" = "true" ]
then
  set -x
fi

if [ -z "${RELEASE_NUMBER}" ] ;then
  echo "RELEASE_NUMBER must be set."
  exit 1
fi

if [ -z "${ENVIRONMENT}" ] ;then
  echo "ENVIRONMENT must be set."
  exit 1
fi

# e.g. /terraform/standalone
LOCAL_PATH=$(dirname "${BASH_SOURCE[0]}")
#pull in cloud-specific variables, e.g. tenancy
[ -e "$LOCAL_PATH/../../clouds/oracle.sh" ] && . $LOCAL_PATH/../../clouds/oracle.sh
[ -e "$LOCAL_PATH/../../sites/$ENVIRONMENT/stack-env.sh" ] && . "$LOCAL_PATH/../../sites/$ENVIRONMENT/stack-env.sh"

[ -z "$BUCKET_NAMESPACE" ] && BUCKET_NAMESPACE="$ORACLE_S3_NAMESPACE"
[ -z "$REGIONS" ] && REGIONS="$DRG_PEER_REGIONS"
[ -z "$REGIONS" ] && REGIONS="us-ashburn-1 us-phoenix-1 uk-london-1 sa-saopaulo-1 eu-frankfurt-1 ap-tokyo-1 ap-sydney-1 ap-mumbai-1 ca-toronto-1"

if [ -z "${BUCKET_NAMESPACE}" ] ;then
  echo "BUCKET_NAMESPACE is not set."
  exit 1
fi


echo "Running with RELEASE_NUMBER=${RELEASE_NUMBER}, ENVIRONMENT=${ENVIRONMENT}, REGIONS=${REGIONS}"

if [ -e ./pre-terminate-stats/release-${RELEASE_NUMBER} ] ;then
  echo "./pre-terminate-stats/release-${RELEASE_NUMBER} already exists, will not re-download."
else
  for region in $REGIONS; do
    oci os object bulk-download --bucket-name "stats-${ENVIRONMENT}" --download-dir . --namespace "$BUCKET_NAMESPACE" --region "$region" --prefix "pre-terminate-stats/release-${RELEASE_NUMBER}"
  done

  echo "Downloaded $(find pre-terminate-stats -type f | wc -l) files."
  for i in pre-terminate-stats/*/*.tar.gz; do 
    d=${i%.tar.gz}
    mkdir $d
    tar xf $i -C $d
  done
fi

DIR="pre-terminate-stats/release-${RELEASE_NUMBER}-aggregates"
mkdir -p "$DIR/jvb"
mkdir -p "$DIR/jicofo"
for i in templates/jvb/*; do
  template=$(basename $i)
  echo "Aggregating jvb/$template"
  node ./aggregate.js templates/jvb/$template pre-terminate-stats/release-${RELEASE_NUMBER}/${ENVIRONMENT}-jvb-*/$template > pre-terminate-stats/release-${RELEASE_NUMBER}-aggregates/jvb/$template
done

jicofo_dirs=$(find pre-terminate-stats/release-${RELEASE_NUMBER} -type d -name ${ENVIRONMENT}-* | grep -v ${ENVIRONMENT}-jvb-)
for i in templates/jicofo/*; do
  template=$(basename $i)
  echo "Aggregating jicofo/$template"
  templates=""
  for i in $jicofo_dirs; do templates="$templates $i/$template"; done
  node ./aggregate.js templates/jicofo/$template $templates > pre-terminate-stats/release-${RELEASE_NUMBER}-aggregates/jicofo/$template
done

node ./summarize.js "$DIR" > "$DIR/summary.txt"
