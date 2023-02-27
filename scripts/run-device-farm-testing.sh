#!/bin/bash
set -x #echo on
set -e

ifsOrigin=$IFS

[ -z "$EC2_REGION" ] && EC2_REGION="us-west-2"

[ -z "$DEVICEFARM_PROJECT_NAME" ] && DEVICEFARM_PROJECT_NAME="Jitsi-Meet-Mobile-Spike-Jenkins"

#android and ios devices which we use for tests
#use "aws devicefarm list-devices --region your_region to get device list with devices arn"
[ -z "$ANDROID_DEVICES" ] && ANDROID_DEVICES="arn:aws:devicefarm:us-west-2::device:BED682AAC76E4E2F89E3D44550F5A230"
[ -z "$IOS_DEVICES" ] && IOS_DEVICES="arn:aws:devicefarm:us-west-2::device:FD9876C6541D4D6186F338207B4881B2"

ARR_ANDROID_DEVICES=()
{ IFS=','; for device in $ANDROID_DEVICES;do
ARR_ANDROID_DEVICES+=("\"$device\"")
done; 
IFS=$ifsOrigin;}

ARR_IOS_DEVICES=()
{ IFS=','; for device in $IOS_DEVICES;do
ARR_IOS_DEVICES+=("\"$device\"")
done;
IFS=$ifsOrigin;}

if [ -z "$APP_NAME" ];then 
    echo "No application name provided or found. Exiting"
    exit 201
fi

if [ -z "$APP_TESTS_PACKAGE" ];then 
    echo "No tests package name provided or found. Exiting"
    exit 202
fi

if [ -z "$APP_PATH" ]; then 
    echo "No path to an application. Exiting"
    exit 203
fi

if [ -z "$APP_TEST_PACKAGE_PATH" ]; then 
    echo "No path to an application tests package. Exiting"
    exit 204
fi

if [ -z ""${TEST_RESULT_PATH}"" ]; then 
    echo "No path for test results. Exiting"
    exit 205
fi

[ -z "$TESTS_TYPE" ] && TESTS_TYPE="APPIUM_JAVA_JUNIT_TEST_PACKAGE"

[ -z "$ANDROID_DEVICE_POOL_NAME" ] && ANDROID_DEVICE_POOL_NAME="JenkinsAndroidPool"

[ -z "$IOS_DEVICE_POOL_NAME" ] && IOS_DEVICE_POOL_NAME="JenkinsIOSPool"

[ -z "$APPIUM_VERSION" ] && APPIUM_VERSION="1.4.16"

create_devicefarm_project(){
    project_exists=$(aws devicefarm list-projects --region $EC2_REGION | jq ".projects[] | select (.name==\"$DEVICEFARM_PROJECT_NAME\")" )

    if [ -z "$project_exists" ]; then
        echo "Create new AWS Device Farm project"
        DEVICEFARM_PROJECT_ARN=$( aws devicefarm create-project --region $EC2_REGION --name "$DEVICEFARM_PROJECT_NAME" | jq -r .project.arn )
    else
        echo "AWS Device Farm project exists. Getting project ARN"
        DEVICEFARM_PROJECT_ARN=$(echo "$project_exists" |  jq -r .arn )
    fi    
}

check_app_type(){
    app_extention="${APP_NAME##*.}"
    if [ $app_extention == "ipa" ]; then
        APP_TYPE="IOS_APP"
        echo "ios"
    elif [ $app_extention == "apk" ]; then
        APP_TYPE="ANDROID_APP"
        echo "android"
    fi
}

create_upload(){
    
    UPLOAD_TYPE=$1
    UPLOAD_NAME=$2
    
    app_upload_response=$(aws devicefarm create-upload \
    --region $EC2_REGION \
    --project-arn $DEVICEFARM_PROJECT_ARN \
    --name "$UPLOAD_NAME" \
    --type "$UPLOAD_TYPE" \
    )
    
    app_s3_url=$(echo $app_upload_response| jq -r .upload.url )
    app_arn=$(echo $app_upload_response| jq -r .upload.arn)
    
    echo $app_arn
}

check_upload(){

    UPLOAD_ARN=$1

    TEST_STATUS="INITIAL"
    while [ -z "$TEST_STATUS" ] || [ ${TEST_STATUS//\"} != "SUCCEEDED" ]; do
        TEST_STATUS_RESPONSE=$(aws devicefarm get-upload --region $EC2_REGION --arn $UPLOAD_ARN)
        TEST_STATUS="$(echo $TEST_STATUS_RESPONSE|jq -r .upload.status)"
        sleep 15
    done
}

upload_package(){
    
    FILE_TYPE=$1
    FILE_NAME=$2
    FILE_PATH=$3
    
    upload_exists=$(aws devicefarm list-uploads \
    --region $EC2_REGION \
    --arn $DEVICEFARM_PROJECT_ARN \
    | jq ".uploads[] | select (.name==\"$FILE_NAME\")")
    
    if [ -z "$upload_exists" ]; then
        create_upload $FILE_TYPE $FILE_NAME
    else
        upload_arn=$(echo "$upload_exists" | jq -r .arn) && \
        aws devicefarm delete-upload --region $EC2_REGION --arn $upload_arn && \
        create_upload $FILE_TYPE $FILE_NAME
    fi
    
    curl -T "$FILE_PATH" $app_s3_url

    check_upload $app_arn
}

create_android_device_pool(){
    android_devices=$( echo ${ANDROID_DEVICES[*]}|sed -e 's/,/\\",\\"/g' -e 's/^/\\"/' -e 's/$/\\"/')
    echo "$(aws devicefarm create-device-pool \
    --region $EC2_REGION \
    --project-arn $DEVICEFARM_PROJECT_ARN \
    --name "$ANDROID_DEVICE_POOL_NAME" \
    --rules '[{"attribute": "ARN","operator": "IN", "value": "['"$android_devices"']"}]'| jq .devicePool.arn )"
}

create_ios_device_pool(){
    ios_devices=$( echo ${IOS_DEVICES[*]}|sed -e 's/,/\\",\\"/g' -e 's/^/\\"/' -e 's/$/\\"/')
    echo "$(aws devicefarm create-device-pool \
    --region $EC2_REGION \
    --project-arn $DEVICEFARM_PROJECT_ARN \
    --name "$IOS_DEVICE_POOL_NAME" \
    --rules '[{"attribute": "ARN","operator": "IN", "value": "['"$ios_devices"']"}]'| jq -r .devicePool.arn )"
}

create_device_pools(){
    
    platform="$(check_app_type)"
    
    if [ "$platform" == "android" ]; then
        android_device_pool=$(aws devicefarm list-device-pools --region $EC2_REGION --arn $DEVICEFARM_PROJECT_ARN |jq ".devicePools[] | select(.name==\"$ANDROID_DEVICE_POOL_NAME\")" )
        if [ -z "$android_device_pool" ]; then
            echo "$(create_android_device_pool)"
        else
            local android_devices_arns="$(echo "$android_device_pool"|jq -r .rules[].value)"
            local android_device_pool_arn="$(echo "$android_device_pool"|jq -r .arn)"
            
            IFS=',';arr_android_devices_arns=($android_devices_arns);IFS=$ifsOrigin;
            
            if [ ${#arr_android_devices_arns[@]} -ne ${#ARR_ANDROID_DEVICES[@]} ];then
                aws devicefarm delete-device-pool --region $EC2_REGION --arn $android_device_pool_arn
                echo "$(create_android_device_pool)"
            else
                exist=0
                for dev in ${ARR_ANDROID_DEVICES[*]};do 
                    if echo $android_devices_arns | grep -q ${dev//\"}; then
                        continue
                    else
                        aws devicefarm delete-device-pool --region $EC2_REGION --arn $android_device_pool_arn
                        exist=1
                        break
                    fi
                done
                if [ $exist -eq 1 ];then
                    echo "$(create_android_device_pool)"
                else
                    echo "$android_device_pool_arn"
                fi
            fi
        fi
    elif [ "$platform" == "ios" ]; then
        ios_device_pool=$(aws devicefarm list-device-pools --region $EC2_REGION --arn $DEVICEFARM_PROJECT_ARN |jq ".devicePools[] | select(.name==\"$IOS_DEVICE_POOL_NAME\")" )
        if [ -z "$ios_device_pool" ]; then
            echo "$(create_ios_device_pool)"
        else
            local ios_devices_arns="$(echo "$ios_device_pool"|jq -r .rules[].value)"
            local ios_device_pool_arn="$(echo "$ios_device_pool"|jq -r .arn)"
            
            IFS=',';arr_ios_devices_arns=($ios_devices_arns);IFS=$ifsOrigin;
            
            if [ ${#arr_ios_devices_arns[@]} -ne ${#ARR_IOS_DEVICES[@]} ];then
                aws devicefarm delete-device-pool --region $EC2_REGION --arn $ios_device_pool_arn
                echo "$(create_ios_device_pool)"
            else
                exist=0
                for dev in ${ARR_IOS_DEVICES[*]};do 
                    if echo $ios_devices_arns | grep -q ${dev//\"};then
                        continue
                    else
                        aws devicefarm delete-device-pool --region $EC2_REGION --arn $ios_device_pool_arn
                        exist=1
                        break
                    fi
                    done
                if [ $exist -eq 1 ];then
                    echo "$(create_ios_device_pool)"
                else 
                    echo "$ios_device_pool_arn"
                fi
            fi
        fi
    fi
}

schedule_run(){
    
    testPackageArn=$(upload_package $TESTS_TYPE $APP_TESTS_PACKAGE $APP_TEST_PACKAGE_PATH)
    check_app_type
    appArn=$(upload_package $APP_TYPE $APP_NAME $APP_PATH)
    devicePoolArn=$(create_device_pools)
    test_name="${BUILD_TAG}" 
    
    testArn=$(
        aws devicefarm schedule-run \
        --region $EC2_REGION \
        --project-arn $DEVICEFARM_PROJECT_ARN \
        --app-arn $appArn \
        --device-pool-arn $devicePoolArn \
        --name "$test_name" \
        --test "{"\"type\"":"\"APPIUM_JAVA_TESTNG\"","\"testPackageArn\"":"\"$testPackageArn\"","\"parameters\"":{"\"appium_version\"":"\"$APPIUM_VERSION\""}}" \
        | jq -r .run.arn
    )
}

get_test_results(){
    TEST_STATUS_RESPONSE=$(aws devicefarm get-run --region $EC2_REGION --arn $testArn)
    TEST_STATUS="$(echo $TEST_STATUS_RESPONSE|jq -r .run.status)"
    
    while [ ${TEST_STATUS//\"} != "COMPLETED" ]; do
        TEST_STATUS_RESPONSE=$(aws devicefarm get-run --region $EC2_REGION --arn $testArn)
        TEST_STATUS="$(echo $TEST_STATUS_RESPONSE|jq -r .run.status)"
        sleep 60
    done
    
    echo "$TEST_STATUS_RESPONSE" > "${TEST_RESULT_PATH}/aws_devicefarm_tests_result.json"
    
    mkdir "${TEST_RESULT_PATH}/aws_devicefarm_logs" && cd "${TEST_RESULT_PATH}/aws_devicefarm_logs"
    
    LOGS_URL=$(aws devicefarm list-artifacts --region $EC2_REGION --arn $testArn --type FILE|jq -r .artifacts[].url)
    for url in $LOGS_URL; do
        filename=$(basename $url)
        wget -O "$(cut -d'?' -f1 <<< "$filename")" $url
    done
    
    cd "${TEST_RESULT_PATH}" && zip -r aws_devicefarm_logs.zip aws_devicefarm_logs/* && \
    rm -rf aws_devicefarm_logs
    
    if grep -q "PASSED" "${TEST_RESULT_PATH}/aws_devicefarm_tests_result.json"; then
        echo "Success"
        return 0
    else
        echo "Test failed"
        return 1
    fi
}

create_devicefarm_project
schedule_run

get_test_results
result=$?

exit $result