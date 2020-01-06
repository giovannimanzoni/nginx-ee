#!/usr/bin/env bash

JAIL='/srv/'
NF='ngxdef'

# Colors
CSI='\033['
CRED="${CSI}1;31m"
CGREEN="${CSI}1;32m"
CEND="${CSI}0m"


_check_privileges() {

        echo -ne '	Controllo privilegi			[..]\r'
        sleep 1
        if [ $(id -u) -ne 0 ]; then
                echo -ne '	Controllo privilegi			[FAIL]\r'
                echo -e  "\n        Non sei root"
                exit
        else
                echo -e "	Controllo privilegi			[${CGREEN}OK${CEND}]\\r"
        fi
}



_check_privileges

# fix & recreate folder if missing after rebot

if [ ! -d /var/run/$NF-cache ]; then
	mkdir -p /var/run/$NF-cache
fi
chown $NF:root /var/run/$NF-cache

if [ ! -d /var/run/$NF-pid ]; then
	mkdir /var/run/$NF-pid
fi
chown $NF:root /var/run/$NF-pid

if [ ! -d /var/lock/$NF-lock ]; then
	mkdir /var/lock/$NF-lock
fi
chown $NF:root /var/lock/$NF-lock

chown -R $NF:root /var/log/$NF $JAIL$NF

# start master process as $NF user & allow bind on port < 1024
setcap 'cap_net_bind_service=+ep' $JAIL$NF/sbin/$NF

service $NF start

