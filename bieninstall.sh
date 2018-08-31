#!/bin/bash

# In this version we asume you have copied fusionpbx.pgsql into /tmp yourself if you want it

# FusionPbx Bien install script with Bien defaults
# add local nl_NL.UTF8
echo "generate locales for nl-NL"
sed -i '/^#.* en_US.* /s/^#//' /etc/locale.gen
sed -i '/^#.* nl_NL.* /s/^#//' /etc/locale.gen
locale-gen

# FusionPBX Post install scripts
echo "install git to pull FusionPBX install script"
apt-get update && apt-get install -y --force-yes git
cd /usr/src
git clone https://github.com/fusionpbx/fusionpbx-install.sh.git
chmod 755 -R /usr/src/fusionpbx-install.sh
cd /usr/src/fusionpbx-install.sh/debian

# I don't want fail2ban & iptables so remove it from the script
echo "remove fail2ban and iptables from install batch"
sed -i 's/resources\/fail2ban.sh/# resources\/fail2ban.sh/' install.sh
sed -i 's/systemctl restart fail2ban/# systemctl restart fail2ban/' install.sh
sed -i 's/resources\/iptables.sh/# resources\/iptables.sh/' install.sh

# lsb-release is installed without the -y option in environment.sh
# to prevent the script asking to type y we install it our selves first
apt-get update && apt-get install -y lsb-release


# now run the FusionPBX installer
echo "run the FusionPBX installer"
source ./install.sh

# set peer to trust  in Postgresql database
echo "set peer to trust in postgres config file"
sed -i '/^local\s*all\s*all.*/s/peer/trust/' /etc/postgresql/10/main/pg_hba.conf
# restart postgresql.
echo "restart postgresql"
systemctl restart postgresql

# store the fusionpbx password generated by the install programm in $db_password
echo "fetch the random generated fusionpbx database password"
db_password=$(grep db_password /etc/fusionpbx/config.php |awk -F\' '{print $2}')

# edit freeswitch vars file
# part to set the $${dsn} in the .xml files
echo "store the db_password in the freeswitch vars.xml"
sed -i '/<!-- Defaults -->/a <X-PRE-PROCESS cmd="set" data="dsn=pgsql://hostaddr=127.0.0.1 dbname=freeswitch user=fusionpbx password='"$db_password"' options='\''-c client_min_messages=NOTICE'\'' application_name='\''freeswitch'\''" />' /etc/freeswitch/vars.xml

# remove PCMU codec
echo "remove PCMU codec and change us_ring to fr_ring"
sed -i 's/PCMU\,//g' /etc/freeswitch/vars.xml
sed -i 's/$${us-ring}/$${fr-ring}/g' /etc/freeswitch/vars.xml

# vervang <!-- <param name="core-db-dsn" value="$${dsn}" /> -->
# voor <param name="core-db-dsn" value="$${dsn}" />
echo "change the xml files to use postgresql"
echo "	switch.conf.xml"
sed -i 's/<\!--\s*<param name="core-db-dsn" value="$${dsn}"\s*\/>\s*-->/<param name="core-db-dsn" value="$${dsn}" \/>/'  /etc/freeswitch/autoload_configs/switch.conf.xml

# vervang <!-- <param name="odbc-dsn" value="$${dsn}"/> -->
# in db.conf.xml, directory.conf.xml, fifo.conf.xml & voicemail.conf.xml
echo "	db.conf.xml"
sed -i 's/<\!--\s*<param name="odbc-dsn" value="$${dsn}"\s*\/>\s*-->/<param name="odbc-dsn" value="$${dsn}" \/>/'  /etc/freeswitch/autoload_configs/db.conf.xml
echo "	directory.conf.xml"
sed -i 's/<\!--\s*<param name="odbc-dsn" value="$${dsn}"\s*\/>\s*-->/<param name="odbc-dsn" value="$${dsn}" \/>/'  /etc/freeswitch/autoload_configs/directory.conf.xml
echo "	fifo.conf.xml"
sed -i 's/<\!--\s*<param name="odbc-dsn" value="$${dsn}"\s*\/>\s*-->/<param name="odbc-dsn" value="$${dsn}" \/>/'  /etc/freeswitch/autoload_configs/fifo.conf.xml
echo "	voicemail.conf.xml"
sed -i 's/<\!--\s*<param name="odbc-dsn" value="$${dsn}"\s*\/>\s*-->/<param name="odbc-dsn" value="$${dsn}" \/>/'  /etc/freeswitch/autoload_configs/voicemail.conf.xml
echo "	callcenter.conf.xml"
sed -i 's/<\!--\s*<param name="odbc-dsn" value="$${dsn}"\s*\/>\s*-->/<param name="odbc-dsn" value="$${dsn}" \/>/'  /etc/freeswitch/autoload_configs/callcenter.conf

# activeer blf functies in /etc/freeswitch/autoload_configs/lua.conf.xml
echo "activate blf for call_flow, dnd and forward"
sed -i 's/<\!--\s*<param name="startup-script" value="call_flow_monitor.lua"\s*\/>\s*-->/<param name="startup-script" value="call_flow_monitor.lua"\/>/'  /etc/freeswitch/autoload_configs/lua.conf.xml
sed -i 's/<\!--\s*<param name="startup-script" value="blf_subscribe.lua flow"\s*\/>\s*-->/<param name="startup-script" value="blf_subscribe.lua flow"\/>/'  /etc/freeswitch/autoload_configs/lua.conf.xml
sed -i 's/<\!--\s*<param name="startup-script" value="blf_subscribe.lua dnd"\s*\/>\s*-->/<param name="startup-script" value="blf_subscribe.lua dnd"\/>/'  /etc/freeswitch/autoload_configs/lua.conf.xml
sed -i 's/<\!--\s*<param name="startup-script" value="blf_subscribe.lua forward"\s*\/>\s*-->/<param name="startup-script" value="blf_subscribe.lua forward"\/>/'  /etc/freeswitch/autoload_configs/lua.conf.xml

# part to import the Bien template fusionbx postgresql database
# postgresql database dump created with:
# su postgres -
# cd
# pg_dump -Fc fusionpbx > fusionpbx.pgsql
# exit

# restore in new setup
# to restore copy the fusionpbx.pgsql file to new server
# in /tmp and make readable for all
if [ -e /tmp/fusionpbx.pgsql ]
then
    echo "template database file /tmp/fusionpbx.pgsql found"
    chmod +r /tmp/fusionpbx.pgsql
    cd /tmp
    echo "restore the database"
    su -c "pg_restore --clean -d fusionpbx /tmp/fusionpbx.pgsql" -s /bin/sh postgres
    # upgrade the sql schema if database was from ealier release
    # no harm in doing it so so it anyway
    echo "execute a database schema upgrade; just in case"
    cd /var/www/fusionpbx
    /usr/bin/php /var/www/fusionpbx/core/upgrade/upgrade.php
else
    echo "no template database found to restore"
fi

# part to delete freeswitch .db files
echo "get rid of the sqlite database files"
rm /var/lib/freeswitch/db/*.db
if ls /var/lib/freeswitch/db/*.db >/dev/null 2>&1;
then
	echo "files where not deleted correctly; try by hand later"
else
	echo ".db files were correctly removed"
fi
echo "restart memcached"
systemctl restart memcached
echo "restart postgresql"
systemctl restart postgresql
echo "restart freeswitch"
systemctl restart freeswitch
echo ""
echo ""
echo ""
echo ""
echo ""
if [ -e /tmp/fusionpbx.pgsql ]
then
	echo "login with admin@10.11.12.50"
	echo "use password clviXHEaacGf1Mee"
else
	echo "if you can not login with admin"
	echo "reset the admin password by renaming /etc/freeswitch/conf.php to conf.php.org"
	echo "in the fusionpbx gui you can now setup fusionpbx"
	echo "for the postgresql connection use user fusionpbx with password $db_password" 
fi
# login with admin@<imported domain>
# ***** NB Admin password from 10.11.12.50 database copy
# admin password clviXHEaacGf1Mee

