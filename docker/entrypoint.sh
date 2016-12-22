#!/bin/bash
# __version__ 0.1

###HDFS-KERBEROS CLIENT CONFIGURATION###
REALM=${REALM:=DEMO.STRATIO.COM}
KDC_HOST=${KDC_HOST:=kdc.stratio.com}
KADMIN_HOST=${KADMIN_HOST:=kadmin.stratio.com}

##SPARK SREVICE PROPERTIES##
SPARK_HOME=/opt/sds/spark/
SPARK_MASTER=mesos://zk://master.mesos:2181/mesos
SPARK_DOCKER=qa.stratio.com/stratio/spark-testing:0.1

###SPARK KERBEROS CONF WITH MESOS ###
SPARK_PRINCIPAL=${SPARK_PRINCIPAL:=stratio}
SPARK_KEYTAB=${SPARK_KEYTAB:=/root/stratio.keytab}
SPARK_USER=${SPARK_USER:=$SPARK_PRINCIPAL}
MESOS_NATIVE_JAVA_LIBRARY=/opt/mesosphere/lib/libmesos.so

###VAULT PROPERTIES
VAULT_PORT=${VAULT_PORT:=8200}
VAULT_TOKEN=${VAULT_TOKEN:=e20d9967-be69-7822-8464-a3e17622cffc}
KMS_CLUSTER=${KMS_CLUSTER:=userland}
KMS_INSTANCE=${KMS_INSTANCE:=performance-spark}
KMS_FQDN=${KMS_FQND=performance-spark}
VHOSTS=${VHOSTS:=gosec16.labs.stratio.com}
IFS=',' read -ra VAULT_HOSTS <<< "$VHOSTS"

###TESTING JOB VARIBLES
SPARK_JOB_ARGS=""
SPARK_JOB_OUTPUT_PATH=${SPARK_JOB_OUTPUT_PATH:="/tmp/output"}
SPARK_JOB_OUTPUT_FORMAT=${SPARK_JOB_OUTPUT_FORMAT:="com.databricks.spark.csv"}
SPARK_JOB_INPUT_PATH=${SPARK_JOB_INPUT_PATH:="/tpcds"}
SPARK_JOB_INPUT_FORMAT=${SPARK_JOB_INPUT_FORMAT:="parquet"}
SPARK_PACKAGES="--packages com.databricks:spark-csv_2.11:1.5.0"

###JOB TYPES
WRITE_INCLUDE=${WRITE_INCLUDE:=false}
SEC_ENABLE=${SEC_ENABLE:=false}
TEST_SINFO=${TEST_SINFO:=false}

function main() {

    source /usr/bin/local/kms_utils.sh

   generate_krb-conf $REALM $KDC_HOST $KADMIN_HOST
   ### OBTAIN SPARK_KEYTAB PROGRAMATICALY FROM STRATIO KMS ###
   getKrb $KMS_CLUSTER $KMS_INSTANCE $KMS_FQDN $SPARK_KEYTAB_PATH SPARK_PRINCIPAL

   SPARK_JOB_ARGS="$SPARK_JOB_INPUT_PATH $SPARK_JOB_INPUT_FORMAT "
   SPARK_JOB_MAIN_CLASS="com.stratio.spark.perfomance.testing.ReadTestingMain"

   if [[ $WRITE_INCLUDE == 'true' ]]; then
      SPARK_JOB_ARGS="$SPARK_JOB_ARGS $SPARK_JOB_OUTPUT_PATH $SPARK_JOB_OUTPUT_FORMAT"
      SPARK_JOB_MAIN_CLASS="com.stratio.spark.perfomance.testing.WritingTestingMain"
   fi

   if [[ $SEC_ENABLE == 'true' ]]; then
      SECURITY_ARGS="--principal $SPARK_PRINCIPAL --keytab $SPARK_KEYTAB_PATH/$KMS_FQDN.keytab"
   fi

   if [[ $TEST_SINFO == 'true' ]]; then
      SPARK_JOB_MAIN_CLASS="com.stratio.spark.perfomance.testing.SinfoTestingMain"
      SPARK_PACKAGES="--packages com.databricks:spark-csv_2.11:1.5.0"
      SPARK_JOB_ARGS="$SPARK_JOB_ARGS $SPARK_JOB_OUTPUT_PATH $SPARK_JOB_OUTPUT_FORMAT"
   fi      

  $SPARK_HOME/bin/spark-submit --master $SPARK_MASTER --class $SPARK_JOB_MAIN_CLASS $SPARK_PACKAGES --conf spark.mesos.executor.docker.image=$SPARK_DOCKER $SECURITY_ARGS /root/testing.jar $SPARK_JOB_ARGS
}

function make_directory() {
        local dir=$1
        local module=$2

        mkdir -p $dir \
        && echo "[$module] Created $dir directory" \
        || echo "[$module] Something was wrong creating $dir directory or already exists"
}

function generate_krb-conf () {
    local realm=$1
    local kdc_host=$2
    local kadmin_host=$3

    cat << EOF > /tmp/krb5.conf.tmp
[libdefaults]
 default_realm = __<REALM>__
 dns_lookup_realm = false
 udp_preference_limit = 1
[realms]
 __<REALM>__ = {
   kdc = __<KDC_HOST>__
   admin_server = __<KADMIN_HOST>__
   default_domain = __<LW_REALM>__
 }
[domain_realm]
 .__<LW_REALM>__ = __<REALM>__
 __<LW_REALM>__ = __<REALM>__
EOF

    lw_realm=$(echo $REALM | tr '[:upper:]' '[:lower:]')

    sed -i "s#__<REALM>__#$realm#" /tmp/krb5.conf.tmp \
    && echo "[KRB-CONF] Realm configured in krb5.conf" \
    || echo "[KRB-CONF] Something went wrong when REALM was configured in krb5.conf"

    sed -i "s#__<LW_REALM>__#$lw_realm#" /tmp/krb5.conf.tmp \
    && echo "[KRB-CONF] Domain configured in krb5.conf" \
    || echo "[KRB-CONF] Something went wrong when DOMAIN was configured in krb5.conf"

    sed -i "s#__<KDC_HOST>__#$kdc_host#" /tmp/krb5.conf.tmp \
    && echo "[KRB-CONF] kdc host configured in krb5.conf" \
    || echo "[KRB-CONF] Something went wrong when kdc host was configured in krb5.conf"

    sed -i "s#__<KADMIN_HOST>__#$kadmin_host#" /tmp/krb5.conf.tmp \
    && echo "[KRB-CONF] kadmin host configured in krb5.conf" \
    || echo "[KRB-CONF] Something went wrong when kadmin host was configured in krb5.conf"

    mv -f /tmp/krb5.conf.tmp /etc/krb5.conf
}

main
