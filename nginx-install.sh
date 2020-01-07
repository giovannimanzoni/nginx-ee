#!/usr/bin/env bash

HERE=$(pwd)
JAIL="/srv/"
NF="ngxdef"
FILE="/lib/systemd/system/$NF.service"
LOG_FILE="$HERE/install.log"
PIDFILE="/tmp/$NF.pid"


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
		echo "Non sei root" >> $LOG_FILE
        	echo -e "\n      Controlla $LOG_FILE"
		exit
	else
		echo -e "	Controllo privilegi			[${CGREEN}OK${CEND}]\\r"
	fi

}

_init() {
	echo -ne "	Init					[..]\r"
	sleep 1
	rm $LOG_FILE
	touch $LOG_FILE
	date > $LOG_FILE

	if [ ! -f $HERE/$NF*.deb ]; then
		echo -e "	Init					[${CRED}FAIL${CEND}]\r"
		echo -e "	Manca il file di setup .deb di Nginx\n"
		exit
	fi
	if [ ! -f $HERE/nginx.conf ]; then
		echo -e "	Init					[${CRED}FAIL${CEND}]\r"
		echo -e "	Manca il file con la configurazione di defult di Nginx"
		exit
	fi
	echo -e "	Init					[${CGREEN}OK${CEND}]\\r"
}

_install() {
	echo -ne "	Install					[..]\r"
	sleep 1
	if {
		{

		#installa
		dpkg -i $NF*.deb

		# fa partire master process come user $NF
		setcap 'cap_net_bind_service=+ep' $JAIL$NF/sbin/$NF

		# rimuove file creati con l'installazione che non servono
		rm $JAIL$NF/conf/*.default

		# aggiorna OVERWRITE conf di default
		git clone --depth=1 https://github.com/giovannimanzoni/nginx-config.git /tmp/git$NF
		cp -R /tmp/git$NF/* $JAIL$NF/conf/
		rm -rf /tmp/git$NF

		} >>$LOG_FILE 2>&1
	}; then
        	echo -e "	Install					[${CGREEN}OK${CEND}]\\r"
    	else
        	echo -e "	Install					[${CRED}FAIL${CEND}]"
        	echo -e "	Controlla $LOG_FILE"
        	exit 1
    	fi
}

_setup() {
	apt-get -y install logrotate libxslt1.1 libgoogle-perftools4 libcap2-bin

	# create nginx user for this nginx pkguser with no home, no login, no password
	if id "$NF" >/dev/null 2>&1; then
		sleep 1
	else
		useradd -r $NF
	fi

        # create nginx temp directory
        if [ ! -d /var/lib/$NF ]; then
                mkdir -p /var/lib/$NF/{body,fastcgi,proxy,scgi,uwsgi}
        fi

        # create nginx cache directory
        if [ ! -d /var/cache/$NF ]; then
            mkdir -p /var/cache/$NF
        fi
        if [ ! -d /var/run/$NF-cache ]; then
            mkdir -p /var/run/$NF-cache
        fi

        if [ ! -d /var/log/$NF ]; then
            mkdir -p /var/log/$NF
            touch /var/log/$NF/access.log
            touch /var/log/$NF/error.log
        fi
}

_create_service_file() {
  echo "Creo file .service" >> $LOG_FILE

  touch $FILE
  echo "[Unit]" > $FILE
  echo "Description=The $NF (Nginx) HTTP and reverse proxy server" >> $FILE
  echo "After=syslog.target network.target remote-fs.target nss-lookup.target" >> $FILE
  echo "" >> $FILE
  echo "[Service]" >> $FILE
  echo "Type=forking" >> $FILE
  echo "User=$NF" >> $FILE
  echo "PIDFile=/tmp/$NF.pid" >> $FILE
  echo "ExecStartPre=/srv/ngxdef/sbin/ngxdef -t -q -g 'daemon on; master_process on;'" >> $FILE
  echo "ExecStart=/srv/ngxdef/sbin/ngxdef -q -g 'daemon on; master_process on;'" >> $FILE
  echo "ExecReload=/srv/ngxdef/sbin/ngxdef -g 'daemon on; master_process on;' -s reload" >> $FILE
  echo "ExecStop=-/sbin/start-stop-daemon --quiet --stop --retry QUIT/5 --pidfile /tmp/ngxdef.pid" >> $FILE
  echo "PrivateTmp=true" >> $FILE
  echo "Restart=on-abort" >> $FILE
  echo "TimeoutStopSec=5" >> $FILE
  echo "KillMode=mixed" >> $FILE
  echo "" >> $FILE
  echo "[Install]" >> $FILE
  echo "WantedBy=multi-user.target" >> $FILE

  # enable on boot
  systemctl enable $NF.service

  # reload
  systemctl daemon-reload
}

pidchange() {
  local pidfile try=0 tries=3

  if [ ! -z $2 ]; then
    pidfile=$2
  else
    pidfile=$PIDFILE
  fi

  while [ $try -lt $tries ]; do
    case "$1" in
      'create')
        if [ -f $pidfile ]; then
	  #return ok
          return 0
        fi
        ;;
      'remove')
        if [ ! -f $pidfile ]; then
          #return ok
	  return 0
        fi
        ;;
    esac
    try=`expr $try + 1`
    sleep 1
  done

  #error
  return 3
}

_upgrade() {
	echo -ne '	Nginx upgrade				[..]\r'
	sleep 1
	#echo -n "OLD PID: "
	#echo `cat $PIDFILE`
	{
		kill -USR2 `cat $PIDFILE`
		pidchange 'create' $PIDFILE.oldbin
		NEWSTATUS=$?
		kill -WINCH `cat $PIDFILE.oldbin`
	} >> $LOG_FILE 2>&1

	if [ ${NEWSTATUS} -eq 0 ]; then
		kill -QUIT `cat $PIDFILE.oldbin`
	 	pidchange 'remove' $PIDFILE.oldbin
        	echo -e "	Nginx upgrade				[${CGREEN}OK${CEND}]\\r"
		sleep 1
	else
		kill -HUP `cat $PIDFILE`
		kill -TERM `cat $PIDFILE.oldbin`
		kill -QUIT `cat $PIDFILE.oldbin`
		pidchange 'remove' $PIDFILE.oldbin
        	echo -e "	Nginx upgrade				[${CRED}FAIL${CEND}]"
        	echo -e "	Controlla $LOG_FILE"
        	exit 1
        fi

	#echo
	#echo -n "NEW PID: "
	#echo `cat $PIDFILE`
}

_set_permissions() {
	# set proper permissions
	echo -ne "	Update permissions			[..]\r"
	sleep 1
        chmod 740 /var/log/$NF  # 640 ??
        chown -R $NF:root /var/log/$NF $JAIL$NF
        chown -R $NF:root /var/lib/$NF /var/cache/$NF /var/run/$NF-cache

       	echo -e "	Update permissions			[${CGREEN}OK${CEND}]\\r"
}

_add_startup() {
	systemctl enable $NF
}


#######################################
#	RUN
#######################################

echo ""
echo -e "${CGREEN}##################################${CEND}"
echo " $NF (Nginx) setup "
echo -e "${CGREEN}##################################${CEND}"
echo ""


_check_privileges
_init
_install

# New setup or upgrade ?
if [ ! -f $FILE  ]; then
# New setup
	_setup
	_create_service_file
	_add_startup

	# download logrotate configuration
        wget -O /etc/logrotate.d/$NF https://raw.githubusercontent.com/giovannimanzoni/nginx-ee/master/etc/logrotate.d/nginx

	# create initial nginx.conf
	cp $HERE/nginx.conf $JAIL$NF/conf/

	# create folders
	mkdir $JAIL$NF/conf/sites-enabled
	mkdir $JAIL$NF/conf/sites-availables

	#
	# test & start
	#
	# check if nginx -t do not return errors
	echo -ne "	Checking Nginx configuration		[..]\r"
	sleep 1
    	VERIFY_NGINX_CONFIG=$($NF -t 2>&1 | grep failed)
    	if [ -z "$VERIFY_NGINX_CONFIG" ]; then
        	echo -e "	Checking Nginx configuration		[${CGREEN}OK${CEND}]\\r"
		_set_permissions
		echo -ne "	Nginx start				[..]\r"
		sleep 1
        	{
			service $NF start
		} >> $LOG_FILE 2>&1
        	echo -e "	Nginx start				[${CGREEN}OK${CEND}]\\r"
	else
        	echo -e "	Checking Nginx configuration		[${CRED}FAIL${CEND}]"
        	echo -e "	Check $LOG_FILE"
        	exit 1
    	fi

else # upgrade

	# check if nginx -t do not return errors
	echo -ne "	Checking Nginx configuration		[..]\r"
	sleep 1
    	VERIFY_NGINX_CONFIG=$($NF -t 2>&1 | grep failed)
	if [ -z "$VERIFY_NGINX_CONFIG" ]; then
        	echo -e "	Checking nginx configuration		[${CGREEN}OK${CEND}]\\r"
		# RESTART if it is running or start it
		if [ -f /tmp/$NF.pid ]; then
			_upgrade
		else
		  echo -ne "	Start Nginx				[..]\r"
		  if {
			{
			  service $NF start
			} >> $LOG_FILE
		  }; then
		  	echo -e "	Start Nginx				[${CGREEN}OK${CEND}]\\r"
		  else
		  	echo -e "	Start Nginx				[${CRED}FAIL${CEND}]"
        		echo -e "	Check $LOG_FILE"
	        	exit 1
		  fi
		fi
    	else
		echo -e "	Checking nginx configuration           [${CRED}FAIL${CEND}]"
       		echo -e "	Check $LOG_FILE"
		exit 1
	fi
fi

