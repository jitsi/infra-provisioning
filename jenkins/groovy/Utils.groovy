// splits incoming clouds into a list
// alternately loads defaults for environment into a list
def SplitClouds(shard_environment,cloud_names) {
    if (cloud_names) {
        clouds = cloud_names.split(' ')
    } else {
        clouds = sh(
            returnStdout: true,
            script: 'scripts/release_clouds.sh '+shard_environment
        ).trim().split(' ');
    }
    return clouds
}

def SplitNomadRegions(environment,region_names) {
    if (!region_names) {
        region_names = sh(
            returnStdout: true,
            script: """#!/bin/bash
. ./sites/${environment}/stack-env.sh
echo \$NOMAD_REGIONS"""
        ).trim()
    }
    if (!region_names) {
        error("no nomad region_names entered or in stack-env.sh")
    }

    return region_names.split(' ')
}

def ReplicateImageOracle(image_type) {
    sh(
        script: """#!/bin/bash
        export FORCE_BUILD_IMAGE=true
        export IMAGE_TYPE="${image_type}"
        # copy new image to root tenancy
        export DEST_COMPARTMENT_USE_TENANCY="true"
        scripts/replicate-image-oracle.sh
        exit \$?"""
    )
}
def SetupOCI() {
    withCredentials([
        file(credentialsId: 'oci-jenkins-config', variable: 'OCI_CLI_CONFIG_FILE'),
        file(credentialsId: 'oci-jenkins-pem', variable: 'OCI_CLI_KEY_FILE')
    ]) {
        sh 'rm -rf ~/.oci'
        sh 'mkdir -p ~/.oci'
        sh 'cp "$OCI_CLI_CONFIG_FILE" ~/.oci/config'
        sh 'cp "$OCI_CLI_KEY_FILE" ~/.oci/private-key.pem'
    }
}
def SetupAnsible() {
    withCredentials([
        string(credentialsId: 'ansible-vault-password', variable: 'ANSIBLE_VAULT_PASSWORD_PATH'),
    ]) {
        sh 'echo "$ANSIBLE_VAULT_PASSWORD_PATH" > ./.vault-password.txt'
    }
}
def CheckSkipBuild(image_type, environment, force_build) {
    echo "checking for existing ${image_type} images before building, FORCE_BUILD_IMAGE is ${force_build}"
    def checkOutput = sh(
        returnStatus: true,
        script: """#!/bin/bash
        export IMAGE_TYPE="${image_type}"
        export CLOUDS=\$(scripts/release_clouds.sh ${environment})
        SKIP_BUILD=false
        if [[ "${force_build}" != "true" ]]; then
            scripts/check-build-oracle-image-for-clouds.sh && SKIP_BUILD=true
        fi
        if \$SKIP_BUILD; then
            exit 1
        fi"""
    )
    // echo checkOutput;
    return (checkOutput == 1);
}

def SetupRepos(branch) {
  sshagent (credentials: ['video-infra']) {
      def scmUrl = scm.getUserRemoteConfigs()[0].getUrl()
      dir('infra-provisioning') {
        retry(count: 3) {
          git branch: branch, url: scmUrl, credentialsId: 'video-infra'
        }
      }
      if (env.INFRA_CONFIGURATION_REPO) {
        dir('infra-configuration') {
            retry(count: 3) {
                try {
                    checkout([$class: 'GitSCM', branches: [[name: "origin/${branch}"]], extensions: [[$class: 'SubmoduleOption', disableSubmodules: false, parentCredentials: false, recursiveSubmodules: true, reference: '', trackingSubmodules: false]], userRemoteConfigs: [[credentialsId: 'video-infra', url: env.INFRA_CONFIGURATION_REPO]]])
                } catch (hudson.AbortException e) {
                    if (e.toString().contains('Couldn\'t find any revision to build')) {
                        echo "WARNING: couldn't find branch ${branch} in infra-configuration repo, falling back to main"
                        checkout([$class: 'GitSCM', branches: [[name: "origin/main"]], extensions: [[$class: 'SubmoduleOption', disableSubmodules: false, parentCredentials: false, recursiveSubmodules: true, reference: '', trackingSubmodules: false]], userRemoteConfigs: [[credentialsId: 'video-infra', url: env.INFRA_CONFIGURATION_REPO]]])
                    } else {
                        throw e
                    }
                }
                SetupAnsible()
            }
        }
      }
      dir('infra-customization') {
        retry(count: 3) {
          try {
            git branch: branch, url: env.INFRA_CUSTOMIZATIONS_REPO, credentialsId: 'video-infra'
          } catch (hudson.AbortException e) {
            if (e.toString().contains('Couldn\'t find any revision to build')) {
                echo "WARNING: couldn't find branch ${branch} in infra-customization repo, falling back to main"
                git branch: 'main', url: env.INFRA_CUSTOMIZATIONS_REPO, credentialsId: 'video-infra'
            } else {
                throw e
            }
          }
        }
      }
      if (env.INFRA_CONFIGURATION_REPO) {
        sh 'cp -a infra-customization/* infra-configuration'
      }
      sh 'cp -a infra-customization/* infra-provisioning'
  }
}

def CreateImageOracle(image_type) {
    def image_script
    switch (env.IMAGE_TYPE) {
        case 'JVB':
            image_script = 'build-jvb-oracle.sh'
        break;
        case 'JicofoHotfix':
            image_script = 'build-jicofo-hotfix-oracle.sh'
        break;
        case 'Signal':
            image_script = 'build-signal-oracle.sh'
        break;
        case 'JavaJibri':
            image_script = 'build-java-jibri-oracle.sh'
        break;
        case 'Jigasi':
            image_script = 'build-jigasi-oracle.sh'
        break;
        case 'coTURN':
        case 'CoTURN':
            image_script = 'build-coturn-oracle.sh'
        break;
        case 'SeleniumGrid':
            image_script = 'build-selenium-grid-oracle.sh'
        break;
        case 'FocalBase':
            image_script = 'build-focal-base-oracle.sh'
        break;
        case 'JammyBase':
            image_script = 'build-jammy-base-oracle.sh'
        break;
        case 'NobleBase':
            image_script = 'build-noble-base-oracle.sh'
        break;
        default:
            def build_script_part_lower = env.IMAGE_TYPE.toLowerCase()
            def build_script_name = "build-${build_script_part_lower}-oracle.sh"
            if (fileExists("scripts/$build_script_name")) {
                image_script = build_script_name;
            } else {
                echo "No known image type ${env.IMAGE_TYPE}"
            }
        break;
    }

    if (image_script == false) {
        error("Build failed because no known image script")
    } else {
        echo "Running build script ${image_script} for type ${image_type}"
        sh(
            script: """#!/bin/bash
            export CLOUDS=\$(scripts/release_clouds.sh \$ENVIRONMENT)
            export FORCE_BUILD_IMAGE=true
            export ANSIBLE_FORCE_COLOR=True
            scripts/${image_script} ubuntu
            if [ \$? -eq 0 ]; then
                echo "Image creation successful"
            else
                echo "Failed to create image, skipping replication"
                exit 2
            fi"""
        )
    }
}

// use incoming branch/tag or tag repo with new tag based on build ID
def TagRelease(type,release,env_branch) {
    def tag_branch
    if (!env_branch) {
        sshagent (credentials: ['video-infra']) {        
            tag_branch = ApplyReleaseTagRelease(type,release)
            dir('infra-configuration') {
                ApplyReleaseTagRelease(type,release)
            }
            dir('infra-customization') {
                ApplyReleaseTagRelease(type,release)
            }
        }
    } else {
        tag_branch = env_branch
    }
    return tag_branch
}

// apply specific release tag to branch
def ApplyReleaseTagRelease(type,release) {
    git_branch = "${type}-${release}"
    sh 'git tag ' + git_branch
    sh 'git push origin '+git_branch
    return git_branch
}

def ReconfigureEnvironment(hcv_environment, video_infra_branch) {
    def result = build job: 'reconfigure-autoscaler-environment',wait: true,parameters: [
        [$class: 'StringParameterValue', name: 'ENVIRONMENT', value: hcv_environment],
        [$class: 'StringParameterValue', name: 'VIDEO_INFRA_BRANCH', value: video_infra_branch]
    ]
    return result
}

def ReconfigureHAProxy(environment, video_infra_branch) {
    def result = build job: 'reconfigure-haproxy',parameters: [
        [$class: 'StringParameterValue', name: 'ENVIRONMENT', value: environment],
        [$class: 'StringParameterValue', name: 'VIDEO_INFRA_BRANCH', value: video_infra_branch]
    ]
    return result
}

def SetupSSH() {
    withCredentials([
        sshUserPrivateKey(credentialsId: 'ssh-ubuntu', keyFileVariable: 'USER_PRIVATE_KEY_PATH', usernameVariable: 'SSH_USERNAME')
    ]) {
        sh '''#!/bin/bash
        export USER_PUBLIC_KEY_PATH=~/.ssh/ssh_key.pub
        ssh-keygen -y -f "$USER_PRIVATE_KEY_PATH" > "$USER_PUBLIC_KEY_PATH"'''
        env.SSH_USERNAME=SSH_USERNAME
    }
    env.USER_PUBLIC_KEY_PATH='~/.ssh/ssh_key.pub'
}

def GetShardBase(hcv_environment) {
    def shard_base = GetEnvironmentVar(hcv_environment,'SHARD_BASE')
    if (shard_base == "false") {
        return hcv_environment
    } else {
        return shard_base
    }
    return hcv_environment
}

def GetEnvironmentVar(hcv_environment,var_name) {
    def ret = 'false';

    def environmentVal = sh(
       returnStdout: true,
       script: """#!/bin/bash
. ./sites/${hcv_environment}/stack-env.sh
echo \$${var_name}"""
    ).trim();

    if (environmentVal.length() > 0) {
        ret = environmentVal;
    }

    return ret;
}

def GetAnsibleVar(hcv_environment,var_name) {
    def ret = 'false';

    def ansibleVal = sh(
       returnStdout: true,
       script: """#!/bin/bash
CHECK_VAR="\$(yq '.${var_name}' < ./sites/${hcv_environment}/vars.yml)"
echo \$CHECK_VAR"""
    ).trim();

    if (ansibleVal.length() > 0) {
        ret = ansibleVal;
    }

    return ret;
}

// get the shape of the jigasi image via JIGASI_SHAPE variable
def JigasiShapeFromEnvironment(environment) {
    dir('infra-provisioning') {
        def shape = sh(
        returnStdout: true,
        script: """#!/bin/bash
. ./clouds/oracle.sh
. ./sites/${environment}/stack-env.sh
if [ -z "\$JIGASI_SHAPE" ]; then
    echo \$SHAPE_A_1
else
    echo \$JIGASI_SHAPE
fi
""").trim();
        return shape
    }        
}

def ImageArchFromShape(shape) {
    dir('infra-provisioning') {
        def arch = sh(
        returnStdout: true,
        script: """#!/bin/bash
. ./clouds/oracle.sh
arch_from_shape ${shape}
echo \$IMAGE_ARCH"""
        ).trim();
        return arch
    }
}

// get the shape of the signal image via DEFAULT_SIGNAL_SHAPE variable
def SignalShapeFromEnvironment(environment) {
    dir('infra-provisioning') {
        def shape = sh(
        returnStdout: true,
        script: """#!/bin/bash
. ./clouds/oracle.sh
. ./sites/${environment}/stack-env.sh
if [ -z "\$DEFAULT_SIGNAL_SHAPE" ]; then
    echo \$SHAPE_A_1
else
    echo \$DEFAULT_SIGNAL_SHAPE
fi
""").trim();
        return shape
    }        
}

// get the shape of the JVB image via ENABLE_A_1 variable
def JVBShapeFromEnvironment(environment) {
    dir('infra-provisioning') {
        def shape = sh(
        returnStdout: true,
        script: """#!/bin/bash
. ./clouds/oracle.sh
. ./sites/${environment}/stack-env.sh
if [ "\$ENABLE_A_2" == "true" ]; then
    echo \$SHAPE_A_2
elif [ "\$ENABLE_A_1" == "true" ]; then
    echo \$SHAPE_A_1
else
    echo \$JVB_SHAPE
fi
""").trim();
        return shape
    }        
}

def OracleRegionFromCloud(cloud) {
        def region = sh(
        returnStdout: true,
        script: """#!/bin/bash
. ./clouds/${cloud}.sh
echo \$ORACLE_REGION"""
        ).trim();
        return region

}

return this