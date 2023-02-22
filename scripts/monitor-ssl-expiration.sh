#!/bin/bash
set -x #echo on

FILE_NAME="sns_message.txt"
expired_cert=[]
expired_date=[]
status=0
i=0

[ -z $SNS_TOPIC ] && SNS_TOPIC="arn:aws:sns:us-east-1:103425057857:JenkinsNotices"

if [ -z "$sites" ];then
    sites=$1
fi

for site in ${sites};do
	#check that certificate is valid for 30 days
    if openssl s_client -servername ${site} -connect ${site}:443 2>/dev/null | openssl x509 -noout -checkend 2592000
    then
    	echo "Certificate is good for the ${site}"
    else
    	exp_date="$(date --date="$(openssl s_client -servername ${site} -connect ${site}:443 2>/dev/null | openssl x509 -noout -enddate | cut -d= -f 2)" --iso-8601)"
    	echo "Certificate has expired or will do so within 30 days! Expiration date is $exp_date"
        expired_cert[$i]=${site}
        expired_date[$i]=${exp_date}
        ((i++))
        status=1
    fi
done

if [ $status -eq 1 ];then
echo -ne "BUILD: $BUILD_NUMBER\nJOB_NAME: $JOB_BASE_NAME\nURL: $BUILD_URL\nEXPIRE SITES:\n" > sns_message.txt

for iter in ${!expired_cert[*]};do
echo "${expired_cert[$iter]} Expiration date is ${expired_date[$iter]}" >> sns_message.txt
done

aws sns publish --region "us-east-1" --topic-arn "${SNS_TOPIC}" \
--subject "Jenkins $JOB_BASE_NAME" \
--message file://"$FILE_NAME"

rm -f "$FILE_NAME"
fi

exit $status