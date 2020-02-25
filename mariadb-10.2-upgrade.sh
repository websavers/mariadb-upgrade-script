#!/bin/bash

echo "Beginning upgrade procedure."
while true; do
    read -p "Do you wish to back up all existing databases?" yn
    case $yn in
      [Yy]* )
        echo "Proceeding with backup to /root/all_databases_pre_maria_10_2_upgrade.sql.gz ... Stand by."
        MYSQL_PWD=`cat /etc/psa/.psa.shadow` mysqldump -u admin --all-databases --routines --triggers | gzip > /root/all_databases_pre_maria_10_2_upgrade.sql.gz
        break
        ;;
      [Nn]* )
        echo "A risk taker, I see. Carrying on with upgrade procedures..."
        break
        ;;
  * ) echo "Please answer yes or no.";;
esac
done

MySQL_VERS_INFO=$(mysql --version)
case $MySQL_VERS_INFO in
    *"Distrib 5.5."*)
      UPGRADE_STEPS=3
      echo "MySQL / MariaDB 5.5 detected."
      while true; do
          read -p "Do you wish to attempt to upgrade through to 10.2?" yn
          case $yn in
            [Yy]* )
            CENTOS_MAJOR_VER=$(rpm --eval '%{centos_ver}')
            echo "# MariaDB 10.0 CentOS repository list - created 2019-02-20 23:18 UTC
# http://downloads.mariadb.org/mariadb/repositories/
[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/10.0/centos$CENTOS_MAJOR_VER-amd64
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1" > /etc/yum.repos.d/mariadb.repo
            break
            ;;
        [Nn]* ) exit;;
        * ) echo "Please answer yes or no.";;
    esac
done
      ;;
    *"Distrib 10.0"*)
      echo "MariaDB 10.0 detected. Proceeding with full upgrade to 10.2"
      UPGRADE_STEPS='2'
      ;;
    *"Distrib 10.1"*)
      echo "MariaDB 10.1 detected. Proceeding with partial upgrade to 10.2"
      UPGRADE_STEPS='1'
      ;;
    *"Distrib 10.2"*)
      echo "Already at 10.2. Exiting."
      exit 1
      ;;
    *)
      echo "Error. Unknown initial MySQL version. Aborting."
      exit 1
      ;;
    esac
read -p "Are you sure you wish to proceed with the upgrade to 10.2? (y/n)" -n 1 -r
echo    # (optional) move to a new line
if [[ ! $REPLY =~ ^[Yy]$ ]] ; then
    [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
fi

if [ "$CENTOS_MAJOR_VER" = '7' ]; then
  systemctl stop sw-cp-server
else
  service sw-cp-server stop
fi

#install MariaDB 10

if [ -f "/etc/yum.repos.d/MariaDB.repo" ] ; then
  mv /etc/yum.repos.d/MariaDB.repo /etc/yum.repos.d/mariadb.repo
fi

if [ -f "/etc/yum.repos.d/mariadb.repo" ] ; then
  echo "MariaDB detected. Proceeding with upgrade..."
else
  echo "No MariaDB repo detected at /etc/yum.repos.d/mariadb.repo -- Aborting."
  exit 1
fi

do_mariadb_upgrade(){

  MDB_VER=$1
  CENTOS_MAJOR_VER=$(rpm --eval '%{centos_ver}')
  echo "Upgrading to MariaDB $MDB_VER..."

  echo "# MariaDB $MDB_VER CentOS repository list - created 2019-02-20 23:18 UTC
# http://downloads.mariadb.org/mariadb/repositories/
[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/$MDB_VER/centos$CENTOS_MAJOR_VER-amd64
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1" > /etc/yum.repos.d/mariadb.repo

  mv /etc/my.cnf /etc/my.cnf.bak

  yum -y update
  if [ "$CENTOS_MAJOR_VER" = '7' ]; then
    systemctl stop mysql
  else
    service mysql stop
  fi
  rpm -e --nodeps MariaDB-server
  yum -y install MariaDB-server

  if [ "$CENTOS_MAJOR_VER" = '7' ]; then
    systemctl restart mysql
  else
    service mysql restart
  fi

  MYSQL_PWD=`cat /etc/psa/.psa.shadow` mysql_upgrade -uadmin

}

case $UPGRADE_STEPS in
  1)
    do_mariadb_upgrade '10.2'
    ;;
  2)
    do_mariadb_upgrade '10.1'
    do_mariadb_upgrade '10.2'
    ;;
  3)
    do_mariadb_upgrade '10.0'
    do_mariadb_upgrade '10.1'
    do_mariadb_upgrade '10.2'
  ;;
  *)
    echo Error. Aborting.
    exit 1
    ;;
esac

######
# At completion of all upgrades
######

# Inform Plesk
plesk sbin packagemng -sdf

# Increase MySQL/MariaDB Packet Size and open file limit. Set log file to default logrotate location
sed -i 's/^\[mysqld\]/&\nlog-error=\/var\/lib\/mysql\/mysqld.log/' /etc/my.cnf.d/server.cnf
sed -i 's/^\[mysqld\]/&\nmax_allowed_packet=64M/' /etc/my.cnf.d/server.cnf
sed -i 's/^\[mysqld\]/&\nopen_files_limit=8192/' /etc/my.cnf.d/server.cnf
if [ "$CENTOS_MAJOR_VER" = '7' ]; then
  systemctl restart mysql
  systemctl restart sw-cp-server
else
  service mysql restart
  service sw-cp-server restart
fi
# If the log file hasn't been aliased yet, deal with that
if [ -f "/var/log/mysqld.log" ]; then
  mv /var/log/mysqld.log /var/log/mysqld.log.bak
elif [ -L "/var/log/mysqld.log" ]; then #symlink
  rm -f /var/log/mysqld.log
fi
# Link /var/log/mysqld.log to mariadb log file location
ln -s /var/lib/mysql/mysqld.log /var/log/mysqld.log

# Set /root/.my.cnf to allow commands like mysqladmin processlist without un/pw
# Needed for logrotate
MYSQL_PWD=$(cat /etc/psa/.psa.shadow) && echo "[mysqladmin]
user=admin
password=$MYSQL_PWD" > /root/.my.cnf
chmod 600 /root/.my.cnf
MYSQL_PWD=''

# Update systemctl to recognize latest mariadb
if [ "$CENTOS_MAJOR_VER" = '7' ]; then
  systemctl daemon-reload
fi
