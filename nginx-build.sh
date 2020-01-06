#!/usr/bin/env bash
# -------------------------------------------------------------------------
#  Nginx-ee - Automated Nginx compilation from source
# -------------------------------------------------------------------------
# GitHub:        https://github.com/giovannimanzoni/nginx-ee
# Copyright (c) 2019 VirtuBox <contact@virtubox.net>
# Copyright (c) 2020 The Doctor WEb S.r.l.  <info@thedoctorweb.com>
# This script is licensed under M.I.T
# -------------------------------------------------------------------------
# Version 3.6.5 - 2019-11-18
# Version 3.6.5b - 2020-01-02
# -------------------------------------------------------------------------


##################################
# Check requirements
##################################

# Check if user is root
[ "$(id -u)" != "0" ] && {
    echo "Error: You must be root or use sudo to run this script"
    exit 1
}

_help() {
    echo " -------------------------------------------------------------------- "
    echo "   Nginx-ee : automated Nginx compilation with additional modules  "
    echo " -------------------------------------------------------------------- "
    echo ""
    echo "Usage: ./nginx-ee <options> [modules]"
    echo "By default, Nginx-ee will compile the latest Nginx mainline release without Pagespeed, Naxsi or RTMP module"
    echo "  Options:"
    echo "       -h, --help ..... display this help"
    echo "       --stable ..... Nginx stable release"
    echo "       --full ..... Nginx mainline release with Pagespeed, Nasxi and RTMP module"
    echo "  Modules:"
    echo "       --pagespeed ..... Pagespeed module stable release"
    echo "       --pagespeed-beta .....  Pagespeed module beta release"
    echo "       --naxsi ..... Naxsi WAF module"
    echo "       --rtmp ..... RTMP video streaming module"
    echo "       --openssl-dev ..... Compile Nginx with OpenSSL 3.0.0-dev"
    echo "       --openssl-system ..... Compile Nginx with OpenSSL from system lib"
    echo "       --libressl ..... Compile Nginx with LibreSSL"
    echo ""
    return 0
}

##################################
# Use config.inc if available
##################################

if [ -f ./config.inc ]; then

    . ./config.inc

else

    ##################################
    # Parse script arguments
    ##################################

    while [ "$#" -gt 0 ]; do
        case "$1" in
        --pagespeed)
            PAGESPEED="y"
            PAGESPEED_RELEASE="2"
            ;;
        --pagespeed-beta)
            PAGESPEED="y"
            PAGESPEED_RELEASE="1"
            ;;
        --full)
            PAGESPEED="y"
            PAGESPEED_RELEASE="2"
            NAXSI="y"
            RTMP="y"
            ;;
        --naxsi)
            NAXSI="y"
            ;;
        --openssl-dev)
            OPENSSL_LIB="2"
            ;;
        --openssl-system)
            OPENSSL_LIB="3"
            ;;
        --libressl)
            LIBRESSL="y"
            ;;
        --rtmp)
            RTMP="y"
            ;;
        --latest | --mainline)
            NGINX_RELEASE="1"
            ;;
        --stable)
            NGINX_RELEASE="2"
            ;;
        --travis)
            TRAVIS_BUILD="1"
            ;;
	--tdw)
	PAGESPEED="y"
        PAGESPEED_RELEASE="2"
	NAXSI="y"
        RTMP="y"
	LIBRESSL="y"
	NGINX_RELEASE="1"
	    ;;
        -h | --help)
            _help
            exit 1
            ;;
        *) ;;
        esac
        shift
    done

fi

export DEBIAN_FRONTEND=noninteractive

# check if a command exist
command_exists() {
    command -v "$@" >/dev/null 2>&1
}

# updating packages list
[ -z "$TRAVIS_BUILD" ] && {
    apt-get update -qq
}

# checking if curl is installed
if ! command_exists curl; then
    apt-get install curl -qq
fi

# Checking if lsb_release is installed
if ! command_exists lsb_release; then
    apt-get -qq install lsb-release
fi

# checking if tar is installed
if ! command_exists tar; then
    apt-get install tar -qq
fi

# checking if jq is installed
if ! command_exists jq; then
    apt-get install jq -qq
fi

##################################
# Variables
##################################

HERE=$(pwd)
DIR_SRC="/usr/local/src"
DIR_DOWNLOAD="/usr/local/download"
NGINX_EE_VER=$(curl -m 5 --retry 3 -sL https://api.github.com/repos/VirtuBox/nginx-ee/releases/latest 2>&1 | jq -r '.tag_name')
NGINX_MAINLINE="$(curl -sL https://nginx.org/en/download.html 2>&1 | grep -E -o 'nginx\-[0-9.]+\.tar[.a-z]*' | awk -F "nginx-" '/.tar.gz$/ {print $2}' | sed -e 's|.tar.gz||g' | head -n 1 2>&1)"
NGINX_STABLE="$(curl -sL https://nginx.org/en/download.html 2>&1 | grep -E -o 'nginx\-[0-9.]+\.tar[.a-z]*' | awk -F "nginx-" '/.tar.gz$/ {print $2}' | sed -e 's|.tar.gz||g' | head -n 2 | grep 1.16 2>&1)"
LIBRESSL_VER="3.0.2"
STATICLIBSSL="$DIR_SRC/libressl"
OPENSSL_VER="1.1.1d"
readonly OS_ARCH="$(uname -m)"
OS_DISTRO_FULL="$(lsb_release -ds)"
readonly DISTRO_ID="$(lsb_release -si)"
readonly DISTRO_CODENAME="$(lsb_release -sc)"
readonly DISTRO_NUMBER="$(lsb_release -sr)"
OPENSSL_COMMIT="6f02932edba62186a6866e8c9f0f0714674f6bab"
# jail in separate hdd partition
JAIL="/srv/"
# nginx folder default for all domains, POI IMPOSTARLO COME PARAMETRO
NF="ngxdef"
#cartelle e file devono esistere



# Colors
CSI='\033['
CRED="${CSI}1;31m"
CGREEN="${CSI}1;32m"
CEND="${CSI}0m"

##################################
# Initial check & cleanup
##################################

# clean previous install log
_init() {
    echo "       Init"
    touch /tmp/nginx-ee.log
    date > /tmp/nginx-ee.log
    if [ ! -d $DIR_DOWNLOAD ]; then
    	mkdir -p $DIR_DOWNLOAD
    fi
}

# detect Plesk
[ -d /etc/psa ] && {
    PLESK_VALID="YES"
}

# detect easyengine
[ -f /var/lib/ee/ee.db ] && {
    EE_VALID="YES"
}

[ -f /var/lib/wo/dbase.db ] && {
    WO_VALID="YES"
}


##################################
# Installation menu
##################################

echo ""
echo "Welcome to the nginx-ee bash script ${NGINX_EE_VER}"
echo ""


##################################
# Set nginx release and HPACK
##################################

if [ "$NGINX_RELEASE" = "2" ]; then
    NGINX_VER="$NGINX_STABLE"
    NGX_HPACK="--with-http_v2_hpack_enc"
else
    NGINX_VER="$NGINX_MAINLINE"
    NGX_HPACK="--with-http_v2_hpack_enc"
fi

##################################
# Set RTMP module
##################################

if [ "$RTMP" = "y" ]; then
    NGX_RTMP="--add-module=../nginx-rtmp-module "
    RTMP_VALID="YES"
else
    NGX_RTMP=""
    RTMP_VALID="NO"
fi

##################################
# Set Naxsi module
##################################

if [ "$NAXSI" = "y" ]; then
    NGX_NAXSI="--add-module=../naxsi/naxsi_src "
    NAXSI_VALID="YES"
else
    NGX_NAXSI=""
    NAXSI_VALID="NO"
fi

##################################
# Set OPENSSL/LIBRESSL lib
##################################

if [ "$LIBRESSL" = "y" ]; then
    NGX_SSL_LIB="--with-openssl=../libressl"
    LIBRESSL_VALID="YES"
    OPENSSL_OPT=""
else
    if [ "$OS_ARCH" = 'x86_64' ]; then
        if [ "$DISTRO_ID" = "Ubuntu" ]; then
            OPENSSL_OPT="enable-ec_nistp_64_gcc_128 enable-tls1_3 no-ssl3-method -march=native -ljemalloc"
        else
            OPENSSL_OPT="enable-tls1_3"
        fi
    fi
    if [ "$OPENSSL_LIB" = "2" ]; then
        NGX_SSL_LIB="--with-openssl=../openssl"
        OPENSSL_VALID="3.0.0-dev"
        LIBSSL_DEV=""
    elif [ "$OPENSSL_LIB" = "3" ]; then
        NGX_SSL_LIB=""
        OPENSSL_VALID="from system"
        LIBSSL_DEV="libssl-dev"
    else
        NGX_SSL_LIB=""
        OPENSSL_VALID="$OPENSSL_VER Stable"
        LIBSSL_DEV="libssl-dev"
    fi
fi

##################################
# Set Pagespeed module
##################################

if [ -n "$PAGESPEED_RELEASE" ]; then
    if [ "$PAGESPEED_RELEASE" = "1" ]; then
        NGX_PAGESPEED="--add-module=../incubator-pagespeed-ngx-latest-beta "
        PAGESPEED_VALID="beta"
    elif [ "$PAGESPEED_RELEASE" = "2" ]; then
        NGX_PAGESPEED="--add-module=../incubator-pagespeed-ngx-latest-stable "
        PAGESPEED_VALID="stable"
    fi
else
    NGX_PAGESPEED=""
    PAGESPEED_VALID="NO"
fi

##################################
# Set Plesk configuration
##################################

if [ "$PLESK_VALID" = "YES" ]; then
    NGX_USER="--user=nginx --group=nginx"
else
    NGX_USER="--user=$NF --group=$NF"
fi


##################################
# Display Compilation Summary
##################################

echo ""
echo -e "${CGREEN}##################################${CEND}"
echo " Compilation summary "
echo -e "${CGREEN}##################################${CEND}"
echo ""
echo " Detected OS : $OS_DISTRO_FULL"
echo " Detected Arch : $OS_ARCH"
echo ""
echo -e "  - Nginx release : $NGINX_VER"
[ -n "$OPENSSL_VALID" ] && {
    echo -e "  - OPENSSL : $OPENSSL_VALID"
}
[ -n "$LIBRESSL_VALID" ] && {
    echo -e "  - LIBRESSL : $LIBRESSL_VALID"
}
echo "  - Pagespeed : $PAGESPEED_VALID"
echo "  - Naxsi : $NAXSI_VALID"
echo "  - RTMP : $RTMP_VALID"
[ -n "$EE_VALID" ] && {
    echo "  - EasyEngine : $EE_VALID"
}
[ -n "$WO_VALID" ] && {
    echo "  - WordOps : $WO_VALID"
}
[ -n "$PLESK_VALID" ] && {
    echo "  - Plesk : $PLESK_VALID"
}
echo ""

##################################
# Install dependencies
##################################

_gitget() {
    REPO="$1"
    echo "clono $REPO"
    repodir=$(echo "$REPO" | awk -F "/" '{print $2}')
    if [ -d $DIR_SRC/${repodir}/.git ]; then
        git -C $DIR_SRC/${repodir} pull &
    else
        if [ -d $DIR_SRC/${repodir} ]; then
            rm -rf $DIR_SRC/${repodir}
        fi
        git clone --depth 1 https://github.com/${REPO}.git $DIR_SRC/${repodir} &

    fi
}

_install_dependencies() {
    echo -ne '       Installing dependencies               [..]\r'
    if {
        apt-get -o Dpkg::Options::="--force-confmiss" -o Dpkg::Options::="--force-confold" -y install \
            sudo git build-essential libtool automake autoconf \
            libgd-dev dpkg-dev libgeoip-dev libjemalloc-dev \
            libbz2-1.0 libreadline-dev libbz2-dev libbz2-ocaml libbz2-ocaml-dev software-properties-common tar \
            libgoogle-perftools-dev perl libperl-dev libpam0g-dev libbsd-dev gnupg gnupg2 \
            libgmp-dev autotools-dev libxml2-dev libxslt-dev libpcre3-dev uuid-dev libbrotli-dev "$LIBSSL_DEV"

	apt-get -t buster-backports -y install checkinstall

    } >>/tmp/nginx-ee.log 2>&1; then
        echo -ne "       Installing dependencies                [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e "        Installing dependencies              [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1

    fi
}

##################################
# Setup Nginx from scratch
##################################
_create_service_file() {
  FILE="/lib/systemd/system/$NF.service"

  touch $FILE
  echo "[Unit]" > $FILE
  echo "Description=The $NF (Nginx) HTTP and reverse proxy server" >> $FILE
  echo "After=syslog.target network.target remote-fs.target nss-lookup.target" >> $FILE
  echo "" >> $FILE
  echo "[Service]" >> $FILE
  echo "Type=forking" >> $FILE
  echo "PIDFile=/var/run/$NF-pid/$NF.pid" >> $FILE
  echo "ExecStartPre=$JAIL/$NF/sbin/$NF -t" >> $FILE
  echo "ExecStart=$JAIL/$NF/sbin/$NF" >> $FILE
  echo "ExecReload=/bin/kill -s HUP \$MAINPID" >> $FILE
  echo "ExecStop=/bin/kill -s QUIT \$MAINPID" >> $FILE
  echo "PrivateTmp=true" >> $FILE
  echo "" >> $FILE
  echo "[Install]" >> $FILE
  echo "WantedBy=multi-user.target" >> $FILE

}

_nginx_from_scratch_setup() {

    echo -ne '       Setting Up Nginx configurations        [..]\r'
    if {
        # clone custom nginx configuration
        [ ! -d $JAIL/$NF/conf ] && {
            git clone --depth 1 https://github.com/giovannimanzoni/nginx-config $JAIL/$NF/conf/
	    cp $HERE/nginx.conf $JAIL/$NF/conf/
        } >>/tmp/nginx-ee.log 2>&1

        {
            # download default nginx page
            touch /var/www/html-$NF/index.html
            ln -s $JAIL/$NF/conf/sites-available/default $JAIL/$NF/conf/sites-enabled/
            # download nginx systemd service
            [ ! -f /lib/systemd/system/$NF.service ] && {
		_create_service_file
                systemctl enable $NF.service
            }

            # download logrotate configuration
            wget -O /etc/logrotate.d/$NF https://raw.githubusercontent.com/VirtuBox/nginx-ee/master/etc/logrotate.d/nginx

        } >>/tmp/nginx-ee.log 2>&1

    }; then
        echo -ne "       Setting Up Nginx configurations        [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e "       Setting Up Nginx configurations        [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi

}



_nginx_prepare() {

    echo -ne '       Prepare Nignx folder structure         [..]\r'
    if {
	{
	# create nginx user for this nginx pkguser with no home, no login, no password
	if id "$NF" >/dev/null 2>&1; then
		sleep 1
	else
		useradd -r $NF
	fi

        if [ ! -d $JAIL/$NF/conf ]; then
	  mkdir -p $JAIL/$NF/conf
	fi

        # create nginx temp directory
        if [ ! -d /var/lib/$NF ] ; then
	        mkdir -p /var/lib/$NF/{body,fastcgi,proxy,scgi,uwsgi}
		chown -R $NF:root /var/lib/$NF
	fi

        # create nginx cache directory
        if [ ! -d /var/cache/$NF ]; then
		mkdir -p /var/cache/$NF
		chown $NF:root /var/cache/$NF
        fi
        if [ ! -d /var/run/$NF-cache ]; then
		mkdir -p /var/run/$NF-cache
		chown $NF:root /var/run/$NF-cache
        fi
        if [ ! -d /var/lock/$NF-lock ]; then
		mkdir -p /var/lock/$NF-lock
		chown $NF:root /var/lock/$NF-lock
        fi
        if [ ! -d /var/run/$NF-pid ]; then
		mkdir -p /var/run/$NF-pid
		chown $NF:root /var/run/$NF-pid
        fi
        if [ ! -d /var/log/$NF ]; then
            mkdir -p /var/log/$NF
	    touch /var/log/$NF/access.log
	    touch /var/log/$NF/error.log
            chmod 640 /var/log/$NF
            chown -R $NF:root /var/log/$NF
        fi
        if [ ! -d /usr/share/$NF/modules ]; then
		mkdir -p /usr/share/$NF/modules
		chown $NF:root /usr/share/$NF/modules
        fi
	} >> /tmp/nginx-ee.log 2>&1
    }; then
        echo -ne "       Prepare Nginx folder structure         [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e  "       Prepare Nginx folder structure         [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi
}



##################################
# Install gcc7 or gcc8 from PPA
##################################
# gcc7 if Nginx is compiled with RTMP module
# otherwise gcc8 is used

_gcc_ubuntu_setup() {

    if [ ! -f /etc/apt/sources.list.d/jonathonf-ubuntu-gcc-"$(lsb_release -sc)".list ]; then
        {
            echo "### adding gcc repository ###"
            add-apt-repository ppa:jonathonf/gcc -yu
        } >>/dev/null 2>&1
    fi
        echo -ne '       Installing gcc-8                       [..]\r'
        if {
            echo "### installing gcc8 ###"
            apt-get install gcc-8 g++-8 -y
        } >>/dev/null 2>&1; then
            echo -ne "       Installing gcc-8                       [${CGREEN}OK${CEND}]\\r"
            echo -ne '\n'
        else
            echo -e "        Installing gcc-8                      [${CRED}FAIL${CEND}]"
            echo -e '\n      Please look at /tmp/nginx-ee.log\n'
            exit 1
        fi
        {
            # update gcc alternative to use gcc-8 by default
            update-alternatives --remove-all gcc
            update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-8 80 --slave /usr/bin/g++ g++ /usr/bin/g++-8
        } >>/dev/null 2>&1

}

_dependencies_repo() {
    {
        curl -sL https://build.opensuse.org/projects/home:virtubox:nginx-ee/public_key | apt-key add -
        if [ ! -f /etc/apt/sources.list.d/nginx-ee.list ]; then
            if [ "$DISTRO_ID" = "Ubuntu" ]; then
                if [ "$DISTRO_CODENAME" = "xenial" ]; then
                    add-apt-repository ppa:virtubox/brotli -yu
                fi
                echo "deb http://download.opensuse.org/repositories/home:/virtubox:/nginx-ee/xUbuntu_${DISTRO_NUMBER}/ /" >/etc/apt/sources.list.d/nginx-ee.list

            elif [ "$DISTRO_ID" = "Debian" ]; then
                if [ "$DISTRO_CODENAME" = "jessie" ]; then
                    echo 'deb http://download.opensuse.org/repositories/home:/virtubox:/nginx-ee/Debian_8.0/ /' >/etc/apt/sources.list.d/nginx-ee.list
                elif [ "$DISTRO_CODENAME" = "strech" ]; then
                    echo 'deb http://download.opensuse.org/repositories/home:/virtubox:/nginx-ee/Debian_9.0/ /' >/etc/apt/sources.list.d/nginx-ee.list
                else
                    echo 'deb http://download.opensuse.org/repositories/home:/virtubox:/nginx-ee/Debian_10/ /' >/etc/apt/sources.list.d/nginx-ee.list
                fi
            else
                if [ "$DISTRO_CODENAME" = "strech" ]; then
                    echo 'deb http://download.opensuse.org/repositories/home:/virtubox:/nginx-ee/Raspbian_9.0/ /' >/etc/apt/sources.list.d/nginx-ee.list
                else
                    echo 'deb http://download.opensuse.org/repositories/home:/virtubox:/nginx-ee/Raspbian_10/ /' >/etc/apt/sources.list.d/nginx-ee.list
                fi
            fi

        fi
        apt-get update -qq
    } >>/tmp/nginx-ee.log 2>&1
}

##################################
# Install ffmpeg for rtmp module
##################################

_rtmp_setup() {
    echo -ne '       Installing FFMPEG for RTMP module      [..]\r'
    if {

        if [ "$DISTRO_ID" = "Ubuntu" ]; then
            if [ ! -f /etc/apt/sources.list.d/jonathonf-ubuntu-ffmpeg-4-"$(lsb_release -sc)".list ]; then
                add-apt-repository -y ppa:jonathonf/ffmpeg-4 -u
                apt-get install ffmpeg -y
            fi
        else
            apt-get install ffmpeg -y
        fi
    } >>/dev/null 2>&1; then
        echo -ne "       Installing FFMPEG for RMTP module      [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e "       Installing FFMPEG for RMTP module      [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi
}

##################################
# Cleanup modules
##################################

_cleanup_modules() {
    cd "$DIR_SRC" || exit 1
    rm -rf $DIR_SRC/{*.tar.gz,*.deb,nginx,nginx-1.*,pcre,zlib,incubator-pagespeed-*,build_ngx_pagespeed.sh,install,ngx_http_redis,naxsi}
}

##################################
# Download additional modules
##################################

_download_modules() {

    echo -ne '       Downloading additionals modules        [..]\r'
    if {
        echo "### downloading additionals modules ###"
        MODULES='FRiCKLE/ngx_cache_purge openresty/memc-nginx-module
        simpl/ngx_devel_kit openresty/headers-more-nginx-module
        openresty/echo-nginx-module yaoweibin/ngx_http_substitutions_filter_module
        openresty/redis2-nginx-module openresty/srcache-nginx-module
        openresty/set-misc-nginx-module sto/ngx_http_auth_pam_module
        vozlt/nginx-module-vts VirtuBox/ngx_http_redis '
        for MODULE in $MODULES; do
		echo -ne '        download $MODULE'
            _gitget "$MODULE"
        done
        if [ "$RTMP" = "y" ]; then
            { [ -d "$DIR_SRC/nginx-rtmp-module" ] && {
                git -C "$DIR_SRC/nginx-rtmp-module" pull &
            }; } || {
                git clone --depth=1 https://github.com/arut/nginx-rtmp-module.git &
            }
        fi

        # ipscrub module
        { [ -d "$DIR_SRC/ipscrubtmp" ] && {
            git -C "$DIR_SRC/ipscrubtmp" pull origin master &
        }; } || {
            git clone --depth=1 https://github.com/masonicboom/ipscrub.git ipscrubtmp &
        }
        wait
        echo "### additionals modules downloaded ###"
    } >>/tmp/nginx-ee.log 2>&1; then
        echo -ne "       Downloading additionals modules        [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e "        Downloading additionals modules      [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi

}

##################################
# Download zlib
##################################

_download_zlib() {

    echo -ne '       Downloading zlib                       [..]\r'

    if {
        cd "$DIR_SRC" || exit 1
        if [ "$OS_ARCH" = 'x86_64' ]; then
            { [ -d $DIR_SRC/zlib-cf ] && {
                echo "### git pull zlib-cf ###"
                git -c $DIR_SRC/zlib-cf pull
            }; } || {
                echo "### cloning zlib-cf ###"
                git clone --depth=1 https://github.com/cloudflare/zlib.git -b gcc.amd64 $DIR_SRC/zlib-cf
            }
            cd $DIR_SRC/zlib-cf || exit 1
            echo "### make distclean ###"
            make -f Makefile.in distclean
            echo "### configure zlib-cf ###"
            ./configure --prefix=/usr/local/zlib-cf
        else
            echo "### downloading zlib 1.2.11 ###"
            rm -rf zlib
            curl -sL http://zlib.net/zlib-1.2.11.tar.gz | /bin/tar zxf - -C "$DIR_SRC"
            mv zlib-1.2.11 zlib
        fi

    } >>/tmp/nginx-ee.log 2>&1; then
        echo -ne "       Downloading zlib                       [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e "       Downloading zlib                       [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi

}

##################################
# Download ngx_broti
##################################

_download_brotli() {

    cd "$DIR_SRC" || exit 1
    if {
        echo -ne '       Downloading brotli                     [..]\r'
        {
            rm $DIR_SRC/ngx_brotli -rf
            git clone --depth=1 https://github.com/google/ngx_brotli $DIR_SRC/ngx_brotli -q

        } >>/tmp/nginx-ee.log 2>&1

    }; then
        echo -ne "       Downloading brotli                     [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e "       Downloading brotli      [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi

}

##################################
# Download and patch OpenSSL
##################################

_download_openssl_dev() {

    cd "$DIR_SRC" || exit 1
    if {
        echo -ne '       Downloading openssl                    [..]\r'

        {
            if [ -d $DIR_SRC/openssl ]; then
                if [ ! -d $DIR_SRC/openssl/.git ]; then
                    echo "### removing openssl extracted archive ###"
                    rm -rf $DIR_SRC/openssl
                    echo "### cloning openssl ###"
                    git clone --depth=1 https://github.com/openssl/openssl.git $DIR_SRC/openssl
                    cd $DIR_SRC/openssl || exit 1
                    echo "### git checkout commit ###"
                    git checkout $OPENSSL_COMMIT
                else
                    cd $DIR_SRC/openssl || exit 1
                    echo "### reset openssl to master and clean patches ###"
                    git fetch --all
                    git reset --hard origin/master
                    git clean -f
                    git checkout $OPENSSL_COMMIT
                fi
            else
                echo "### cloning openssl ###"
                git clone --depth=1 https://github.com/openssl/openssl.git $DIR_SRC/openssl
                cd $DIR_SRC/openssl || exit 1
                echo "### git checkout commit ###"
                git checkout $OPENSSL_COMMIT
            fi
        } >>/tmp/nginx-ee.log 2>&1

        {
            if [ -d $DIR_SRC/openssl-patch/.git ]; then
                cd $DIR_SRC/openssl-patch || exit 1
                git pull origin master
            else
                git clone --depth=1 https://github.com/VirtuBox/openssl-patch.git $DIR_SRC/openssl-patch
            fi
            cd $DIR_SRC/openssl || exit 1
            # apply openssl ciphers patch
            echo "### openssl ciphers patch ###"
            patch -p1 <../openssl-patch/openssl-equal-3.0.0-dev_ciphers.patch
        } >>/tmp/nginx-ee.log 2>&1

    }; then
        echo -ne "       Downloading openssl                    [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e "       Downloading openssl      [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi

}

##################################
# Download LibreSSL
##################################

_download_libressl() {

    cd "$DIR_SRC" || exit 1
    if {
        echo -ne '       Downloading LibreSSL                   [..]\r'

#        {
            rm -rf $DIR_SRC/libressl
	    mkdir $DIR_SRC/libressl
	    if [ ! -d ${DIR_DOWNLOAD}/libressl ]; then
	      cd $DIR_DOWNLOAD
	      git clone --depth=1 https://github.com/EtchDroid/LibreSSL.git libressl
	      cd ..
	    fi
            cp -R $DIR_DOWNLOAD/libressl/* $DIR_SRC/libressl/
 #       } >>/tmp/nginx-ee.log 2>&1

    }; then
        echo -ne "       Downloading LibreSSL                   [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e "       Downloading LibreSSL      [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi

}

##################################
# Download Naxsi
##################################

_download_naxsi() {

    cd "$DIR_SRC" || exit 1
    if {
        echo -ne '       Downloading naxsi                      [..]\r'
        {

            git clone --depth=1 https://github.com/nbs-system/naxsi.git $DIR_SRC/naxsi -q
            cp -f $DIR_SRC/naxsi/naxsi_config/naxsi_core.rules $JAIL/$NF/conf/naxsi_core.rules

        } >>/tmp/nginx-ee.log 2>&1

    }; then
        echo -ne "       Downloading naxsi                      [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e "       Downloading naxsi      [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi

}

##################################
# Download Pagespeed
##################################

_download_pagespeed() {

    cd "$DIR_SRC" || exit 1
    if {
        echo -ne '       Downloading pagespeed                  [..]\r'

        {
            wget -O build_ngx_pagespeed.sh https://raw.githubusercontent.com/pagespeed/ngx_pagespeed/master/scripts/build_ngx_pagespeed.sh
            chmod +x build_ngx_pagespeed.sh
            if [ "$PAGESPEED_RELEASE" = "1" ]; then
                ./build_ngx_pagespeed.sh --ngx-pagespeed-version latest-beta -b "$DIR_SRC" -y
            else
                ./build_ngx_pagespeed.sh --ngx-pagespeed-version latest-stable -b "$DIR_SRC" -y
            fi
        } >>/tmp/nginx-ee.log 2>&1

    }; then
        echo -ne "       Downloading pagespeed                  [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e "       Downloading pagespeed                  [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi
}

##################################
# Download Nginx
##################################

_download_nginx() {

    cd "$DIR_SRC" || exit 1
    if {
        echo -ne '       Downloading nginx                      [..]\r'

        {
            rm -rf $DIR_SRC/nginx
	    if [ -f ${DIR_DOWNLOAD}/nginx-${NGINX_VER}.tar.gz  ]; then
                #file gia scaricato
                sleep 1
            else
              cd $DIR_DOWNLOAD
              wget  http://nginx.org/download/nginx-${NGINX_VER}.tar.gz
	      cd ..
	    fi
	    cd $DIR_SRC
	    /bin/tar zxf $DIR_DOWNLOAD/nginx-${NGINX_VER}.tar.gz
            mv $DIR_SRC/nginx-${NGINX_VER} nginx
        } >>/tmp/nginx-ee.log 2>&1

    }; then
        echo -ne "       Downloading nginx                      [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e "       Downloading nginx      [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi

}

##################################
# Apply Nginx patches
##################################

_patch_nginx() {

    cd $DIR_SRC/nginx || exit 1
    if {
        echo -ne '       Applying nginx patches                 [..]\r'

        {
            curl -sL https://raw.githubusercontent.com/kn007/patch/master/nginx.patch | patch -p1
            #curl -sL https://raw.githubusercontent.com/kn007/patch/master/nginx_auto_using_PRIORITIZE_CHACHA.patch | patch -p1
        } >>/tmp/nginx-ee.log 2>&1

    }; then
        echo -ne "       Applying nginx patches                 [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e "       Applying nginx patches                 [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi

}

##################################
# Configure Nginx
##################################

_configure_libressl() {
    if {
        echo -ne '       Configuring LibreSSL                   [..]\r'
	cd $STATICLIBSSL
        bash -c "./config \
                  LDFLAGS=-lrt --prefix=${STATICLIBSSL}/.openssl/ >> /tmp/nginx-ee.log 2>&1;"

    }; then
        echo -ne "       Configuring LibreSSL                   [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e  "       Configuring LibreSSL                   [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi

}
##################################
# Configure Nginx
##################################

_configure_nginx() {
    local DEB_CFLAGS
    local DEB_LFLAGS

        if [ "$OS_ARCH" = 'x86_64' ]; then
            if [ "$DISTRO_ID" = "Ubuntu" ]; then
                DEB_CFLAGS='-m64 -march=native -mtune=native -DTCP_FASTOPEN=23 -g -O3 -fstack-protector-strong -flto -ffat-lto-objects -fuse-ld=gold --param=ssp-buffer-size=4 -Wformat -Werror=format-security -Wimplicit-fallthrough=0 -fcode-hoisting -Wp,-D_FORTIFY_SOURCE=2 -gsplit-dwarf'
                DEB_LFLAGS='-lrt -ljemalloc -Wl,-z,relro -Wl,-z,now -fPIC -flto -ffat-lto-objects'
            fi
            ZLIB_PATH='../zlib-cf'
        else
            ZLIB_PATH='../zlib'
        fi

	if [ "$DISTRO_ID" != "Ubuntu" ]; then
		# https://github.com/arut/nginx-rtmp-module/issues/1283
		# https://www.unixteacher.org/blog/speed-up-web-delivery-with-nginx-and-tfo/
		DEB_CFLAGS="$(dpkg-buildflags --get CPPFLAGS) -Wno-error=date-time -Wimplicit-fallthrough=0 -O2 -fstack-protector-strong -DTCP_FASTOPEN=23"
		DEB_LFLAGS="-lrt $(dpkg-buildflags --get LDFLAGS)" # https://gist.github.com/leonklingele/a669803060fa92817f64
	fi

    if {
        echo -ne '       Configuring nginx                      [..]\r'

        # main configuration
        NGINX_BUILD_OPTIONS=" \
	--prefix=$JAIL/$NF \
	--conf-path=$JAIL/$NF/conf/nginx.conf \
	--http-log-path=/var/log/$NF/access.log \
	--error-log-path=/var/log/$NF/error.log \
	--lock-path=/var/lock/$NF-lock/$NF.lock \
	--pid-path=/var/run/$NF-pid/$NF.pid \
	--http-client-body-temp-path=/var/lib/$NF/body \
	--http-fastcgi-temp-path=/var/lib/$NF/fastcgi \
	--http-proxy-temp-path=/var/lib/$NF/proxy \
	--http-scgi-temp-path=/var/lib/$NF/scgi \
	--http-uwsgi-temp-path=/var/lib/$NF/uwsgi \
	--modules-path=/usr/share/$NF/modules"

        # built-in modules
            NGINX_INCLUDED_MODULES=" \
	--with-http_stub_status_module \
        --with-http_realip_module \
        --with-http_auth_request_module \
        --with-http_addition_module \
        --with-http_gzip_static_module \
        --with-http_gunzip_module \
        --with-http_mp4_module \
        --with-http_sub_module \
	--with-http_secure_link_module \
	--with-http_geoip_module \
	--with-http_degradation_module \
	--with-http_xslt_module \
	--with-google_perftools_module \
	--with-stream=dynamic \
	--with-stream_ssl_module \
	--with-stream_realip_module \
	--with-stream_geoip_module=dynamic \
	--with-stream_ssl_preread_module \
	--without-http_ssi_module --without-http_userid_module \
	--without-mail_pop3_module --without-mail_imap_module \
	--without-mail_smtp_module --without-http_split_clients_module \
	--without-http_uwsgi_module --without-http_scgi_module \
	--without-poll_module \
	--without-select_module \
	"

        # third party modules
                NGINX_THIRD_MODULES="--add-module=../ngx_http_substitutions_filter_module \
        --add-module=../srcache-nginx-module \
        --add-module=../ngx_http_redis \
        --add-module=../redis2-nginx-module \
        --add-module=../memc-nginx-module \
        --add-module=../ngx_devel_kit \
        --add-module=../set-misc-nginx-module \
        --add-module=../ngx_http_auth_pam_module \
        --add-module=../nginx-module-vts \
        --add-module=../ipscrubtmp/ipscrub"

	cd $DIR_SRC/nginx
        bash -c "./configure \
                    ${NGX_NAXSI} \
                    --with-cc-opt='$DEB_CFLAGS' \
                    --with-ld-opt='$DEB_LFLAGS' \
                    $NGINX_BUILD_OPTIONS \
                    --build='VirtuBox Nginx-ee' \
                    $NGX_USER \
                    --with-file-aio \
                    --with-threads \
                    $NGX_HPACK \
                    --with-http_v2_module \
                    --with-http_ssl_module \
                    $NGINX_INCLUDED_MODULES \
                    $NGINX_THIRD_MODULES \
                    $NGX_PAGESPEED \
                    $NGX_RTMP \
                    --add-module=../headers-more-nginx-module \
                    --add-module=../ngx_cache_purge \
                    --add-module=../ngx_brotli \
                    --with-zlib=$ZLIB_PATH \
                    $NGX_SSL_LIB \
                    --with-openssl-opt='$OPENSSL_OPT' \
		    --without-http_empty_gif_module \
		    --without-http_autoindex_module \
                    --sbin-path=$JAIL/$NF/sbin/$NF >> /tmp/nginx-ee.log 2>&1;"

    }; then
        echo -ne "       Configuring nginx                      [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e "        Configuring nginx    [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi

}


##################################
# Compile Nginx
##################################

_compile_libressl() {
if {
        echo -ne '       Compiling LibreSSL                     [..]\r'

        {
		cd $STATICLIBSSL
		make install-strip
	} >>/tmp/nginx-ee.log 2>&1
    }; then
        echo -ne "       Compiling LibreSSL                     [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo  -e "       Compiling LibreSSL                     [${CRED}FAIL${CEND}]"
        echo  -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi

}
##################################
# Compile Nginx
##################################

_compile_nginx() {
if {
        echo -ne '       Compiling nginx                        [..]\r'

        {
            # compile Nginx
	    touch $STATICLIBSSL/.openssl/include/openssl/ssl.h
	    cd $DIR_SRC/nginx/
            make -j1
            # Strip debug symbols
            strip --strip-unneeded $DIR_SRC/nginx/objs/nginx

	    # install Nginx
            make install
	} >>/tmp/nginx-ee.log 2>&1
    }; then
        echo -ne "       Compiling nginx                        [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e "       Compiling nginx                        [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi

}

##################################
# Perform final tasks
##################################

_final_tasks() {

    echo -ne '       Performing final steps                 [..]\r'
    if {

        {
            # enable nginx service
            systemctl unmask $NF.service
            systemctl enable $NF.service
            systemctl start $NF.service
            # remove default configuration
	    rm -f $JAIL/$NF/conf/{*.default,*.dpkg-dist}
        } >/dev/null 2>&1

    }; then
        echo -ne "       Performing final steps                 [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e "       Performing final steps                 [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi

    echo -ne '       Checking nginx configuration           [..]\r'

    # check if nginx -t do not return errors
    VERIFY_NGINX_CONFIG=$($NF -t 2>&1 | grep failed)
    if [ -z "$VERIFY_NGINX_CONFIG" ]; then
        {
            systemctl stop $NF
            systemctl start $NF
        } >>/tmp/nginx-ee.log 2>&1
        echo -ne "       Checking nginx configuration           [${CGREEN}OK${CEND}]\\r"
        echo ""
        echo -e "       ${CGREEN}Nginx-ee was compiled successfully !${CEND}"
        echo -e '\n       Installation log : /tmp/nginx-ee.log\n'
    else
        echo -e "       Checking nginx configuration           [${CRED}FAIL${CEND}]"
        echo -e "       Nginx-ee was compiled successfully but there is an error in your nginx configuration"
        echo -e '\nPlease look at /tmp/nginx-ee.log or use the command nginx -t to find the issue\n'
	exit 1
    fi
}



_create_deb() {
if {
	echo -ne '       Performing create .deb                 [..]\r'
	sleep 1
        {
	# creazione .deb
        UND='_'
        checkinstall --type=debian --pkgname=$NF --pkgsource=$NF$UND$NGINX_VER --pakdir=$DIR_SRC --nodoc --maintainer=thedoctorweb.com \
	--pkgversion="$NGINX_VER"  --provides=$NF --requires="libc6, libpcre3, zlib1g" --strip=yes \
	--stripso=yes --backup=yes -y  --install=no
	} >>/tmp/nginx-ee.log 2>&1
    }; then
        echo -ne "       Performing create .deb                 [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e  "       Performing create .deb                 [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi
}



##################################
# Main Setup
##################################

_init
_dependencies_repo
_install_dependencies
_nginx_prepare
_nginx_from_scratch_setup

if [ "$DISTRO_ID" = "Ubuntu" ]; then
    _gcc_ubuntu_setup
fi
if [ "$RTMP" = "y" ]; then
    _rtmp_setup
fi
_cleanup_modules
_download_modules
_download_zlib
_download_brotli
if [ "$NAXSI" = "y" ]; then
    _download_naxsi
fi
if [ "$LIBRESSL" = "y" ]; then
    _download_libressl
    _configure_libressl
    _compile_libressl
else
    if [ "$OPENSSL_LIB" = "2" ]; then
        _download_openssl_dev
    elif [ "$OPENSSL_LIB" = "3" ]; then
        sleep 1
    else
        sleep 1
    fi
fi
if [ "$PAGESPEED" = "y" ]; then
    _download_pagespeed
fi
_download_nginx
_patch_nginx
_configure_nginx
_compile_nginx
_final_tasks
_create_deb
#echo "Give Nginx-ee a GitHub star : https://github.com/VirtuBox/nginx-ee"

