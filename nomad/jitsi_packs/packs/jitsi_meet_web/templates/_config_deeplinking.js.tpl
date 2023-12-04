[[ define "config_deeplinking.js" -]]
config.deeplinking={
    "desktop": {
      "appName": "Jitsi Meet"
    },
    "hideLogo": false,
    "showImage": false,
    "ios": {
      "appName": "Jitsi Meet",
      "appScheme": "org.jitsi.meet",
      "dynamicLink": {
        "apn": "org.jitsi.meet",
        "appCode": "w2atb",
        "ibi": "com.atlassian.JitsiMeet.ios",
        "isi": "1165103905"
      },
      "downloadLink": "https://itunes.apple.com/us/app/jitsi-meet/id1165103905"
    },
    "android": {
      "appName": "Jitsi Meet",
      "appScheme": "org.jitsi.meet",
      "appPackage": "org.jitsi.meet",
      "fDroidUrl": "https://f-droid.org/en/packages/org.jitsi.meet/",
      "dynamicLink": {
        "apn": "org.jitsi.meet",
        "appCode": "w2atb",
        "ibi": "com.atlassian.JitsiMeet.ios",
        "isi": "1165103905"
      },
      "downloadLink": "https://play.google.com/store/apps/details?id=org.jitsi.meet"
    }
};

[[ end -]]