#!/bin/bash
service ngxdef stop
rm -rf /srv/*
rm /lib/systemd/system/ngxdef.service
systemctl daemon-reload
rm /var/run/ngxdef-pid/ngxdef.pid
