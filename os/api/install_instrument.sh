#!/bin/bash

NAME=$1
LIVE_DIRNAME=$2

/bin/rm -rf ${LIVE_DIRNAME}
/bin/mkdir -p ${LIVE_DIRNAME}

/bin/systemctl stop koheron-server.service
/usr/bin/unzip -o /usr/local/instruments/${NAME}.zip -d ${LIVE_DIRNAME}

source ${LIVE_DIRNAME}/start.sh

echo 'Load bitstream'
/bin/cat ${LIVE_DIRNAME}/${NAME}.bit > /dev/xdevcfg
/bin/cat /sys/bus/platform/drivers/xdevcfg/f8007000.devcfg/prog_done

echo 'Restart koheron-server'
/bin/systemctl start koheron-server.service
/bin/systemctl start koheron-server-init.service