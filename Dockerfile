FROM php:7.4-apache
MAINTAINER Phil Kulin <schors@gmail.com>

ENV USER_GID=800
ENV USER_UID=800
ENV USER_NAME=nagios
ENV GROUP_NAME=nagios
ENV APACHE_CONFDIR /etc/apache2
ENV APACHE_ENVVARS $APACHE_CONFDIR/envvars

ENV NAGIOS_VOLUME          /usr/local/vnagios
ENV NAGIOS_HOME            /usr/local/nagios
ENV NAGIOS_USER            nagios
ENV NAGIOS_UID             800
ENV NAGIOS_GROUP           nagios
ENV NAGIOS_GID             800
#ENV NAGIOSADMIN_USER       nagiosadmin
#ENV NAGIOSADMIN_PASS       nagios
ENV APACHE_RUN_USER        nagios
ENV APACHE_RUN_GROUP       nagios
ENV NAGIOS_TIMEZONE        UTC
ENV DEBIAN_FRONTEND        noninteractive
ENV NAGIOS_BRANCH          nagios-4.4.6
ENV NAGIOS_PLUGINS_BRANCH  release-2.3.3
ENV NRPE_BRANCH            nrpe-4.0.3

VOLUME "${NAGIOS_HOME}/var" "${NAGIOS_HOME}/etc" "/tmp"

RUN groupadd --system -g $NAGIOS_GID $NAGIOS_GROUP &&\
    useradd --system -d $NAGIOS_HOME -g $NAGIOS_GROUP    $NAGIOS_USER

RUN apt-get update && apt-get dist-upgrade -y && apt-get autoremove -y && \
    apt-get install -q -y  --no-install-recommends \
        msmtp-mta                           \
        ca-certificates                     \
        build-essential                     \
        iputils-ping                        \
        dnsutils                            \
        fping                               \
        git                                 \
        smbclient                           \
        snmp                                \
        snmpd                               \
        unzip                               \
        python3                             \ 
        autoconf                            \
        automake                            \
        libwww-perl                         \
        libnagios-object-perl               \
        libnet-snmp-perl                    \
        libnet-snmp-perl                    \
        libnet-tftp-perl                    \
        libnet-xmpp-perl                    \
        libssl-dev                          \
        wget                                \
        apache2-dev                         \
        locales-all                         \
        libfreetype6-dev                    \
        libjpeg62-turbo-dev                 \
        libmcrypt-dev                       \
        libpng-dev                          \
        libicu-dev                          \
        libssl-dev                          \
        libxml2-dev                         \
        libxslt-dev                         \
        libbz2-dev                          \
        libtidy-dev                         \
        libexif-dev                         \
        libcurl4-openssl-dev                \
        libc-client-dev libkrb5-dev         \
        imagemagick                         \
        mailutils                           \
        libgd-dev                           \
        libgd-tools                         \
        zip

RUN cd /tmp                                                                          && \
    git clone https://github.com/NagiosEnterprises/nagioscore.git -b $NAGIOS_BRANCH  && \
    cd nagioscore                                                                    && \
    ./configure                                  \
        --prefix=${NAGIOS_VOLUME}                  \
        --exec-prefix=${NAGIOS_HOME}             \
        --datarootdir=${NAGIOS_HOME}/share      \
        --with-httpd_conf=/etc/apache2/conf.d   \
        --with-cgibindir=${NAGIOS_HOME}/sbin    \
        --enable-event-broker                    \
        --with-gd-lib=/usr                     \
        --with-gd-inc=/usr                     \
        --with-command-user=${NAGIOS_USER}    \
        --with-command-group=${NAGIOS_GROUP}  \
        --with-nagios-user=${NAGIOS_USER}        \
        --with-nagios-group=${NAGIOS_GROUP}                                          && \
    mkdir -p /etc/apache2/conf.d                                                     && \
    make all                                                                         && \
    make install                                                                     && \
    make install-config                                                              && \
    make install-commandmode                                                         && \
    #make install-webconf                                                             && \
    make clean                                                                       && \
    cd /tmp && rm -Rf nagioscore

RUN cd /tmp                                                                                   && \
    git clone https://github.com/nagios-plugins/nagios-plugins.git -b $NAGIOS_PLUGINS_BRANCH  && \
    cd nagios-plugins                                                                         && \
    ./tools/setup                                                                             && \
    ./configure                                                 \
        --prefix=${NAGIOS_HOME}                                 \
        --with-ipv6                                             \
        --with-ping6-command="/bin/ping6 -n -U -W %d -c %d %s"  \
                                                                                              && \
    make                                                                                      && \
    make install                                                                              && \
    make clean                                                                                && \
    mkdir -p /usr/lib/nagios/plugins                                                          && \
    ln -sf ${NAGIOS_HOME}/libexec/utils.pm /usr/lib/nagios/plugins                            && \
    cd /tmp && rm -Rf nagios-plugins

RUN cd /tmp                                                                  && \
    git clone https://github.com/NagiosEnterprises/nrpe.git -b $NRPE_BRANCH  && \
    cd nrpe                                                                  && \
    ./configure                                   \
        --with-ssl=/usr/bin/openssl               \
        --with-ssl-lib=/usr/lib/x86_64-linux-gnu  \
                                                                             && \
    make check_nrpe                                                          && \
    cp src/check_nrpe ${NAGIOS_HOME}/libexec/                                && \
    make clean                                                               && \
    cd /tmp && rm -Rf nrpe

RUN apt-get install -q -y  --no-install-recommends libonig-dev

RUN docker-php-ext-install -j$(nproc) gettext mbstring curl ctype json iconv intl opcache bcmath sockets sysvmsg sysvsem sysvshm pcntl\
    && docker-php-ext-configure intl \
    && docker-php-ext-install intl \
    && docker-php-ext-configure gd --with-freetype=/usr/include/ --with-jpeg=/usr/include/ \
    && docker-php-ext-install -j$(nproc) gd exif \
    && wget https://github.com/gnif/mod_rpaf/archive/stable.zip -O /tmp/stable.zip &&  unzip  /tmp/stable -d /tmp && rm -f /tmp/stable.zip \
    && make -C /tmp/mod_rpaf-stable -f /tmp/mod_rpaf-stable/Makefile && make -C /tmp/mod_rpaf-stable -f /tmp/mod_rpaf-stable/Makefile install \
    && rm -rf /tmp/mod_rpaf-stable

#COPY etc/php.ini /usr/local/etc/php/
COPY etc/mpm_prefork.conf /etc/apache2/mods-available/
COPY etc/rpaf.conf etc/rpaf.load /etc/apache2/mods-available/
COPY etc/apache-logformat.conf /etc/apache2/conf-available/logformat.conf
COPY etc/ssl-env.conf /etc/apache2/conf-available/
COPY etc/nagios.conf /etc/apache2/conf-available/
COPY etc/msmtprc /etc/msmtprc
COPY logos/ /usr/local/nagios/share/images/logos/

RUN a2enmod headers \
    && a2enmod expires \
    && a2enmod status \
    && a2enmod cgi \
    && a2enconf logformat \
    && a2enmod rewrite \
    && a2enmod rpaf \
    && a2enconf nagios \
    && a2enconf ssl-env 

