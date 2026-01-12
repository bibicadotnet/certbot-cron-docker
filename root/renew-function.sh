function renew() {

    #Variables:

    #$1 = Certbot command

    RENEWAL_DOMAINS=$(echo $1 | sed -r 's/.*\s-d\s(\S*).*/\1/')
    CUSTOM_CA_PATH=$(echo $1 | sed -r 's/REQUESTS_CA_BUNDLE=(\S*)\s(.*)/\1/')
    CERTBOT_COMMAND=$(echo $1 | sed -r 's/REQUESTS_CA_BUNDLE=(\S*)\s(.*)/\2/')

    echo "Renewing certificate for ${RENEWAL_DOMAINS}"

    echo "REQUESTS_CA_BUNDLE=${CUSTOM_CA_PATH} ${CERTBOT_COMMAND}" | bash

    if [ $? = 0 ]; then
        echo "Renewal attempt of certificate for ${RENEWAL_DOMAINS} succeeded"
        if [ "${NOTIFY_ON_SUCCESS}" = "true" ]; then
            apprise -b "Renewal of certificate for ${RENEWAL_DOMAINS} succeeded" ${APPRISE_URL}
        fi
    else
        echo "Renewal attempt of certificate for ${RENEWAL_DOMAINS} failed"
        if [ "${NOTIFY_ON_FAILURE}" = "true" ]; then
            apprise -b "Renewal of certificate for ${RENEWAL_DOMAINS} failed" ${APPRISE_URL}
        fi
    fi

}