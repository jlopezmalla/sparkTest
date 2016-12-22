FROM fedora:25
MAINTAINER stratio<support@stratio.com>

# https://github.com/Yelp/dumb-init
RUN yum -y update \
    && yum -y upgrade \
    && yum -y install java-1.8.0-openjdk tar curl wget jq krb5-workstation krb5-libs krb5-auth-dialog\
    && yum -y clean all

RUN wget -O /usr/local/bin/dumb-init https://github.com/Yelp/dumb-init/releases/download/v1.2.0/dumb-init_1.2.0_amd64 && chmod +x /usr/local/bin/dumb-init

COPY spark-1.6.2-bin-mesos-env/ /opt/sds/spark

COPY kms_utils.sh /usr/bin/local/

COPY testing.jar /root/testing.jar

COPY entrypoint.sh /

ENTRYPOINT ["/usr/local/bin/dumb-init", "/entrypoint.sh"]

CMD [""]
