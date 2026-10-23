variable "environment" {
  type = string
}

variable "dc" {
  type = string
}

variable "oracle_region" {
  type = string
}

variable "domain" {
  type = string
}

# tenant path segment appended to the domain for the conference URL
variable "tenant" {
  type    = string
  default = "70r7ur4"
}

variable "cloudprober_version" {
  type    = string
  default = "v0.14.2-pw"
}

variable "participants" {
  type    = string
  default = "3"
}

# how long the participants stay in the conference once established
variable "conference_duration_seconds" {
  type    = string
  default = "300"
}

job "[JOB_NAME]" {
  datacenters = [var.dc]
  type        = "service"
  # low priority: synthetic test job, never worth preempting real workloads
  priority    = 25

  meta {
    environment = "${var.environment}"
  }

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  group "cloudprober-synthetic" {
    count = 1

    constraint {
      attribute = "${meta.pool_type}"
      value     = "general"
    }

    restart {
      attempts = 3
      interval = "10m"
      delay    = "25s"
      mode     = "delay"
    }

    network {
      port "http" {
        to = 9313
      }
    }

    task "cloudprober" {
      shutdown_delay = "5s"

      vault {
        change_mode = "noop"
      }

      # registered under the same service name as the base cloudprober job so
      # the existing prometheus consul_sd scrape config picks it up; metrics
      # are distinguished by the probe label (probe="synthetic_conference")
      service {
        name = "cloudprober"
        tags = ["ip-${attr.unique.network.ip-address}", "synthetic"]
        port = "http"
        check {
          name     = "alive"
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }

      driver = "docker"

      config {
        image = "cloudprober/cloudprober:${var.cloudprober_version}"
        ports = ["http"]
        args  = ["--config_file=/local/cloudprober.cfg", "--logtostderr"]
      }

      template {
        destination = "secrets/asap-client.key"
        perms       = "600"
        data        = <<EOH
{{- with secret "secret/${var.environment}/asap/client" }}{{ .Data.data.private_key }}{{ end -}}
EOH
      }

      template {
        destination = "local/cloudprober.cfg"
        data        = <<EOH
surfacer {
  type: PROMETHEUS
  export_as_gauge: true
  prometheus_surfacer {
    metrics_prefix: "cloudprober_"
    # probe runs are long (minutes); without this, exported samples keep their
    # original timestamps and go stale in prometheus between runs
    include_timestamp: false
  }
}

# synthetic conference test: N headless participants join a conference through
# the public domain (Cloudflare ingress, same path as real users) and verify
# they stay connected and receive media for the configured duration
probe {
  name: "synthetic_conference"
  type: BROWSER
  targets {
    host_names: "${var.domain}"
  }
  browser_probe {
    test_dir: "/local/tests"
    test_spec: "conference.spec.js"
    save_trace: RETAIN_ON_FAILURE
    test_metrics_options {
      enable_step_metrics: true
    }
    env_var {
      key: "BASE_URL"
      value: "https://${var.domain}/${var.tenant}/"
    }
    env_var {
      key: "PARTICIPANTS"
      value: "${var.participants}"
    }
    env_var {
      key: "CONFERENCE_DURATION_SECONDS"
      value: "${var.conference_duration_seconds}"
    }
    env_var {
      key: "ROOM_PREFIX"
      value: "synthetic-${var.oracle_region}"
    }
    env_var {
      key: "ASAP_KEY_FILE"
      value: "/secrets/asap-client.key"
    }
    env_var {
      key: "ASAP_JWT_KID"
      value: "{{ with secret "secret/${var.environment}/asap/client" }}{{ .Data.data.key_id }}{{ end }}"
    }
  }
  interval_msec: 600000
  timeout_msec: 480000
  latency_unit: "ms"
  additional_label {
    key: "service"
    value: "jitsi"
  }
}
EOH
      }

      template {
        destination = "local/tests/conference.spec.js"
        change_mode = "restart"
        data        = <<EOH
const { test } = require('@playwright/test');
const { chromium } = require('@playwright/test');
const crypto = require('crypto');
const fs = require('fs');

const BASE_URL = process.env.BASE_URL;
const PARTICIPANTS = parseInt(process.env.PARTICIPANTS || '3', 10);
const DURATION_SEC = parseInt(process.env.CONFERENCE_DURATION_SECONDS || '300', 10);
const CHECK_INTERVAL_SEC = 10;
const JOIN_TIMEOUT_MS = 90000;
const ROOM_PREFIX = process.env.ROOM_PREFIX || 'synthetic';
const ASAP_KEY_FILE = process.env.ASAP_KEY_FILE;
const ASAP_JWT_KID = process.env.ASAP_JWT_KID;

function b64url(buf) {
  return Buffer.from(buf).toString('base64')
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

// ASAP client JWT, mirroring generate-client-token.sh (iss=jitsi, sub=*,
// moderator) but short-lived instead of 1 year
function makeJwt(displayName) {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT', kid: ASAP_JWT_KID };
  const payload = {
    iss: 'jitsi',
    aud: 'jitsi',
    sub: '*',
    room: '*',
    iat: now,
    nbf: now - 10,
    exp: now + 7200,
    context: { user: { moderator: true, name: displayName } },
  };
  const input = b64url(JSON.stringify(header)) + '.' + b64url(JSON.stringify(payload));
  const key = fs.readFileSync(ASAP_KEY_FILE);
  const sig = crypto.sign('RSA-SHA256', Buffer.from(input), key);
  return input + '.' + b64url(sig);
}

function joinUrl(room, displayName) {
  const hash = [
    'config.prejoinConfig.enabled=false',
    'config.requireDisplayName=false',
    'config.startWithAudioMuted=false',
    'config.startWithVideoMuted=false',
    'userInfo.displayName="' + displayName + '"',
  ].join('&');
  return BASE_URL + room + '?jwt=' + makeJwt(displayName) + '#' + hash;
}

function sleep(ms) {
  return new Promise(function (resolve) { setTimeout(resolve, ms); });
}

// equivalent of torture HeartbeatTask checks, evaluated in the page
function participantState() {
  const conf = window.APP && window.APP.conference;
  if (!conf) {
    return { loaded: false };
  }
  let download = 0;
  try {
    const stats = conf.getStats();
    if (stats && stats.bitrate) {
      download = stats.bitrate.download || 0;
    }
  } catch (e) { /* stats not ready */ }
  let xmpp = false;
  try {
    xmpp = !!(conf._room && conf._room.xmpp.connection.connected);
  } catch (e) { /* room not ready */ }
  return {
    loaded: true,
    joined: conf.isJoined(),
    ice: conf.getConnectionState() === 'connected',
    xmpp: xmpp,
    members: conf.listMembers().length,
    download: download,
  };
}

test('synthetic conference', async () => {
  test.setTimeout((DURATION_SEC + 240) * 1000);

  const room = ROOM_PREFIX + '-' + Date.now();
  // surface the active room for debugging/observers (see alloc exec)
  console.log('conference room: ' + room);
  try {
    fs.writeFileSync('/tmp/current-room.txt',
      new Date().toISOString() + ' ' + room + '\n', { flag: 'a' });
  } catch (e) { /* ignore */ }
  const browser = await chromium.launch({
    args: [
      '--use-fake-device-for-media-stream',
      '--use-fake-ui-for-media-stream',
      '--autoplay-policy=no-user-gesture-required',
      '--disable-dev-shm-usage',
      '--no-sandbox',
    ],
  });
  const pages = [];

  try {
    await test.step('join', async () => {
      for (let i = 0; i < PARTICIPANTS; i++) {
        const context = await browser.newContext();
        const page = await context.newPage();
        await page.goto(joinUrl(room, 'synthetic-p' + (i + 1)), { waitUntil: 'domcontentloaded' });
        pages.push(page);
      }
      for (let i = 0; i < pages.length; i++) {
        await pages[i].waitForFunction(
          'window.APP && APP.conference && APP.conference.isJoined()',
          null, { timeout: JOIN_TIMEOUT_MS });
        await pages[i].waitForFunction(
          'APP.conference.listMembers().length >= ' + (PARTICIPANTS - 1),
          null, { timeout: JOIN_TIMEOUT_MS });
      }
      // 8x8.vc sets disableInitialGUM=true server-side (not URL-overridable),
      // so participants join with no tracks; unmute explicitly to trigger GUM
      for (let i = 0; i < pages.length; i++) {
        await pages[i].evaluate(function () {
          try { window.APP.conference.muteAudio(false); } catch (e) { /* ignore */ }
          try { window.APP.conference.muteVideo(false); } catch (e) { /* ignore */ }
        });
      }
      for (let i = 0; i < pages.length; i++) {
        await pages[i].waitForFunction(
          "APP.store.getState()['features/base/tracks']" +
          '.filter(function (t) { return t.local; }).length >= 2',
          null, { timeout: 30000 });
      }
    });

    await test.step('heartbeat', async () => {
      // tolerate up to 3 consecutive zero-bitrate readings, like torture's
      // HeartbeatTask countdown latch
      const zeroBitrate = pages.map(function () { return 0; });
      const deadline = Date.now() + DURATION_SEC * 1000;
      while (Date.now() < deadline) {
        await sleep(CHECK_INTERVAL_SEC * 1000);
        for (let i = 0; i < pages.length; i++) {
          const who = 'participant' + (i + 1);
          const s = await pages[i].evaluate(participantState);
          if (!s.loaded) { throw new Error(who + ': jitsi-meet app is gone'); }
          if (!s.joined) { throw new Error(who + ' is not in the muc'); }
          if (!s.ice) { throw new Error(who + ' ice is not connected'); }
          if (!s.xmpp) { throw new Error(who + ' xmpp connection is not connected'); }
          if (s.members < PARTICIPANTS - 1) {
            throw new Error(who + ' sees ' + s.members + ' members, expected ' + (PARTICIPANTS - 1));
          }
          if (s.download <= 0) {
            zeroBitrate[i]++;
            if (zeroBitrate[i] >= 3) {
              throw new Error(who + ' download bitrate stayed at 0');
            }
          } else {
            zeroBitrate[i] = 0;
          }
        }
      }
    });

    await test.step('hangup', async () => {
      for (let i = 0; i < pages.length; i++) {
        try {
          await pages[i].evaluate('APP.conference.hangup()');
        } catch (e) { /* best effort */ }
      }
      await sleep(2000);
    });
  } finally {
    await browser.close();
  }
});
EOH
      }

      resources {
        cpu        = 4000
        memory     = 3072
        memory_max = 4096
      }
    }
  }
}
