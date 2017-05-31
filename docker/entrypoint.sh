#!/bin/bash

set -e

# find the java heap size as 50% of container memory using sysfs
max_heap=`cat /sys/fs/cgroup/memory/memory.limit_in_bytes | xargs -I{} echo "({} / 1024 / 1024) / 2" | bc`
export JAVA_OPTS="${JAVA_OPTS} -Xmx${max_heap}m"

# Set basic java options
export JAVA_OPTS="${JAVA_OPTS} -Djava.security.egd=file:/dev/./urandom"

# Load agent support if required
source ./agents/newrelic.sh

# open the secrets
hs256_key=`cat /var/run/secrets/hs256-key/key`
JAVA_OPTS="${JAVA_OPTS} \
-Djwt.sharedSecret=${hs256_key}"

mysql_uri=`cat /var/run/secrets/binding-refarch-compose-for-mysql/binding | jq '.uri' | sed -e 's/"//g'`

# rip apart the uri, the format is mysql://<user>:<password>@<host>:<port>/<db_name>
mysql_user=`echo ${mysql_uri} | sed -e 's|mysql://\([^:]*\):.*|\1|'`
mysql_password=`echo ${mysql_uri} | sed -e 's|mysql://[^:]*:\([^@]*\)@.*|\1|'`
mysql_host=`echo ${mysql_uri} | sed -e 's|mysql://[^:]*:[^@]*@\([^:]*\):.*|\1|'`
mysql_port=`echo ${mysql_uri} | sed -e 's|mysql://[^:]*:[^@]*@[^:]*:\([^/]*\)/.*|\1|'`
mysql_db=`echo ${mysql_uri} | sed -e 's|mysql://[^:]*:[^@]*@[^:]*:[^/]*/\(.*\)|\1|'`

JAVA_OPTS="${JAVA_OPTS} \
-Dspring.datasource.url=jdbc:mysql://${mysql_host}:${mysql_port}/${mysql_db} \
-Dspring.datasource.username=${mysql_user} \
-Dspring.datasource.password=${mysql_password} \
-Dspring.datasource.port=${mysql_port}"

if [ -f /var/run/secrets/binding-refarch-messagehub/binding ]; then
    messagehub_creds=`cat /var/run/secrets/binding-refarch-messagehub/binding`
    kafka_username=`echo ${messagehub_creds} | jq '.user' | sed -e 's/"//g'`
    kafka_password=`echo ${messagehub_creds} | jq '.password' | sed -e 's/"//g'`
    kafka_brokerlist=`echo ${messagehub_creds} | jq '.kafka_brokers_sasl | join(" ")' | sed -e 's/"//g'`
    
    JAVA_OPTS="${JAVA_OPTS} \
-Dspring.application.messagehub.user=${kafka_username} \
-Dspring.application.messagehub.password=${kafka_password}"
    
    count=0
    for broker in ${kafka_brokerlist}; do
        JAVA_OPTS="${JAVA_OPTS} -Dspring.application.messagehub.kafka_brokers_sasl[${count}]=${broker}"
        count=$((count + 1))
    done
    
    kafka_apikey=`echo ${messagehub_creds} | jq '.api_key' | sed -e 's/"//g'`
    kafka_adminurl=`echo ${messagehub_creds} | jq '.kafka_admin_url' | sed -e 's/"//g'`
fi

# disable eureka
JAVA_OPTS="${JAVA_OPTS} -Deureka.client.enabled=false -Deureka.client.registerWithEureka=false -Deureka.fetchRegistry=false"

echo "Starting with Java Options ${JAVA_OPTS}"

# Start the application
exec java ${JAVA_OPTS} -jar /app.jar

