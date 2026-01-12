#!/command/with-contenv bash
# shellcheck shell=bash

# Halt container if anything returns a non-zero exit code
set -e

# Creating needed folders and files if they don't already exist
if [ ! -d /config/.secrets ]
then
    mkdir /config/.secrets
fi

if [ ! -d /config/letsencrypt ]
then
    mkdir /config/letsencrypt
fi

if [ ! -d /config/letsencrypt/keys ]
then
    mkdir /config/letsencrypt/keys
fi

if [ ! -d /config/logs ]
then
    mkdir /config/logs
fi

if [ ! -f /config/logs/renew.log ]
then
    touch /config/logs/renew.log
fi

if [ ! -f /config/.crontab.txt ]
then
    touch /config/.crontab.txt
fi

function better_exit {

    echo ""
    echo ""
    echo ""
    echo "You can ignore the below error messages - they happened because the container exited with a non-0 exit code due misconfiguration"
    echo "=========================================================="
    exit 1

}

# Check APPRISE_URL is set if either NOTIFY_ON_SUCCESS or NOTIFY_ON_FAILURE are set
if [ "${NOTIFY_ON_SUCCESS}" = "true" ] || [ "${NOTIFY_ON_FAILURE}" = "true" ] && [ -z "${APPRISE_URL}" ]; then

    echo "You have notifications enabled but have not set APPRISE_URL. Please set APPRISE_URL and restart the container."
    better_exit

fi

# Cleanup renew list and create it fresh, ready for commands to be run and added
echo "#!/command/with-contenv bash

date
echo \"Attempting to renew certificates\"
source /renew-function.sh
" > /config/.renew-list.sh
chmod +x /config/.renew-list.sh

# Create original config file to track changes to environmental variables
if [ ! -f /config/.donoteditthisfile ]
then
    echo -e "ORIGDOMAINS=\"${DOMAINS}\" ORIGEMAIL=\"${EMAIL}\" ORIGSTAGING=\"${STAGING}\" ORIGCUSTOM_CA=\"${CUSTOM_CA}\" ORIGCUSTOM_CA_SERVER=\"${CUSTOM_CA_SERVER}\" ORIGPLUGIN=\"${PLUGIN}\" ORIGPROPOGATION_TIME=\"${PROPOGATION_TIME}\" ORIGCERT_COUNT=${CERT_COUNT}" > /config/.donoteditthisfile
fi

# Load original config file
. /config/.donoteditthisfile

# Revoke all certs if CERT_COUNT has decreased, starting fresh
if [ "${CERT_COUNT}" -lt "${ORIGCERT_COUNT}" ]; then

    echo ""

    echo "CERT_COUNT has decreased - revoking all certificates then reissuing to cleanup any lingerers."

    # Use .donoteditthisfile_cert_* to get details of each issued certificate to revoke with correct parameters

    x=1
    while [ $x -le ${ORIGCERT_COUNT} ]; do

        # Load config of particular cert
        . /config/.donoteditthisfile_cert_${x}

        # Setting up variables (requires two passes to clean away requirement for indirect variables)
        ## Pass 1
        DOMAINS_P1=ORIGDOMAINS_${x}
        EMAIL_P1=ORIGEMAIL_${x}
        STAGING_P1=ORIGSTAGING_${x}
        CUSTOM_CA_P1=ORIGCUSTOM_CA_${x}
        CUSTOM_CA_SERVER_P1=ORIGCUSTOM_CA_SERVER_${x}
        PLUGIN_P1=ORIGPLUGIN_${x}
        PROPOGATION_TIME_P1=ORIGPROPOGATION_TIME_${x}
        CLOUDFLARE_TOKEN_P1=ORIGCLOUDFLARE_TOKEN_${x}

        ## Pass 2
        DOMAINS_MULTI=${!DOMAINS_P1}
        EMAIL_MULTI=${!EMAIL_P1}
        STAGING_MULTI=${!STAGING_P1}
        CUSTOM_CA_MULTI=${!CUSTOM_CA_P1}
        CUSTOM_CA_SERVER_MULTI=${!CUSTOM_CA_SERVER_P1}
        PLUGIN_MULTI=${!PLUGIN_P1}
        PROPOGATION_TIME_MULTI=${!PROPOGATION_TIME_P1}
        CLOUDFLARE_TOKEN_MULTI=${!CLOUDFLARE_TOKEN_P1}

        FIRST_DOMAIN_MULTI=$(echo ${DOMAINS_MULTI} | cut -d \, -f1)

        echo ${FIRST_DOMAIN_MULTI}

        if [ ! -z ${CUSTOM_CA_MULTI} ]
        then

            echo "A custom CA was used for issuing certificate ${x}. Using it to revoke as well."

            if [ ! -d /config/custom_ca ]
            then
                mkdir /config/custom_ca
                echo "Please place the custom CA root file used to generate the current certificate ${x} into /config/custom_ca and restart the container"
                better_exit
            fi

            if [ -z "$(ls -A /config/custom_ca)" ]
            then
                echo "A root certificate called ${CUSTOM_CA_MULTI} was used to generate a certificate, but the /config/custom_ca dir is now empty. Please place this root certificate back this directory and restart the container so it can be safely revoked"
                better_exit
            fi

            CUSTOM_CA_PATH_MULTI=/config/custom_ca/${CUSTOM_CA_MULTI}
            CUSTOM_CA_SERVER_OPT_MULTI="--server ${CUSTOM_CA_SERVER_MULTI}"

        fi

        if [ $STAGING_MULTI = "true" ]
        then

            # Reusing the CUSTOM_CA_SERVER_OPT variable to add staging option if that was selected
            CUSTOM_CA_SERVER_OPT_MULTI="--server https://acme-staging-v02.api.letsencrypt.org/directory"

        fi

        if [ -f /config/letsencrypt/live/"${FIRST_DOMAIN_MULTI}"/fullchain.pem ]
        then

            REQUESTS_CA_BUNDLE=$CUSTOM_CA_PATH_MULTI certbot revoke --non-interactive --agree-tos --email $EMAIL_MULTI --config-dir /config/letsencrypt --work-dir /config/.tmp --logs-dir /config/logs --cert-path /config/letsencrypt/live/"${FIRST_DOMAIN_MULTI}"/fullchain.pem ${CUSTOM_CA_SERVER_OPT_MULTI} || true

            rm -rf /config/letsencrypt/archive/"${FIRST_DOMAIN_MULTI}"
            rm -rf /config/letsencrypt/live/"${FIRST_DOMAIN_MULTI}"
            rm -rf /config/letsencrypt/renewal/"${FIRST_DOMAIN_MULTI}".conf

        fi

        # Delete .donoteditthisfile_cert_${x}
        rm -rf /config/.donoteditthisfile_cert_${x}

        # Scrubbing variables before running next cert revoke to prevent overlap of values
        DOMAINS_MULTI=
        EMAIL_MULTI=
        STAGING_MULTI=
        CUSTOM_CA_MULTI=
        CUSTOM_CA_SERVER_MULTI=
        PLUGIN_MULTI=
        PROPOGATION_TIME_MULTI=
        CLOUDFLARE_TOKEN_MULTI=
        CUSTOM_CA_PATH_MULTI=
        CUSTOM_CA_SERVER_OPT_MULTI=

        x=$(( $x + 1 ))

    done

    echo "Tidying up any potential lingering ACME challenges in /config/webroot from failed webroot activations"
    rm -rf /config/webroot/.well-known/acme-challenge

fi

function single_domain {

    # Checking for changes to config file, revoke certs if necessary
    if [ ! "${DOMAINS}" = "${ORIGDOMAINS}" ] ||
        [ ! "${EMAIL}" = "${ORIGEMAIL}" ] ||
        [ ! "${STAGING}" = "${ORIGSTAGING}" ] ||
        [ ! "${CUSTOM_CA}" = "${ORIGCUSTOM_CA}" ] ||
        [ ! "${CUSTOM_CA_SERVER}" = "${ORIGCUSTOM_CA_SERVER}" ] ||
        [ ! "${PLUGIN}" = "${ORIGPLUGIN}" ] ||
        [ ! "${PROPOGATION_TIME}" = "${ORIGPROPOGATION_TIME}" ]
    then

        echo ""

        echo "Configuration has changed since the last certificate was issued. Revoking and regenerating certs"
        FIRST_DOMAIN=$(echo $ORIGDOMAINS | cut -d \, -f1)

        if [ ! -z $ORIGCUSTOM_CA ]
        then

            echo "A custom CA was used for issuing. Using it to revoke as well."

            if [ ! -d /config/custom_ca ]
            then
                mkdir /config/custom_ca
                echo "Please place the custom CA root file used to generate the current certificate into /config/custom_ca and restart the container"
                better_exit
            fi

            if [ -z "$(ls -A /config/custom_ca)" ]
            then
                echo "A root certificate called ${ORIGCUSTOM_CA} was used to generate a certificate, but the /config/custom_ca dir is now empty. Please place this root certificate back this directory and restart the container so it can be safely revoked"
                better_exit
            fi

            ORIGCUSTOM_CA_PATH=/config/custom_ca/$ORIGCUSTOM_CA
            ORIGCUSTOM_CA_SERVER_OPT="--server $ORIGCUSTOM_CA_SERVER"

        fi

        if [ $ORIGSTAGING = "true" ]
        then

            # Reusing the CUSTOM_CA_SERVER_OPT variable to add staging option if that was selected
            ORIGCUSTOM_CA_SERVER_OPT="--server https://acme-staging-v02.api.letsencrypt.org/directory"

        fi

        if [ -f /config/letsencrypt/live/"${FIRST_DOMAIN}"/fullchain.pem ]
        then

            REQUESTS_CA_BUNDLE=$ORIGCUSTOM_CA_PATH certbot revoke --non-interactive --agree-tos --email $ORIGEMAIL --config-dir /config/letsencrypt --work-dir /config/.tmp --logs-dir /config/logs --cert-path /config/letsencrypt/live/"${FIRST_DOMAIN}"/fullchain.pem $ORIGCUSTOM_CA_SERVER_OPT || true

            rm -rf /config/letsencrypt/archive/"${FIRST_DOMAIN}"
            rm -rf /config/letsencrypt/live/"${FIRST_DOMAIN}"
            rm -rf /config/letsencrypt/renewal/"${FIRST_DOMAIN}".conf

        fi

    fi

    # Update config file with new env vars
    echo -e "ORIGDOMAINS=\"${DOMAINS}\" ORIGEMAIL=\"${EMAIL}\" ORIGSTAGING=\"${STAGING}\" ORIGCUSTOM_CA=\"${CUSTOM_CA}\" ORIGCUSTOM_CA_SERVER=\"${CUSTOM_CA_SERVER}\" ORIGPLUGIN=\"${PLUGIN}\" ORIGPROPOGATION_TIME=\"${PROPOGATION_TIME}\" ORIGCERT_COUNT=${CERT_COUNT}" > /config/.donoteditthisfile

    echo ""

    if [ ! -z $CUSTOM_CA ]
    then

        echo "Using a custom CA for issuing certificates"

        if [ ! -d /config/custom_ca ]
        then
            mkdir /config/custom_ca
            echo "Please place your custom CA file into /config/custom_ca and restart the container"
            better_exit
        fi

        if [ -z "$(ls -A /config/custom_ca)" ]
        then
            echo "The CUSTOM_CA option is populated, but the /config/custom_ca dir is empty. Please place your root certificate in this directory and restart the container"
            better_exit
        fi

        if [ -z $CUSTOM_CA_SERVER ]
        then
            echo "CUSTOM_CA_SERVER has not been defined. It is required for using a custom CA to issue a certificate"
            better_exit
        fi

        CUSTOM_CA_PATH=/config/custom_ca/$CUSTOM_CA
        CUSTOM_CA_SERVER_OPT="--server $CUSTOM_CA_SERVER"

        if [ $STAGING = "true" ]
        then

            echo "Staging option is not supported when using a custom CA. To remove this alert, set staging to false. If your CA has a standing endpoint, use the CUSTOM_CA_SERVER option to point to it instead"
            better_exit

        fi

    fi

    BASE_COMMAND=(certbot certonly --non-interactive --config-dir /config/letsencrypt --work-dir /config/.tmp --logs-dir /config/logs --key-path /config/letsencrypt/keys --expand --agree-tos $CUSTOM_CA_SERVER_OPT --email $EMAIL -d $DOMAINS)

    ## Run with Cloudflare plugin
    if [ $PLUGIN == "cloudflare" ]
    then

        echo "Using Cloudflare plugin"

        if [ ! -f /config/.secrets/cloudflare.ini ]
        then
            touch /config/.secrets/cloudflare.ini
        fi

        if [ -n "$CLOUDFLARE_TOKEN" ]
        then
            echo "Cloudflare token is present"

            echo "dns_cloudflare_api_token = $CLOUDFLARE_TOKEN" > /config/.secrets/cloudflare.ini

        fi

        if [ ! -s /config/.secrets/cloudflare.ini ]
        then
            echo "cloudflare.ini is empty - please add your Cloudflare credentials or API key before continuing. This can be done by setting CLOUDFLARE_TOKEN, or by editing /config/.secrets/cloudflare.ini directly"

            better_exit
        fi

        #Securing cloudflare.ini to supress warnings
        chmod 600 /config/.secrets/cloudflare.ini

        echo "Creating certificates, or attempting to renew if they already exist"

        if [ $STAGING = true ] 
        then
            echo "Using staging endpoint - THIS SHOULD BE USED FOR TESTING ONLY"
            ${BASE_COMMAND[@]} --dns-cloudflare --dns-cloudflare-propagation-seconds $PROPOGATION_TIME --dns-cloudflare-credentials /config/.secrets/cloudflare.ini --staging
            # Add to renewal list
            echo "renew \"REQUESTS_CA_BUNDLE=$CUSTOM_CA_PATH ${BASE_COMMAND[@]} --dns-cloudflare --dns-cloudflare-propagation-seconds $PROPOGATION_TIME --dns-cloudflare-credentials /config/.secrets/cloudflare.ini --staging\"" >> /config/.renew-list.sh
            echo "Creation/renewal attempt complete"
        elif [ $STAGING = false ]
        then
            echo "Using production endpoint"
            ${BASE_COMMAND[@]} --dns-cloudflare --dns-cloudflare-propagation-seconds $PROPOGATION_TIME --dns-cloudflare-credentials /config/.secrets/cloudflare.ini
            # Add to renewal list
            echo "renew \"REQUESTS_CA_BUNDLE=$CUSTOM_CA_PATH ${BASE_COMMAND[@]} --dns-cloudflare --dns-cloudflare-propagation-seconds $PROPOGATION_TIME --dns-cloudflare-credentials /config/.secrets/cloudflare.ini\"" >> /config/.renew-list.sh
            echo "Creation/renewal attempt complete"
        else
            echo "Unrecognised option for STAGING variable - check your configuration"

            better_exit
        fi

    ## Run with Standalone plugin
    elif [ $PLUGIN == "standalone" ]
    then

        echo "Using HTTP verification via built-in web-server - please ensure port 80 is exposed."

        if [ $STAGING = true ]
        then
            echo "Using staging endpoint - THIS SHOULD BE USED FOR TESTING ONLY"
            REQUESTS_CA_BUNDLE=$CUSTOM_CA_PATH ${BASE_COMMAND[@]} --standalone --staging
            # Add to renewal list
            echo "renew \"REQUESTS_CA_BUNDLE=$CUSTOM_CA_PATH ${BASE_COMMAND[@]} --standalone --staging\"" >> /config/.renew-list.sh
            echo "Creation/renewal attempt complete"
        elif [ $STAGING = false ]
        then
            echo "Using production endpoint"
            REQUESTS_CA_BUNDLE=$CUSTOM_CA_PATH ${BASE_COMMAND[@]} --standalone
            # Add to renewal list
            echo "renew \"REQUESTS_CA_BUNDLE=$CUSTOM_CA_PATH ${BASE_COMMAND[@]} --standalone\"" >> /config/.renew-list.sh
            echo "Creation/renewal attempt complete"
        else
            echo "Unrecognised option for STAGING variable - check your configuration"

            better_exit
        fi

    ## Run with webroot plugin
    elif [ $PLUGIN == "webroot" ]
    then

        echo "Using HTTP verification via webroot - please ensure you have mounted a webroot at /config/webroot from a web-server reachable via the domain you are issuing a certificate for."

        if [ $STAGING = true ]
        then
            echo "Using staging endpoint - THIS SHOULD BE USED FOR TESTING ONLY"
            REQUESTS_CA_BUNDLE=$CUSTOM_CA_PATH ${BASE_COMMAND[@]} --webroot --webroot-path /config/webroot --staging
            # Add to renewal list
            echo "renew \"REQUESTS_CA_BUNDLE=$CUSTOM_CA_PATH ${BASE_COMMAND[@]} --webroot --webroot-path /config/webroot --staging\"" >> /config/.renew-list.sh
            echo "Creation/renewal attempt complete"
        elif [ $STAGING = false ]
        then
            echo "Using production endpoint"
            REQUESTS_CA_BUNDLE=$CUSTOM_CA_PATH ${BASE_COMMAND[@]} --webroot --webroot-path /config/webroot
            # Add to renewal list
            echo "renew \"REQUESTS_CA_BUNDLE=$CUSTOM_CA_PATH ${BASE_COMMAND[@]} --webroot --webroot-path /config/webroot\"" >> /config/.renew-list.sh
            echo "Creation/renewal attempt complete"
        else
            echo "Unrecognised option for STAGING variable - check your configuration"

            better_exit
        fi

    else

        echo "Unrecognised option for PLUGIN variable - check your configuration"

    fi

}

function multi_domain {

    # Update config file with new env vars
    echo -e "ORIGDOMAINS=\"${DOMAINS}\" ORIGEMAIL=\"${EMAIL}\" ORIGSTAGING=\"${STAGING}\" ORIGCUSTOM_CA=\"${CUSTOM_CA}\" ORIGCUSTOM_CA_SERVER=\"${CUSTOM_CA_SERVER}\" ORIGPLUGIN=\"${PLUGIN}\" ORIGPROPOGATION_TIME=\"${PROPOGATION_TIME}\" ORIGCERT_COUNT=${CERT_COUNT}" > /config/.donoteditthisfile

    ## Start multi-domain looper
    x=1
    while [ $x -le $CERT_COUNT ]
    do

        # Setting up variables (requires two passes to clean away requirement for indirect variable)
        ## Pass 1
        DOMAINS_P1=DOMAINS_${x}
        EMAIL_P1=EMAIL_${x}
        STAGING_P1=STAGING_${x}
        CUSTOM_CA_P1=CUSTOM_CA_${x}
        CUSTOM_CA_SERVER_P1=CUSTOM_CA_SERVER_${x}
        PLUGIN_P1=PLUGIN_${x}
        PROPOGATION_TIME_P1=PROPOGATION_TIME_${x}
        CLOUDFLARE_TOKEN_P1=CLOUDFLARE_TOKEN_${x}

        ## Pass 2
        DOMAINS_MULTI=${!DOMAINS_P1}
        EMAIL_MULTI=${!EMAIL_P1}
        STAGING_MULTI=${!STAGING_P1}
        CUSTOM_CA_MULTI=${!CUSTOM_CA_P1}
        CUSTOM_CA_SERVER_MULTI=${!CUSTOM_CA_SERVER_P1}
        PLUGIN_MULTI=${!PLUGIN_P1}
        PROPOGATION_TIME_MULTI=${!PROPOGATION_TIME_P1}
        CLOUDFLARE_TOKEN_MULTI=${!CLOUDFLARE_TOKEN_P1}

        # Inheriting global default if undefined for certain variables
        if [ -z ${EMAIL_MULTI} ]; then
            EMAIL_MULTI=${EMAIL}
        fi

        if [ -z ${STAGING_MULTI} ]; then
            STAGING_MULTI=${STAGING}
        fi

        if [ -z ${CUSTOM_CA_MULTI} ]; then
            CUSTOM_CA_MULTI=${CUSTOM_CA}
        fi

        if [ -z ${CUSTOM_CA_SERVER_MULTI} ]; then
            CUSTOM_CA_SERVER_MULTI=${CUSTOM_CA_SERVER}
        fi

        if [ -z ${PLUGIN_MULTI} ]; then
            PLUGIN_MULTI=${PLUGIN}
        fi
    
        if [ -z ${PROPOGATION_TIME_MULTI} ]; then
            PROPOGATION_TIME_MULTI=${PROPOGATION_TIME}
        fi

        # Create original config file to track changes to environmental variables
        if [ ! -f /config/.donoteditthisfile_cert_${x} ]
        then
            echo -e "ORIGDOMAINS_${x}=\"${DOMAINS_MULTI}\" ORIGEMAIL_${x}=\"${EMAIL_MULTI}\" ORIGSTAGING_${x}=\"${STAGING_MULTI}\" ORIGCUSTOM_CA_${x}=\"${CUSTOM_CA_MULTI}\" ORIGCUSTOM_CA_SERVER_${x}=\"${CUSTOM_CA_SERVER_MULTI}\" ORIGPLUGIN_${x}=\"${PLUGIN_MULTI}\" ORIGPROPOGATION_TIME_${x}=\"${PROPOGATION_TIME_MULTI}\"" > /config/.donoteditthisfile_cert_${x}
        fi

        # Load original config file
        . /config/.donoteditthisfile_cert_${x}

        ORIGDOMAINS_MULTI=ORIGDOMAINS_${x}
        ORIGEMAIL_MULTI=ORIGEMAIL_${x}
        ORIGSTAGING_MULTI=ORIGSTAGING_${x}
        ORIGCUSTOM_CA_MULTI=ORIGCUSTOM_CA_${x}
        ORIGCUSTOM_CA_SERVER_MULTI=ORIGCUSTOM_CA_SERVER_${x}
        ORIGPLUGIN_MULTI=ORIGPLUGIN_${x}
        ORIGPROPOGATION_TIME_MULTI=ORIGPROPOGATION_TIME_${x}
        ORIGCLOUDFLARE_TOKEN_MULTI=ORIGCLOUDFLARE_TOKEN_${x}

        # Log variables to console (have to remove indent because bash dumb)

        echo "
----------------------------------------------------------------------
CERTIFICATE ${x} ENVIRONMENT
----------------------------------------------------------------------"
echo \
"DOMAINS_${x}=${DOMAINS_MULTI}
EMAIL_${x}=${EMAIL_MULTI}
STAGING_${x}=${STAGING_MULTI}
CUSTOM_CA_${x}=${CUSTOM_CA_MULTI}
CUSTOM_CA_SERVER_${x}=${CUSTOM_CA_SERVER_MULTI}
PLUGIN_${x}=${PLUGIN_MULTI}"
## Get plugin-specific data if single certificate config
if [ ${PLUGIN_MULTI} == 'cloudflare' ]; then
echo \
"PROPOGATION_TIME_${x}=${PROPOGATION_TIME_MULTI}"
fi
if [ ${PLUGIN_MULTI} == 'cloudflare' ] && [ ! -z ${CLOUDFLARE_TOKEN_MULTI} ]; then
echo \
"CLOUDFLARE_TOKEN_${x}=[hidden]"
elif [ ${PLUGIN_MULTI} == 'cloudflare' ] && [ -z ${CLOUDFLARE_TOKEN_MULTI} ]; then
echo \
"CLOUDFLARE_TOKEN_${x}="
fi
echo \
"----------------------------------------------------------------------
"

        # Begin actually requesting the certificate

        echo "Requesting certificate $x"

        # Checking for changes to config file, revoke certs if necessary
        if [ ! "${DOMAINS_MULTI}" = "${!ORIGDOMAINS_MULTI}" ] ||
            [ ! "${EMAIL_MULTI}" = "${!ORIGEMAIL_MULTI}" ] ||
            [ ! "${STAGING_MULTI}" = "${!ORIGSTAGING_MULTI}" ] ||
            [ ! "${CUSTOM_CA_MULTI}" = "${!ORIGCUSTOM_CA_MULTI}" ] ||
            [ ! "${CUSTOM_CA_SERVER_MULTI}" = "${!ORIGCUSTOM_CA_SERVER_MULTI}" ] ||
            [ ! "${PLUGIN_MULTI}" = "${!ORIGPLUGIN_MULTI}" ] ||
            [ ! "${PROPOGATION_TIME_MULTI}" = "${!ORIGPROPOGATION_TIME_MULTI}" ]
        then

            echo ""

            echo "Configuration has changed since certificate ${x} was last issued. Revoking and regenerating cert ${x}"
            FIRST_DOMAIN_MULTI=$(echo ${!ORIGDOMAINS_MULTI} | cut -d \, -f1)

            if [ ! -z ${!ORIGCUSTOM_CA_MULTI} ]
            then

                echo "A custom CA was used for issuing certificate ${x}. Using it to revoke as well."

                if [ ! -d /config/custom_ca ]
                then
                    mkdir /config/custom_ca
                    echo "Please place the custom CA root file used to generate the current certificate ${x} into /config/custom_ca and restart the container"
                    better_exit
                fi

                if [ -z "$(ls -A /config/custom_ca)" ]
                then
                    echo "A root certificate called ${!ORIGCUSTOM_CA_MULTI} was used to generate a certificate, but the /config/custom_ca dir is now empty. Please place this root certificate back this directory and restart the container so it can be safely revoked"
                    better_exit
                fi

                ORIGCUSTOM_CA_PATH_MULTI=/config/custom_ca/${!ORIGCUSTOM_CA_MULTI}
                ORIGCUSTOM_CA_SERVER_OPT_MULTI="--server ${!ORIGCUSTOM_CA_SERVER_MULTI}"

            fi

            if [ $ORIGSTAGING_MULTI = "true" ]
            then

                # Reusing the CUSTOM_CA_SERVER_OPT variable to add staging option if that was selected
                ORIGCUSTOM_CA_SERVER_OPT_MULTI="--server https://acme-staging-v02.api.letsencrypt.org/directory"

            fi

            if [ -f /config/letsencrypt/live/"${FIRST_DOMAIN_MULTI}"/fullchain.pem ]
            then

                REQUESTS_CA_BUNDLE=$ORIGCUSTOM_CA_PATH_MULTI certbot revoke --non-interactive --agree-tos --email $ORIGEMAIL_MULTI --config-dir /config/letsencrypt --work-dir /config/.tmp --logs-dir /config/logs --cert-path /config/letsencrypt/live/"${FIRST_DOMAIN_MULTI}"/fullchain.pem ${ORIGCUSTOM_CA_SERVER_OPT_MULTI} || true

                rm -rf /config/letsencrypt/archive/"${FIRST_DOMAIN_MULTI}"
                rm -rf /config/letsencrypt/live/"${FIRST_DOMAIN_MULTI}"
                rm -rf /config/letsencrypt/renewal/"${FIRST_DOMAIN_MULTI}".conf

            fi

            echo "Tidying up any potential lingering ACME challenges in /config/webroot from failed webroot activations"
            rm -rf /config/webroot/.well-known/acme-challenge

        fi

        # Update config file with new cert-specific env vars
        echo -e "ORIGDOMAINS_${x}=\"${DOMAINS_MULTI}\" ORIGEMAIL_${x}=\"${EMAIL_MULTI}\" ORIGSTAGING_${x}=\"${STAGING_MULTI}\" ORIGCUSTOM_CA_${x}=\"${CUSTOM_CA_MULTI}\" ORIGCUSTOM_CA_SERVER_${x}=\"${CUSTOM_CA_SERVER_MULTI}\" ORIGPLUGIN_${x}=\"${PLUGIN_MULTI}\" ORIGPROPOGATION_TIME_${x}=\"${PROPOGATION_TIME_MULTI}\"" > /config/.donoteditthisfile_cert_${x}

        echo ""

        if [ ! -z ${CUSTOM_CA_MULTI} ]
        then

            echo "Using a custom CA for issuing certificate ${x}"

            if [ ! -d /config/custom_ca ]
            then
                mkdir /config/custom_ca
                echo "Please place your custom CA file into /config/custom_ca and restart the container"
                better_exit
            fi

            if [ -z "$(ls -A /config/custom_ca)" ]
            then
                echo "The CUSTOM_CA_${x} option is populated, but the /config/custom_ca dir is empty. Please place your root certificate for certificate ${x} in this directory and restart the container"
                better_exit
            fi

            if [ -z ${CUSTOM_CA_SERVER_MULTI} ]
            then
                echo "CUSTOM_CA_SERVER_${x} has not been defined. It is required when using a custom CA to issue certificate ${x}"
                better_exit
            fi

            CUSTOM_CA_PATH_MULTI=/config/custom_ca/${CUSTOM_CA_MULTI}
            CUSTOM_CA_SERVER_OPT_MULTI="--server ${CUSTOM_CA_SERVER_MULTI}"

            if [ ${STAGING_MULTI} = "true" ]
            then

                echo "Staging option is not supported when using a custom CA. To remove this alert, set staging to false. If your CA has a standing endpoint, use the CUSTOM_CA_SERVER_${x} option to point to it instead"
                better_exit

            fi

        fi

        BASE_COMMAND=(certbot certonly --non-interactive --config-dir /config/letsencrypt --work-dir /config/.tmp --logs-dir /config/logs --key-path /config/letsencrypt/keys --expand --agree-tos "${CUSTOM_CA_SERVER_OPT_MULTI}" --email "${EMAIL_MULTI}" -d "${DOMAINS_MULTI}")

        ## Run with Cloudflare plugin
        if [ ${PLUGIN_MULTI} == "cloudflare" ]
        then

            echo "Using Cloudflare plugin"

            if [ ! -f /config/.secrets/cloudflare.ini ]
            then
                touch /config/.secrets/cloudflare.ini
            fi

            if [ -n "${CLOUDFLARE_TOKEN_MULTI}" ]
            then
                echo "Cloudflare token is present"

                echo "dns_cloudflare_api_token = ${CLOUDFLARE_TOKEN_MULTI}" > /config/.secrets/cloudflare.ini

            fi

            if [ ! -s /config/.secrets/cloudflare.ini ]
            then
                echo "cloudflare.ini is empty - please add your Cloudflare credentials or API key before continuing. This can be done by setting CLOUDFLARE_TOKEN_${x}"

                better_exit
            fi

            #Securing cloudflare.ini to supress warnings
            chmod 600 /config/.secrets/cloudflare.ini

            echo "Creating certificates, or attempting to renew if they already exist"

            if [ ${STAGING_MULTI} = true ] 
            then
                echo "Using staging endpoint - THIS SHOULD BE USED FOR TESTING ONLY"
                ${BASE_COMMAND[@]} --dns-cloudflare --dns-cloudflare-propagation-seconds ${PROPOGATION_TIME_MULTI} --dns-cloudflare-credentials /config/.secrets/cloudflare.ini --staging
                # Add to renewal list
                echo "## Certificate ${x}" >> /config/.renew-list.sh
                echo "renew \"${BASE_COMMAND[@]} --dns-cloudflare --dns-cloudflare-propagation-seconds ${PROPOGATION_TIME_MULTI} --dns-cloudflare-credentials /config/.secrets/cloudflare.ini --staging\"" >> /config/.renew-list.sh
                echo ""  >> /config/.renew-list.sh
                echo "Creation/renewal attempt complete"
            elif [ ${STAGING_MULTI} = false ]
            then
                echo "Using production endpoint"
                ${BASE_COMMAND[@]} --dns-cloudflare --dns-cloudflare-propagation-seconds ${PROPOGATION_TIME_MULTI} --dns-cloudflare-credentials /config/.secrets/cloudflare.ini
                # Add to renewal list
                echo "## Certificate ${x}" >> /config/.renew-list.sh
                echo "renew \"REQUESTS_CA_BUNDLE=$CUSTOM_CA_PATH ${BASE_COMMAND[@]} --dns-cloudflare --dns-cloudflare-propagation-seconds ${PROPOGATION_TIME_MULTI} --dns-cloudflare-credentials /config/.secrets/cloudflare.ini\"" >> /config/.renew-list.sh
                echo ""  >> /config/.renew-list.sh
                echo "Creation/renewal attempt complete"
            else
                echo "Unrecognised option for STAGING variable - check your configuration"

                better_exit
            fi

        ## Run with Standalone plugin
        elif [ ${PLUGIN_MULTI} == "standalone" ]
        then

            echo "Using HTTP verification via built-in web-server - please ensure port 80 is exposed."

            if [ ${STAGING_MULTI} = true ]
            then
                echo "Using staging endpoint - THIS SHOULD BE USED FOR TESTING ONLY"
                REQUESTS_CA_BUNDLE=${CUSTOM_CA_PATH_MULTI} ${BASE_COMMAND[@]} --standalone --staging
                # Add to renewal list
                echo "## Certificate ${x}" >> /config/.renew-list.sh
                echo "renew \"REQUESTS_CA_BUNDLE=${CUSTOM_CA_PATH_MULTI} ${BASE_COMMAND[@]} --standalone --staging\"" >> /config/.renew-list.sh
                echo ""  >> /config/.renew-list.sh
                echo "Creation/renewal attempt complete"
            elif [ ${STAGING_MULTI} = false ]
            then
                echo "Using production endpoint"
                REQUESTS_CA_BUNDLE=${CUSTOM_CA_PATH_MULTI} ${BASE_COMMAND[@]} --standalone
                # Add to renewal list
                echo "## Certificate ${x}" >> /config/.renew-list.sh
                echo "renew \"REQUESTS_CA_BUNDLE=${CUSTOM_CA_PATH_MULTI} ${BASE_COMMAND[@]} --standalone\"" >> /config/.renew-list.sh
                echo ""  >> /config/.renew-list.sh
                echo "Creation/renewal attempt complete"
            else
                echo "Unrecognised option for STAGING variable - check your configuration"

                better_exit
            fi

        ## Run with webroot plugin
        elif [ ${PLUGIN_MULTI} == "webroot" ]
        then

            echo "Using HTTP verification via webroot - please ensure you have mounted a webroot at /config/webroot from a web-server reachable via the domain you are issuing a certificate for."

            if [ ${STAGING_MULTI} = true ]
            then
                echo "Using staging endpoint - THIS SHOULD BE USED FOR TESTING ONLY"
                REQUESTS_CA_BUNDLE=${CUSTOM_CA_PATH_MULTI} ${BASE_COMMAND[@]} --webroot --webroot-path /config/webroot --staging
                # Add to renewal list
                echo "## Certificate ${x}" >> /config/.renew-list.sh
                echo "renew \"REQUESTS_CA_BUNDLE=${CUSTOM_CA_PATH_MULTI} ${BASE_COMMAND[@]} --webroot --webroot-path /config/webroot --staging\"" >> /config/.renew-list.sh
                echo ""  >> /config/.renew-list.sh
                echo "Creation/renewal attempt complete"
            elif [ ${STAGING_MULTI} = false ]
            then
                echo "Using production endpoint"
                REQUESTS_CA_BUNDLE=${CUSTOM_CA_PATH_MULTI} ${BASE_COMMAND[@]} --webroot --webroot-path /config/webroot
                # Add to renewal list
                echo "## Certificate ${x}" >> /config/.renew-list.sh
                echo "renew \"REQUESTS_CA_BUNDLE=${CUSTOM_CA_PATH_MULTI} ${BASE_COMMAND[@]} --webroot --webroot-path /config/webroot\"" >> /config/.renew-list.sh
                echo ""  >> /config/.renew-list.sh
                echo "Creation/renewal attempt complete"
            else
                echo "Unrecognised option for STAGING variable - check your configuration"

                better_exit
            fi

        else

            echo "Unrecognised option for PLUGIN variable - check your configuration"

        fi

        # Scrubbing variables before running next cert to prevent overlap of values
        DOMAINS_MULTI=
        EMAIL_MULTI=
        STAGING_MULTI=
        CUSTOM_CA_MULTI=
        CUSTOM_CA_SERVER_MULTI=
        PLUGIN_MULTI=
        PROPOGATION_TIME_MULTI=
        CLOUDFLARE_TOKEN_MULTI=
        CUSTOM_CA_PATH_MULTI=
        CUSTOM_CA_SERVER_OPT_MULTI=
        ORIGDOMAINS_MULTI=
        ORIGEMAIL_MULTI=
        ORIGSTAGING_MULTI=
        ORIGCUSTOM_CA_MULTI=
        ORIGCUSTOM_CA_SERVER_MULTI=
        ORIGPLUGIN_MULTI=
        ORIGPROPOGATION_TIME_MULTI=
        ORIGCLOUDFLARE_TOKEN_MULTI=
        FIRST_DOMAIN_MULTI=
        ORIGCUSTOM_CA_PATH_MULTI=
        ORIGCUSTOM_CA_SERVER_OPT_MULTI=

        x=$(( $x + 1 ))

    done

}

if [ $CERT_COUNT == 1 ] 
then
    single_domain
elif [ $CERT_COUNT -gt 1 ]
then
    multi_domain
else
    echo "CERT_COUNT varaible not recognised. It needs to be a value of 1 or greater."
fi

# Finish /config/.renew-list.sh now all certs have been added
echo "
echo \"Renewal attempts complete\"" >> /config/.renew-list.sh

if [ $GENERATE_DHPARAM = true ] && [ ! -s /config/letsencrypt/keys/ssl-dhparams.pem ]
then
    echo ""
    echo "Generating Diffie-Hellman keys, saved to /config/letsencrypt/keys. This can take a long time!"
    openssl dhparam -out /config/letsencrypt/keys/ssl-dhparams.pem 4096
fi

if [ $ONE_SHOT == "true" ]; then

    echo ""

    echo "ONE_SHOT is true - exiting container"

elif [ $ONE_SHOT == "false" ]; then

    echo "$INTERVAL /config/.renew-list.sh >> /config/logs/renew.log
    0 0 * * * logrotate -v --state /config/logs/logrotate.status /logrotate.conf" > /config/.crontab.txt

    echo ""

    echo "Starting automatic renewal job. Schedule is $INTERVAL"
    crontab /config/.crontab.txt

fi