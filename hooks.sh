#!/usr/bin/env bash

. hooks/dns-01-fortiadc/fortiadc.conf

# DO NOT CHANGE PARAMETERS BELOW

TOKEN_LOCK_FILE="token.lock"

CURL="/usr/bin/curl -s -f -m 5 -H 'Accept: application/json'"
CURL_LOGIN="$CURL -c $TOKEN_LOCK_FILE -k -X POST https://$FORTIADC/api"
CURL_GET="$CURL -b $TOKEN_LOCK_FILE -k -X GET https://$FORTIADC/api"
CURL_POST="$CURL -b $TOKEN_LOCK_FILE -k -X POST https://$FORTIADC/api"
CURL_DELETE="$CURL -b $TOKEN_LOCK_FILE -k -X DELETE https://$FORTIADC/api"

IS_VDOM=0
LOGGED=0
URL_VDOM=''

function login() {
    echo '   + login'
    local DATA='{"username":"'$USERNAME'","password":"'$PASSWORD'"}'
    local CMD=$CURL_LOGIN'/user/login -d '$DATA' || echo -1'
    if [ -1 == $(eval $CMD) ]; then 
        echo '     + connection error !'
        return
    fi
    LOGGED=1
}

function logout() {
    echo '   + logout'
    local CMD=$CURL_GET'/user/logout || echo -1' 
    if [ -1 == $(eval $CMD) ]; then 
        echo '     + connection error !'
        return
    fi
    rm token.lock
}


function get_vdom_list() {
    echo '  + get vdom list'
    local CMD=$CURL_GET'/vdom || echo -1'
    local EVAL=$($CMD)
    
    if [ -1 == $EVAL ]; then 
        echo '     + connection error !'
        return
    fi
    
    VDOMS=$(echo $EVAL | jq -r '.payload[] | { mkey: .mkey | select(. != null) } | @base64')
    
    if [ -z "$VDOMS" ]; then 
        echo '   + no vdom detected !'
        IS_VDOM=0
        return
    fi
    
    echo '   + vdom detected !'
    IS_VDOM=1
}


function global_dns_server_zone() {
    echo '     + extract zone records'
    local CMD=$CURL_GET'/global_dns_server_zone?'$URL_VDOM
    ZONES=$(eval $CMD | jq -r '.payload[] | { mkey: .mkey, domain_name: .domain_name | select(. != null) } | @base64')
}


function search_global_dns_server_zone() {
    echo '   + retrieving zone record for domain : '$DOMAIN
    
    global_dns_server_zone
    
    test -z "${ZONES}" && echo '     + no zones found' && return 1

    local SEARCH=$DOMAIN'.'
    
    for row in $ZONES; do
        DOMAIN_NAME=$(echo ${row} | base64 --decode | jq -r '.domain_name')
        if [[ $SEARCH == *"$DOMAIN_NAME"* ]] ; then
            MKEY=$(echo ${row} | base64 --decode | jq -r '.mkey')
            
            CLEAN_DOMAIN='_acme-challenge'
            test $(expr ${#SEARCH} - ${#DOMAIN_NAME} - 1) -ge 0 && CLEAN_DOMAIN=$CLEAN_DOMAIN'.'$(echo ${SEARCH:0:$(expr ${#SEARCH} - ${#DOMAIN_NAME} - 1)})
            
            echo '     + zone is '$MKEY
            echo '     + txt record is '$CLEAN_DOMAIN
            return
        fi
    done
    echo '     + no zone found '
}

function get_global_dns_server_zone_child_txt_record() {
    echo '     + retrieving TXT records for zone '$MKEY
    local CMD=$CURL_GET'/global_dns_server_zone_child_txt_record?'$URL_VDOM'pkey='$MKEY' || echo -1'
    TXT_RECORDS=$($CMD | jq -r '.payload[] | @base64')
}

function get_global_dns_server_zone_child_txt_record_idx() {
    echo '   + retrieving ID TXT record for '$CLEAN_DOMAIN
    
    get_global_dns_server_zone_child_txt_record
    
    test -z "${TXT_RECORDS}" && echo '     + no record found' && return 1
    
    for row in $TXT_RECORDS; do
        local NAME=$(echo ${row} | base64 --decode | jq -r '.name')
        if [[ $CLEAN_DOMAIN == $NAME ]] ; then
            IDX=$(echo ${row} | base64 --decode | jq -r '.mkey')
                
            echo '     + index record is '$IDX
            return
        fi
    done
}

function add_global_dns_server_zone_child_txt_record() {
    
    get_global_dns_server_zone_child_txt_record_idx $MKEY $CLEAN_DOMAIN
    test -n "${IDX}" && echo '     + txt entrie already exist : pass !' && return 1

    echo '   + add TXT record for '$DOMAIN
    
    IDX=$(date +%s)
    
    local DATA='{"mkey":"'$IDX'","name":"'$CLEAN_DOMAIN'","text":"'$TOKEN_VALUE'","ttl":"3600"}'
    local CMD=$CURL_POST'/global_dns_server_zone_child_txt_record?'$URL_VDOM'pkey='$MKEY' -d '$DATA' || echo -1'
    local EVAL=$($CMD)
    
    if [ -1 == $EVAL ]; then 
        echo '     + connection error !'
        return
    fi
    
    if [[ $(echo $EVAL | jq -r '.payload') == 0 ]] ; then
        echo '     + success !'
        return
    fi
    
    echo '     + something wrong append'
}

function del_global_dns_server_zone_child_txt_record() {
    
    get_global_dns_server_zone_child_txt_record_idx $MKEY $CLEAN_DOMAIN
    test -z "${IDX}" && echo '   + no txt record found for this domain' && return 1
    
    echo '   + delete TXT record for '$DOMAIN
    
    local CMD=$CURL_DELETE'/global_dns_server_zone_child_txt_record/'$IDX'?'$URL_VDOM'pkey='$MKEY' || echo -1'
    local EVAL=$($CMD)
    
    if [ -1 == $EVAL ]; then 
        echo '     + connection error !'
        return
    fi
    
    if [[ $(echo $EVAL | jq -r '.payload') == 0 ]] ; then
        echo '     + success !'
        return
    fi
    
    echo '     + something wrong append'
}

function verif_challenge_live() {
    echo '   + verify txt resolution '
    echo -n ''
    for nameserver in $(dig $DOMAIN_NAME NS +short); do 
        echo -n '     + with '$nameserver' '
        CMD="dig _acme-challenge.$DOMAIN TXT @$nameserver +short"
        nsresult=$($CMD)
        # nsresult comes with the TXT RR in double quotes - remove those
        nsresult=${nsresult//$'"'/''}
        until [[ "$nsresult" = "$TOKEN_VALUE" ]]; do
            echo -n '.'
            sleep 1
            echo -n '.'
            sleep 1
            echo -n '.'
            sleep 1
            echo -n '.'
            sleep 1
            echo -n '.'
            nsresult=$($CMD)
            # nsresult comes with the TXT RR in double quotes - remove those
            # TODO DRY: move to dedicated function
            nsresult=${nsresult//$'"'/''}
        done
        echo -n "good"
        echo ''
    done
}

function add_cert() {
    local  DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" VDOM="${4}" 

    echo '   + add certificate using expect script'
    
    test -z "${VDOM}" && VDOM=-1
    
    DOMAIN=$(echo $DOMAIN | sed -e "s/\./-/g")
    DOMAIN=$(echo $DOMAIN | sed -e "s/_/-/g")
    
    ./hooks/dns-01-fortiadc/expect.sh $DOMAIN $KEYFILE $CERTFILE $VDOM $FORTIADC $USERNAME $PASSWORD 

}

function deploy_challenge() {
    local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}"
    
    # validated, including any alternative names you may have listed.
    #
    # Parameters:
    # - DOMAIN
    #   The domain name (CN or subject alternative name) being
    #   validated.
    # - TOKEN_FILENAME
    #   The name of the file containing the token to be served for HTTP
    #   validation. Should be served by your web server as
    #   /.well-known/acme-challenge/${TOKEN_FILENAME}.
    # - TOKEN_VALUE
    #   The token value that needs to be served for validation. For DNS
    #   validation, this is what you want to put in the _acme-challenge
    #   TXT record. For HTTP validation it is the value that is expected
    #   be found in the $TOKEN_FILENAME file.

    echo ' + fortiadc hook executing: deploy_challenge'
    
    test -z "${DOMAIN}" && echo ' + empty domain' && return 1
    test -z "${TOKEN_VALUE}" && echo ' + empty token' && return 1

    login
    
    if [[ $LOGGED == 1 ]] ; then
    
        get_vdom_list
        
        if [[ $IS_VDOM == 1 ]] ; then
            for row in $VDOMS; do
                local VDOM_NAME=$(echo ${row} | base64 --decode | jq -r '.mkey')
                URL_VDOM='vdom='$VDOM_NAME'&'
                echo '   +++++++++++++++++++++++++++'
                echo '   + enter vdom "'$VDOM_NAME'"'
                search_global_dns_server_zone
                test -z "${ZONES}" && echo '   + no zone found for this domain on this vdom' && echo '   + leave vdom "'$VDOM_NAME'"' && continue
                add_global_dns_server_zone_child_txt_record
                echo '   + leave vdom "'$VDOM_NAME'"'
            done
        else
            search_global_dns_server_zone
            test -z "${ZONES}" && echo '   + no zone found for this domain'
            test "${ZONES}" && add_global_dns_server_zone_child_txt_record
        fi
        
        logout    
        verif_challenge_live
    fi
}

function clean_challenge() {
    local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}"

    # This hook is called after attempting to validate each domain,
    # whether or not validation was successful. Here you can delete
    # files or DNS records that are no longer needed.
    #
    # The parameters are the same as for deploy_challenge.

    echo ' + fortiadc hook executing: clean_challenge'
    
    test -z "${DOMAIN}" && echo ' + empty domain' && return 1
    test -z "${TOKEN_VALUE}" && echo ' + empty token' && return 1
    
    login
    if [[ $LOGGED == 1 ]] ; then
        get_vdom_list
        
        if [[ $IS_VDOM == 1 ]] ; then
            for row in $VDOMS; do
                local VDOM_NAME=$(echo ${row} | base64 --decode | jq -r '.mkey')
                URL_VDOM='vdom='$VDOM_NAME'&'
                echo '   +++++++++++++++++++++++++++'
                echo '   + enter vdom "'$VDOM_NAME'"'
                search_global_dns_server_zone
                test -z "${ZONES}" && echo '   + no zone found for this domain on this vdom'
                test -z "${ZONES}" && echo '   + leave vdom "'$VDOM_NAME'"'
                test -z "${ZONES}" && continue
                del_global_dns_server_zone_child_txt_record
                echo '   + leave vdom "'$VDOM_NAME'"'
            done
        else
            search_global_dns_server_zone
            test -z "${ZONES}" && echo '   + no zone found for this domain'
            test "${ZONES}" && del_global_dns_server_zone_child_txt_record
        fi
        
        logout
    fi
}

function deploy_cert() {
    local DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" FULLCHAINFILE="${4}" CHAINFILE="${5}" TIMESTAMP="${6}"

    # This hook is called once for each certificate that has been
    # produced. Here you might, for instance, copy your new certificates
    # to service-specific locations and reload the service.
    #
    # Parameters:
    # - DOMAIN
    #   The primary domain name, i.e. the certificate common
    #   name (CN).
    # - KEYFILE
    #   The path of the file containing the private key.
    # - CERTFILE
    #   The path of the file containing the signed certificate.
    # - FULLCHAINFILE
    #   The path of the file containing the full certificate chain.
    # - CHAINFILE
    #   The path of the file containing the intermediate certificate(s).
    # - TIMESTAMP
    #   Timestamp when the specified certificate was created.
    
    echo ' + fortiadc hook executing: deploy_cert'
    
    login
    if [[ $LOGGED == 1 ]] ; then
        get_vdom_list
        add_cert $DOMAIN $KEYFILE $CERTFILE $IS_VDOM
        logout
    fi

}

function unchanged_cert() {
    local DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" FULLCHAINFILE="${4}" CHAINFILE="${5}"

    # This hook is called once for each certificate that is still
    # valid and therefore wasn't reissued.
    #
    # Parameters:
    # - DOMAIN
    #   The primary domain name, i.e. the certificate common
    #   name (CN).
    # - KEYFILE
    #   The path of the file containing the private key.
    # - CERTFILE
    #   The path of the file containing the signed certificate.
    # - FULLCHAINFILE
    #   The path of the file containing the full certificate chain.
    # - CHAINFILE
    #   The path of the file containing the intermediate certificate(s).
    
    echo ' + fortiadc hook executing: unchanged_cert'
    
    echo ' + nothing to do'
}

function invalid_challenge() {
    local DOMAIN="${1}" RESPONSE="${2}"

    # This hook is called if the challenge response has failed, so domain
    # owners can be aware and act accordingly.
    #
    # Parameters:
    # - DOMAIN
    #   The primary domain name, i.e. the certificate common
    #   name (CN).
    # - RESPONSE
    #   The response that the verification server returned
    
    echo ' + fortiadc hook executing: invalid_challenge'
    
    echo ' + nothing to do'
}

function request_failure() {
    local STATUSCODE="${1}" REASON="${2}" REQTYPE="${3}"

    # This hook is called when a HTTP request fails (e.g., when the ACME
    # server is busy, returns an error, etc). It will be called upon any
    # response code that does not start with '2'. Useful to alert admins
    # about problems with requests.
    #
    # Parameters:
    # - STATUSCODE
    #   The HTML status code that originated the error.
    # - REASON
    #   The specified reason for the error.
    # - REQTYPE
    #   The kind of request that was made (GET, POST...)
    
    echo ' + fortiadc hook executing: request_failure'
    
    echo ' + nothing to do'
}

function startup_hook() {
  # This hook is called before the cron command to do some initial tasks
  # (e.g. starting a webserver).

  :
}

function exit_hook() {
  # This hook is called at the end of a dehydrated command and can be used
  # to do some final (cleanup or other) tasks.

  :
}

HANDLER="$1"; shift
if [[ "${HANDLER}" =~ ^(deploy_challenge|clean_challenge|deploy_cert|unchanged_cert|invalid_challenge|request_failure|startup_hook|exit_hook)$ ]]; then
  "$HANDLER" "$@"
fi
