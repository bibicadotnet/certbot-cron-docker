#!/command/with-contenv bash
# shellcheck shell=bash

echo ""
echo ""
echo "================================================"
echo "|      __  _______  __  ___________________    |" 
echo "|     /  |/  / __ \/  |/  / ____/ ____/ __ )   |"
echo "|    / /|_/ / /_/ / /|_/ / __/ / __/ / __  |   |"
echo "|   / /  / / _, _/ /  / / /___/ /___/ /_/ /    |"
echo "|  /_/  /_/_/ |_/_/  /_/_____/_____/_____/     |"
echo "|                                              |"
echo "================================================"
echo ""
echo "Initialising container"
if [ ${CERT_COUNT} == 1 ]; then
echo \
"----------------------------------------------------------------------
ENVIRONMENT
----------------------------------------------------------------------"
else
echo \
"----------------------------------------------------------------------
ENVIRONMENT (Certificate options logged later)
----------------------------------------------------------------------"
fi
echo \
"PUID=${PUID}
PGID=${PGID}
TZ=${TZ}
ONE_SHOT=${ONE_SHOT}
INTERVAL=${INTERVAL}
GENERATE_DHPARAM=${GENERATE_DHPARAM}
CERT_COUNT=${CERT_COUNT}
NOTIFY_ON_SUCCESS=${NOTIFY_ON_SUCCESS}
NOTIFY_ON_FAILURE=${NOTIFY_ON_FAILURE}"
if [ ! -z ${APPRISE_URL} ]; then
echo \
"APPRISE_URL=[hidden]"
fi
## Send extra detail to logs if single certificate config
if [ ${CERT_COUNT} == 1 ]; then
echo \
"DOMAINS=${DOMAINS}
EMAIL=${EMAIL}
STAGING=${STAGING}
CUSTOM_CA=${CUSTOM_CA}
CUSTOM_CA_SERVER=${CUSTOM_CA_SERVER}
PLUGIN=${PLUGIN}"
fi
## Get plugin-specific data if single certificate config
if [ ${CERT_COUNT} == 1 ] && [ ${PLUGIN} == 'cloudflare' ]; then
echo \
"PROPOGATION_TIME=${PROPOGATION_TIME}"
fi
if [ ${CERT_COUNT} == 1 ] && [ ${PLUGIN} == 'cloudflare' ] && [ ! -z ${CLOUDFLARE_TOKEN} ]; then
echo \
"CLOUDFLARE_TOKEN=[hidden]"
elif [ ${CERT_COUNT} == 1 ] && [ ${PLUGIN} == 'cloudflare' ] && [ -z ${CLOUDFLARE_TOKEN} ]; then
echo \
"CLOUDFLARE_TOKEN="
fi
echo \
"----------------------------------------------------------------------
"

#Setting UID and GID as configured
if [[ ! "${PUID}" -eq 0 ]] && [[ ! "${PGID}" -eq 0 ]]; then
    echo "Executing usermod..."
    mkdir "/tmp/temphome"
    usermod -d "/tmp/temphome" mrmeeb
    usermod -o -u "${PUID}" mrmeeb
    usermod -d /config mrmeeb
    rm -rf "/tmp/temphome"
    groupmod -o -g "${PGID}" mrmeeb
else
    echo "Running as root is not supported, please fix your PUID and PGID!"
    sleep infinity
fi

echo "Checking permissions in /config and /app."

if [ ! "$(stat -c %u /app)" -eq "${PUID}" ] || [ ! "$(stat -c %g /app)" -eq "${PGID}" ]
then
    echo "Fixing permissions for /app (this can take some time)."
    chown -R mrmeeb:mrmeeb /app
fi

if [ ! "$(stat -c %u /config)" -eq "${PUID}" ] || [ ! "$(stat -c %g /config)" -eq "${PGID}" ]
then
    echo "Fixing permissions for /config (this can take some time)."
    chown -R mrmeeb:mrmeeb /config
fi