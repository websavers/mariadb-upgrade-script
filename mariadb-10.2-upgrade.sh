#!/bin/bash

echo "Beginning upgrade procedure."
while true; do
    read -p "Do you wish to back up all existing databases?" yn
    case $yn in
      [Yy]* )
        echo "Proceeding with backup to /tmp/all-databases.sql. Stand by."
        MYSQL_PWD=`cat /etc/psa/.psa.shadow` mysqldump -u admin --all-databases --routines --triggers > /tmp/all-databases.sql
        break
        ;;
      [Nn]* )
        echo "A risk taker, I see. Carrying on with upgrade procedures."
        break
        ;;
  * ) echo "Please answer yes or no.";;
esac

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

#install MariaDB 10

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
plesk sbin packaging -sdf

# If the log file hasn't been aliased yet, deal with that
if [ -f "/var/log/mysqld.log" ]; then
  mv /var/log/mysqld.log /var/log/mysqld.log.bak
  # Link mysqld.log to mariadb log file location
  ln -s /var/lib/mysql/$(hostname -f).err /var/log/mysqld.log
fi

# Update systemctl to recognize latest mariadb
systemctl daemon-reload
