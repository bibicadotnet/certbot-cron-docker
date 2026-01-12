#!/command/with-contenv bash
# shellcheck shell=bash

if [ $ONE_SHOT == "true" ]; then

    # Cleanly kill container by sending kill signal to supervisor process
    echo 0 > /run/s6-linux-init-container-results/exitcode
    /run/s6/basedir/bin/halt

fi