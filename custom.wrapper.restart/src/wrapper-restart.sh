#!/usr/bin/env bash

usage() {
    echo "usage: $0 <initscript> <lock_file> <interval_min> <count_max> <reset_after>"
    exit 0
}

[ $# -lt 5 ] && usage

INITSCRIPT="$1"
LOCK_FILE=$2
INTERVAL_MIN=$3
COUNT_MAX=$4
RESET_AFTER=$5
OS="$(uname)"
LASTLOCK="$(date +%s)"
NOW=${LASTLOCK}
LASTRESTART=${NOW}

wrapper_sendmail() {
    local MAIL_TO='root@localhost'
    local MAIL_FROM="$(whoami)@$(hostname -f)"
    local MAIL_SUBS=$1
    local MAIL_BODY=$2

    echo -en "From:${MAIL_FROM}\nTo:${MAIL_TO}\nSubject: ${MAIL_SUBS}\n\n${MAIL_BODY}" | \
        sendmail -f "$(whoami)@$(hostname -f)" ${MAIL_TO}
}

sudo -l | grep "${INITSCRIPT}\|(ALL) NOPASSWD: ALL\|(root) NOPASSWD: ALL" > /dev/null 2>&1
if [ $? -ne 0 ]; then

    echo "sudo ${INITSCRIPT}: Access denied"
    exit 1

fi

if [ "x$OS" != "x" ] && [ -f "$LOCK_FILE" ]; then

    if [ "$OS" == "Darwin" ]; then

        if [ -x /usr/local/bin/gstat ]; then

            LASTLOCK="$(/usr/local/bin/gstat -c%Y ${LOCK_FILE})"

        else
            echo 'gstat NOT FOUND. Please execute "brew install coreutils"'
            exit 1
        fi

    elif [ "$OS" == "Linux" ]; then

        LASTLOCK="$(stat -c%Y ${LOCK_FILE})"

    else
        echo "${OS} NOT SUPPORTED"
        exit 1
    fi

fi

DIFF=$[${NOW}-${LASTLOCK}]

if [ ${DIFF} -ge ${INTERVAL_MIN} ]; then

    if [ "x$LOCK_FILE" != "x" ] && [ -f "$LOCK_FILE" ]; then
        LASTRESTART=$(cat ${LOCK_FILE} | cut -d: -f2)
        if [ ${LASTRESTART} -lt $[$NOW-$RESET_AFTER] ]; then
            echo "1:$NOW" > ${LOCK_FILE}
        else
            COUNT=$(cat ${LOCK_FILE} | cut -d: -f1)
            COUNT=$[COUNT+1]
            echo "${COUNT}:${LASTRESTART}" > ${LOCK_FILE}
        fi
    else
        echo "1:$NOW" > ${LOCK_FILE}
    fi

    COUNT=$(cat ${LOCK_FILE} | cut -d: -f1)
    if [ ${COUNT} -ge ${COUNT_MAX} ]; then
        rm -f ${LOCK_FILE}
        wrapper_sendmail 'Wrapper Restart Event' 'Stopping service'
        eval "sudo ${INITSCRIPT} stop"
    else
        echo "${COUNT}:${NOW}" > ${LOCK_FILE}
        wrapper_sendmail 'Wrapper Restart Event' 'Restarting service'
        eval "sudo ${INITSCRIPT} restart"
    fi
fi

# EOF