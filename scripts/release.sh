#!/bin/sh
BUILD="${1:-nightly}"
BUCKET="${2:-dl.influxdata.com/telegraf/nightly}"

: ${CIRCLE_TOKEN:?"Must set CIRCLE_TOKEN"}

prefix="$(mktemp -d -t telegraf.XXXXXXXXXX)"

on_exit() {
	rm -rf "$prefix"
}

echo "$prefix"
cd "$prefix"

trap on_exit EXIT

if [ "$BUILD" = nightly ]; then
	curl -s -S -u '${CIRLCE_TOKEN}:' "https://circleci.com/api/v1.1/project/github/influxdata/telegraf/tree/master?limit=100" -o builds || exit 1
	BUILD_NUM=$(cat builds | jq '[ .[] | select (.workflows.job_name == "nightly" and .workflows.workflow_name == "nightly")][0].build_num')
fi

echo "using build_num: $BUILD_NUM"

curl -s -S -u '${CIRLCE_TOKEN}:' "https://circleci.com/api/v1.1/project/github/influxdata/telegraf/${BUILD_NUM}/artifacts" -o artifacts || exit 1

cat artifacts | jq -r '.[] | "\(.url) \(.path)"' | egrep '(tar|rpm|deb|zip)$$' > manifest

while read url path;
do
	echo $url
	basepath="$(basename $path)"
	curl -s -S -o "$basepath" "$url" &&
	gpg --armor --detach-sign "$basepath" || exit 1
done < manifest

aws s3 sync ./ "s3://$BUCKET/" \
	--exclude "*" \
	--include "*.tar.gz" \
	--include "*.asc" \
	--include "*.deb" \
	--include "*.rpm" \
	--include "*.zip" \
	--acl public-read \
	--dry-run
