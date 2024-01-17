[[ define "config_deeplinking.js" -]]
config.deeplinking={
    "desktop": {
      "appName": "[[ or (env "CONFIG_jitsi_meet_desktop_app_name") "Jitsi Meet" ]]"
    },
    "hideLogo": [[ or (env "CONFIG_jitsi_meet__deeplink_hide_logo") "false" ]],
    "showImage": [[ or (env "CONFIG_jitsi_meet_deeplink_show_image") "false" ]],
    "ios": {
      "appName": "[[ or (env "CONFIG_jitsi_meet_mobile_app_name") "Jitsi Meet" ]]",
      "appScheme": "[[ or (env "CONFIG_jitsi_meet_app_scheme") "org.jitsi.meet" ]]",
[[ if ne (env "CONFIG_jitsi_meet_dynamic_linking") "false" -]]
      "dynamicLink": {
        "apn": "org.jitsi.meet",
        "appCode": "w2atb",
        "ibi": "com.atlassian.JitsiMeet.ios",
        "isi": "1165103905"
      },
[[ end ]]
      "downloadLink": "[[ or (env "CONFIG_jitsi_meet_ios_download_link") "https://itunes.apple.com/us/app/jitsi-meet/id1165103905" ]]"
    },
    "android": {
      "appName": "[[ or (env "CONFIG_jitsi_meet_mobile_app_name") "Jitsi Meet" ]]",
      "appScheme": "[[ or (env "CONFIG_jitsi_meet_app_scheme") "org.jitsi.meet" ]]",
      "appPackage": "[[ or (env "CONFIG_jitsi_meet_android_app_package") "org.jitsi.meet" ]]",
      "fDroidUrl": "[[ or (env "CONFIG_jitsi_meet_f_droid_url") "https://f-droid.org/en/packages/org.jitsi.meet/" ]]",
[[ if ne (env "CONFIG_jitsi_meet_dynamic_linking") "false" -]]
      "dynamicLink": {
        "apn": "org.jitsi.meet",
        "appCode": "w2atb",
        "ibi": "com.atlassian.JitsiMeet.ios",
        "isi": "1165103905"
      },
[[ end ]]
      "downloadLink": "[[ or (env "CONFIG_jitsi_meet_android_download_link") "https://play.google.com/store/apps/details?id=org.jitsi.meet" ]]"
    }
};

[[ end -]]