#!/bin/bash

################################################################################
########              Stratio Inc. All Rights Reserved                  ########
########         author: Carlos Gomez <carlos.gomez@stratio.com>        ########
################################################################################

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#@@@@    Note all this functions expects the following vars as globals   @@@@@@@
#@@@@        - VAULT_HOSTS [array]                                       @@@@@@@
#@@@@        - VAULT_PORT  [int]                                         @@@@@@@
#@@@@        - VAULT_TOKEN [string]                                      @@@@@@@
#@@@@                                                                    @@@@@@@
#@@@@      To read an array from comma separted string                   @@@@@@@
#@@@@          IFS=',' read -r -a VAULT_HOSTS <<< "$STRING_VAULT_HOST"   @@@@@@@
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#
# Get secret
#     INPUTS:
#          1: cluster [ca-trust, gosec, dcs, userland]
#          2: instance
#          3: secret
#     OUTPUTS:
#          populate ENV VARS as <$INSTANCE>_<$SECRET>_<JSON_KEY>=VALUE
#
function getPass() {
    local cluster=$1
    local instance=$2
    local secret=$3
    local rawdata=''
    local data=''
    local key=''
    local value=''
    declare -A secret_map

    OLD_IFS=$IFS
    result=$(_get_from_vault "/$cluster/passwords/$instance/$secret")
    IFS=',' read -r status_code rawdata <<< "$result"
    if [[ $status_code == 200 ]];
    then
        data=$(echo "$rawdata" | jq -cMSr '.data')
        while IFS='=' read -r key value
        do
            secret_map[$key]="$value"
        done < <(echo "$data" | jq -r "to_entries|map(\"\(.key)=\(.value)\")|.[]")

        underscore_instance=${instance//-/_}
        underscore_secret=${secret//-/_}
        for key in "${!secret_map[@]}"
        do
            underscore_key=${key//-/_}
            export "${underscore_instance^^}"_"${underscore_secret^^}"_"${underscore_key^^}"="${secret_map[$key]}"
            _log "<< getpass - $instance $secret obtained succesfully"
        done
    else
        _log "<< getpass - error -1 requesting $instance $secret"
    fi

    IFS=$OLD_IFS
    return 0
}

#
# Get principal and b64 encoded keytab
#     INPUTS:
#          1 cluster
#          2 instance
#          3 fqdn
#          4 path to save file(s) $fqdn.keytab
#          5 variable to store principal
#     OUTPUTS:
#          1 STDOUT << 0 if everything was ok
#            STDOUT << error code or HTTP status code if there was an error
#          2 $4/$3.keytab
#
function getKrb() {
    local cluster=$1
    local instance=$2
    local fqdn=$3
    local store_path=$4
    declare -n principal=$5
    local krb_credentials=''
    local encoded_ktab=''

    #TODO: extract principal(s) from keytab
    vault_path=$cluster/kerberos/$instance

    # ensure $store_path exists
    mkdir -p "$store_path"
    OLD_IFS=$IFS

    result=$(_get_from_vault "${vault_path}")
    IFS=',' read -r status_code krb_credentials <<< "$result"
    if [[ $status_code == 200 ]]; then
        json_princ_key="$fqdn"_principal
        json_ktab_key="$fqdn"_keytab
        principal=$(echo "$krb_credentials" | jq -cMSr --arg fqdn "$json_princ_key" '.data[$fqdn]')
        encoded_ktab=$(echo "$krb_credentials" | jq -cMSr --arg fqdn "$json_ktab_key" '.data[$fqdn]')
        _log "<< getkrb - credentials to $fqdn downloaded"

        echo "$encoded_ktab" | base64 -d > "$store_path/$fqdn.keytab"
        if [[ $? == 0 ]]; then
            _log ">> getkrb - keytab saved to $principal in $store_path"
        else
            _log ">> getkrb - error 1 saving keytab to $store_path"
            return 1
        fi
    else
        _log "<< getkrb - error $status_code downloading kerberos credentials to $fqdn"
        return "$status_code"
    fi

    IFS=$OLD_IFS
    return 0
}

#
# Get public certificate and private key
#     INPUTS:
#          1 cluster
#          2 instance
#          3 fqdn
#          4 ca-boundle format: JKS or P12 or PEM
#          5 path to save file(s) $fqdn.{jks|p12|pem.key}
#     OUTPUTS:
#          1 STDOUT << 0 if everything was ok
#            STDOUT << error code or HTTP status code if there was an error
#          2 $5/$3.{jks|p12|pem.key}
#
function getCert() {
    local cluster=$1
    local instance=$2
    local fqdn=$3
    local o_format=$4
    local store_path=$5
    local result=''
    local certificates=''
    local public_key=''
    local private_key=''
    local temp_pem_pub=''
    local temp_pem_priv=''
    local status_code=''

    vault_path=$cluster/certificates/$instance

    temp_pem_pub=$(mktemp -p /dev/shm)
    temp_pem_priv=$(mktemp -p /dev/shm)

    # ensure $store_path exists
    mkdir -p "$store_path"

    OLD_IFS=$IFS

    result=$(_get_from_vault "${vault_path}")
    IFS=',' read -r status_code certificates <<< "$result"
    if [[ "$status_code" == 200 ]]; then
        json_crt_key="$fqdn"_crt
        json_key_key="$fqdn"_key
        public_key=$(echo "$certificates" | jq -cMSr --arg fqdn "$json_crt_key" '.data[$fqdn]')
        private_key=$(echo "$certificates" | jq -cMSr --arg fqdn "$json_key_key" '.data[$fqdn]')
        echo "$public_key" | sed \
            -e 's/-----BEGIN CERTIFICATE-----/-----BEGIN CERTIFICATE-----\n/g' \
            -e 's/-----END CERTIFICATE-----/\n-----END CERTIFICATE-----/g' \
            -e 's/-----END CERTIFICATE----------BEGIN CERTIFICATE-----/-----END CERTIFICATE-----\n-----BEGIN CERTIFICATE-----/g'> "$temp_pem_pub"
        if [[ $? == 0 ]]; then
            _log ">> getcertificate - public key $fqdn downloaded"
        else
            _log ">> getcertificate - error 2 while $fqdn was downloaded"
            rm -rf "$temp_pem_pub" \
            rm -rf "$temp_pem_priv" \
            return 2
        fi

        echo "$private_key" | sed \
            -e 's/-----BEGIN RSA PRIVATE KEY-----/-----BEGIN RSA PRIVATE KEY-----\n/g' \
            -e 's/-----END RSA PRIVATE KEY-----/\n-----END RSA PRIVATE KEY-----/g' > "$temp_pem_priv"
        if [[ $? == 0 ]]; then
            _log ">> getcertificate - private key $fqdn downloaded"
        else
            _log ">> getcertificate - error 3 while $fqdn was downloaded"
            rm -rf "$temp_pem_pub" \
            rm -rf "$temp_pem_priv" \
            return 3
        fi

        case $o_format in
            PEM)
                cp -f "$temp_pem_pub" "$store_path/$fqdn.pem"
                cp -f "$temp_pem_priv" "$store_path/$fqdn.key"
                ;;
            P12|JKS)
                p12_temp=$(mktemp -p /dev/shm)
                getPass "$cluster" "$instance" keystore
                ptr_password="${instance^^}_KEYSTORE_PASS"

                openssl pkcs12 -export \
                    -inkey "$temp_pem_priv" \
                    -in "$temp_pem_pub" \
                    -passout pass:"${!ptr_password}" \
                    -out "$p12_temp"
                if [[ $? == 0 ]]; then
                    _log ">> getcertificate - P12 created"
                else
                    _log ">> getcertificate - error 4 creating P12"
                    rm -rf "$p12_temp"
                    rm -rf "$temp_pem_pub"
                    rm -rf "$temp_pem_priv"
                    return 4
                fi

                if [ "$o_format" == "P12" ]; then
                    cp "$p12_temp" "$store_path/$fqdn.p12"
                else
                    keytool -noprompt -importkeystore -srckeystore "$p12_temp" \
                           -srcstorepass "${!ptr_password}" \
                           -srcstoretype PKCS12 \
                           -destkeystore "$store_path/$fqdn.jks" \
                           -deststorepass "${!ptr_password}" 2>/dev/null
                    if [[ $? == 0 ]]; then
                        _log ">> getcertificate - JKS created"
                    else
                        _log ">> getcertificate - error 5 creating JKS"
                        rm -rf "$p12_temp"
                        rm -rf "$temp_pem_pub"
                        rm -rf "$temp_pem_priv"
                        return 5
                    fi
                fi
                rm -rf "$p12_temp"
                ;;
            *)
                _log "<< getcertificate - error 6 Invalid keystore format"
                return 6
        esac

    fi

    rm -rf "$temp_pem_pub"
    rm -rf "$temp_pem_priv"
    IFS=$OLD_IFS
    return 0
}


#
# Get CA public certificates
#     INPUTS:
#          1 path to directory to save ca-bundle.{pem,jks}
#          2 ca-bundle format: JKS or PEM
#          3 optional file to store ca-bundle
#          4 optional cluster to find keystore password
#          5 optional instance to find keystore password
#     OUTPUTS:
#          1 STDOUT << 0 if everything was ok
#          STDOUT << HTTP status code if there was an error
#
function getCAbundle() {
    local store_path=$1
    local format=$2
    local bundle_file=${3:-"ca-bundle"}
    local cluster=${4:-"ca-trust"}
    local instance=${5:-"default"}
    declare -a list_ca
    #local kstore_pass=''
    local result=''
    local status_code=''

    #TODO[xd-mail 20161212]: get password from vault passwords
    #TODO[xd-mail 20161212]: add keystore filename as parameter

    # get CAs list from ca-trust/certificates
    # for each ca append to $store_path/ca-bundle.pem
    # if format = jks
    #   add CA to JKS
    # return with exit code

    # ensure $store_path exists
    mkdir -p "$store_path"

    OLD_IFS=$IFS

    result=$(_get_from_vault "ca-trust/certificates?list=true")
    IFS=',' read -r status_code list <<< "$result"
    if [[ $status_code == 200 ]]; then
        IFS=',' read -r -a list_ca <<< "$(echo "$list" | jq -cMSr '.data .keys' | tr -d '[' |tr -d ']' | tr -d '"')"

        temp_pem=$(mktemp -p /dev/shm)
        formated_pem=$(mktemp -p /dev/shm)
        for ca in "${list_ca[@]}";
        do
            result=$(_get_from_vault ca-trust/certificates/"$ca")
            IFS=',' read -r status_code ca_pub_key <<< "$result"
            if [[ $status_code == 200 ]]; then
                echo "$ca_pub_key" | jq -cMSr ".data .${ca}_crt" > "$temp_pem"
                sed 's/-----BEGIN CERTIFICATE-----/-----BEGIN CERTIFICATE-----\n/g' "$temp_pem" \
                  | sed 's/-----END CERTIFICATE-----/\n-----END CERTIFICATE-----/g' > "$formated_pem"
                if [[ "$format" == "PEM" ]]; then
                    if [ "$bundle_file" == "ca-bundle" ]
                    then
                        bundle_file=${bundle_file}.pem
                    fi
                    cat "$formated_pem" >> "$store_path/$bundle_file"
                    if [[ $? == 0 ]]; then
                      _log ">> getcabundle - $ca saved to $store_path/$bundle_file"
                    else
                      _log ">> getcabundle - error 252 while saving $ca to $store_path/$bundle_file"
                      return 252
                    fi

                elif [[ "$format" == "JKS" ]]; then
                    if [ "$bundle_file" == "ca-bundle" ]
                    then
                        bundle_file=${bundle_file}.jks
                    fi
                    getPass "$cluster" "$instance" keystore
                    ptr_password="${instance^^}_KEYSTORE_PASS"
                    keytool -import -noprompt -alias "$ca" -keystore "$store_path/$bundle_file" \
                        -storepass "${!ptr_password}" -file "$formated_pem" >/dev/null 2>&1
                    if [[ $? == 0 ]]; then
                        _log ">> getcabundle - $ca saved to $store_path/$bundle_file"
                    else
                        _log ">> getcabundle - error 3 while saving $ca to $store_path/$bundle_file"
                        return 3
                    fi
                fi

                > "$formated_pem"
                > "$temp_pem"
            else
                _log "<< getcabundle - error 2 requesting $ca"
                rm -f "$temp_pem"
                rm -f "$formated_pem"
                echo 2
                return 2
            fi
        done

        rm -f "$temp_pem"
        rm -f "$formated_pem"
        return 0
    else
        _log "<< getcabundle - error 1 requesting CA list from /ca-trust/certificates"
        echo 1
        return 1
    fi
    IFS=$OLD_IFS
    return 0
}


#
# Send a HTTP GET method to vault server
#     INPUTS:
#          vault's path
#     OUTPUTS:
#          STDOUT << http_code,data
#
function _get_from_vault() {
    local path=$1
    local vault_hosts=$VAULT_HOSTS
    local vault_port=$VAULT_PORT
    local vault_token=$VAULT_TOKEN
    local response=''
    local data=''
    local status_code=-1
    local curl_opts="-fLs --tlsv1.2 -k"
    #local curl_opts='-sLf'

    for Vhost in "${vault_hosts[@]}"
        do
            response=$(curl $curl_opts -w "%{response_code}" -H "X-Vault-Token:$vault_token" \
                "https://$Vhost:$vault_port/v1/$path")
            data=$(echo "$response" |head -1 )
            status_code=$(echo "$response" | tail -1)
            if [[ $status_code == 200 ]];then
                echo "$status_code,$data"
                return 0
            fi
        done
        echo "$status_code, error getting data from $path"
        return 1
}


#
# Change key's value to file
#     INPUTS:
#          1 configuration key
#          2 configuration value
#          3 configuration file
#     OUTPUTS:
#
# Supported key formats:
#     key1=<value>  | key2 = <value> | key3:<value> | key4: <value> | "key5": "<value>" | "key6": "<value>",
#
function key_substitution() {
    local key=$1
    local value=$2
    local file=$3

    sed -ri "s#(\"|)($key)(\s|\"|)(=|:)(\s|)(\"|)(\w+)(\"|)(,|\s|)#\1\2\3\4\5\6$value\8\9#g" "$file"
    if [[ $? == 0 ]]; then
        _log "key_substitution - $key configured in $file"
    else
        _log "key_substitution - error 1 something went wrong when $key was configured in $file"
        return 1
    fi
    return 0
}

function _log() {
    local message=$1

    if [[ "$JOURNAL_LOG" == "true" ]]; then
        echo "$(date +'%b %d %R:%S.%N') $message" | systemd-cat -t vault
    else
        echo -e "$(date +'%b %d %R:%S.%N') [vault-utils] $message\n" | tee -a "$PWD/vault-utils.log"
    fi
}

#if [[ $(systemd-cat 1>&2 2>/dev/null && echo $?) -eq 0 ]]; then
#    JOURNAL_LOG=false
#fi
JOURNAL_LOG=false
