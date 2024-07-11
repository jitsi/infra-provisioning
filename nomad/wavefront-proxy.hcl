variable "dc" {
  type = string
}
variable "wavefront_instance" {
  type = string
  default = "metrics"
}
variable "wavefront_proxy_hostname" {
  type = string
}

job "[JOB_NAME]" {
  datacenters = [var.dc]
  type = "service"

  group "wavefront-proxy" {
    constraint {
      operator  = "distinct_hosts"
      value     = "true"
    }

    constraint {
      attribute  = "${meta.pool_type}"
      value     = "general"
    }

    count = 2
    network {
      port "http" {
        to = 2878
      }
    }
    task "wavefront-proxy" {
      vault {
        change_mode = "noop"
        
      }
      service {
        name = "wavefront-proxy"
        tags = ["int-urlprefix-${var.wavefront_proxy_hostname}/","int-urlprefix-${var.wavefront_proxy_hostname}:443/"]

        port = "http"

        check {
          name     = "alive"
          type     = "http"
          path     = "/status"
          port     = "http"
          interval = "10s"
          timeout  = "2s"
        }
      }

      driver = "docker"
      env {
        WAVEFRONT_URL = "https://${var.wavefront_instance}.wavefront.com/api"
      }
      template {
        data = <<EOF
preprocessorConfigFile=/etc/wavefront/wavefront-proxy/preprocessor_rules.yaml
EOF
        destination = "local/wavefront.conf"
      }
      template {
        data = <<EOF
'2878'
# block all points with metricName that starts with loki
  ###############################################################
  - rule    : block-loki-stats
    action  : block
    scope   : metricName
    match   : "loki\\..*"
EOF
        destination = "local/preprocessor_rules.yaml"
      }
      template {
        data = <<EOF
WAVEFRONT_TOKEN="{{ with secret "secret/default/wavefront-proxy/token" }}{{ .Data.data.api_token }}{{ end }}"
EOF
        destination = "secrets/env"
        env = true
      }
      template {
        data = <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<Configuration status="INFO" monitorInterval="5">
    <Properties>
        <Property name="log-path">/var/log/wavefront</Property>
    </Properties>
    <Appenders>
        <Console name="Console" target="SYSTEM_OUT">
            <PatternLayout>
                <!-- Use the pattern below to output log in the same format as older versions
                <pattern>%d{MMM d, yyyy h:mm:ss a} %C{10} %M%n%p{WARN=WARNING, DEBUG=FINE, ERROR=SEVERE}: %m%n</pattern>
                -->
                <pattern>%d %-5level [%c{1}:%M] %m%n</pattern>
            </PatternLayout>
        </Console>
        <!-- Uncomment the RollingFile section below to log blocked points to a file -->
        <RollingFile name="BlockedPointsFile" fileName="${log-path}/wavefront-blocked-points.log"
                     filePattern="${log-path}/wavefront-blocked-points-%d{yyyy-MM-dd}-%i.log" >
            <PatternLayout>
                <pattern>%m%n</pattern>
            </PatternLayout>
            <Policies>
                <TimeBasedTriggeringPolicy interval="1"/>
                <SizeBasedTriggeringPolicy size="100 MB"/>
            </Policies>
            <DefaultRolloverStrategy max="10">
                <Delete basePath="/var/log/wavefront" maxDepth="1">
                    <IfFileName glob="wavefront-blocked*.log" />
                    <IfLastModified age="31d" />
                </Delete>
            </DefaultRolloverStrategy>
        </RollingFile>
        <!-- Uncomment the RollingFile section below to log all valid points to a file -->
        <RollingFile name="ValidPointsFile" fileName="${log-path}/wavefront-valid-points.log"
                     filePattern="${log-path}/wavefront-valid-points-%d{yyyy-MM-dd}-%i.log" >
            <PatternLayout>
                <pattern>%m%n</pattern>
            </PatternLayout>
            <Policies>
                <TimeBasedTriggeringPolicy interval="1"/>
                <SizeBasedTriggeringPolicy size="1024 MB"/>
            </Policies>
            <DefaultRolloverStrategy max="10">
                <Delete basePath="/var/log/wavefront" maxDepth="1">
                    <IfFileName glob="wavefront-valid*.log" />
                    <IfLastModified age="7d" />
                </Delete>
            </DefaultRolloverStrategy>
        </RollingFile>
    </Appenders>
    <Loggers>
        <!-- Uncomment AppenderRef to log blocked points to a file.
             Logger property level="WARN" logs only rejected points, level="INFO"
             logs points filtered out by allow/block rules as well -->
        <AsyncLogger name="RawBlockedPoints" level="WARN" additivity="false">
            <AppenderRef ref="BlockedPointsFile"/>
        </AsyncLogger>
        <!-- Uncomment AppenderRef and set level="ALL" to log all valid points to a file -->
        <AsyncLogger name="RawValidPoints" level="ALL" additivity="false">
            <AppenderRef ref="ValidPointsFile"/>
        </AsyncLogger>
        <Root level="INFO">
            <AppenderRef ref="Console" />
        </Root>
    </Loggers>
</Configuration>
EOF
        destination = "local/log4j2.xml"
      }
      config {
        image = "wavefronthq/proxy:latest"
        ports = ["http"]
        volumes = [
          "local/wavefront.conf:/etc/wavefront/wavefront-proxy/wavefront.conf",
          "local/preprocessor_rules.yaml:/etc/wavefront/wavefront-proxy/preprocessor_rules.yaml",
          "local/log4j2.xml:/etc/wavefront/wavefront-proxy/log4j2.xml"
        ]
      }

      resources {
        cpu    = 512
        memory = 1024
      }
    }
  }
}
