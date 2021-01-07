#!/bin/bash

echo "Beginning upgrade procedure."
while true; do
    read -p "Do you wish to back up all existing databases?" yn
    case $yn in
      [Yy]* )
        echo "Proceeding with backup to /root/all_databases_pre_maria_10_4_upgrade.sql.gz ... Stand by."
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

read -p "Are you sure you wish to proceed with the upgrade to MariaDB 10.4? (y/n)" -n 1 -r
echo    # new line
if [[ ! $REPLY =~ ^[Yy]$ ]] ; then
    [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
fi

CENTOS_MAJOR_VER=$(rpm --eval '%{centos_ver}')

if [ "$CENTOS_MAJOR_VER" = '7' ]; then
  systemctl stop sw-cp-server
else
  service sw-cp-server stop
fi

#Consistency in repo naming, if one already exists
if [ -f "/etc/yum.repos.d/MariaDB.repo" ] ; then
  mv /etc/yum.repos.d/MariaDB.repo /etc/yum.repos.d/mariadb.repo
fi


do_mariadb_upgrade(){

  MDB_VER=$1
  CENTOS_MAJOR_VER=$(rpm --eval '%{centos_ver}')
  echo "Upgrading to MariaDB $MDB_VER..."

  DATE=$(date)
  echo "# MariaDB $MDB_VER CentOS repository list - created $DATE
# http://downloads.mariadb.org/mariadb/repositories/
[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/$MDB_VER/centos$CENTOS_MAJOR_VER-amd64
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1" > /etc/yum.repos.d/mariadb.repo

  mv -f /etc/my.cnf /etc/my.cnf.bak

  yum -y install MariaDB
  yum -y update MariaDB-*
  
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

MySQL_VERS_INFO=$(mysql --version)

case $MySQL_VERS_INFO in
    *"Distrib 5.5."*)
      echo "MySQL / MariaDB 5.5 detected. Proceeding with 5.5 -> 10.0 -> 10.4"
      rpm -e --nodeps mysql-server
      do_mariadb_upgrade '10.0'
      #do_mariadb_upgrade '10.1'
      do_mariadb_upgrade '10.4'
      ;;
    
    *"Distrib 5.6."*)
      echo "MySQL or Percona 5.6 detected. Proceeding with 5.6 -> 10.0 -> 10.4"
      
      if [[ $(rpm -qa | grep Percona-Server-server) ]]; then
        # Removing Percona server and disabling repo
        rpm -e --nodeps Percona-Server-server-56
        rpm -e --nodeps Percona-Server-shared-56
        rpm -e --nodeps Percona-Server-client-56
        rpm -e --nodeps Percona-Server-shared-51
        sed -i 's/^enabled = 1/enabled = 0/' /etc/yum.repos.d/percona-original-release.repo
      else
        # Removing MySQL 5.6 server
        rpm -e --nodeps mysql-server
      fi
      
      do_mariadb_upgrade '10.0'
      #do_mariadb_upgrade '10.1'
      do_mariadb_upgrade '10.4'
      ;;
      
    *"Distrib 10.0"*)
      echo "MariaDB 10.1 detected. Proceeding with upgrade to 10.4"
      #do_mariadb_upgrade '10.1'
      do_mariadb_upgrade '10.4'
      ;;
      
    *"Distrib 10.1"*)
      echo "MariaDB 10.1 detected. Proceeding with upgrade to 10.4"
      do_mariadb_upgrade '10.4'
      ;;
      
    *"Distrib 10.2"*)
      echo "MariaDB 10.2 detected. Proceeding with upgrade to 10.4"
      do_mariadb_upgrade '10.4'
      ;;
      
    *"Distrib 10.3"*)
      echo "MariaDB 10.3 detected. Proceeding with upgrade to 10.4"
      do_mariadb_upgrade '10.4'
      ;;
      
    *"Distrib 10.4"*)
      echo "Already at 10.4. Exiting."
      exit 1
      ;;
      

      
    *)
      echo "Error. Unknown initial MySQL version. Aborting."
      exit 1
      ;;
esac


######
# At completion of all upgrades
######

# Increase MySQL/MariaDB Packet Size and open file limit. Set log file to default logrotate location
sed -i 's/^\[mysqld\]/&\nlog-error=\/var\/lib\/mysql\/mysqld.log/' /etc/my.cnf.d/server.cnf
sed -i 's/^\[mysqld\]/&\nmax_allowed_packet=64M/' /etc/my.cnf.d/server.cnf
sed -i 's/^\[mysqld\]/&\nopen_files_limit=8192/' /etc/my.cnf.d/server.cnf

# If the log file hasn't been aliased yet, deal with that
if [ -f "/var/log/mysqld.log" ]; then
  mv /var/log/mysqld.log /var/log/mysqld.log.bak
elif [ -L "/var/log/mysqld.log" ]; then #symlink
  rm -f /var/log/mysqld.log
fi
# Link /var/log/mysqld.log to mariadb log file location
ln -s /var/lib/mysql/mysqld.log /var/log/mysqld.log

echo "Ensuring systemd doesn't mix up mysql and mariadb"
systemctl stop mysql
systemctl stop mariadb
chkconfig --del mysql
systemctl disable mysql
systemctl disable mariadb
systemctl enable mariadb.service
systemctl start mariadb.service

echo "Informing Plesk of Changes..."
plesk bin service_node --update local
plesk sbin packagemng -sdf

if [ "$CENTOS_MAJOR_VER" = '7' ]; then
  systemctl restart mysql
  systemctl restart sw-cp-server
else
  service mysql restart
  service sw-cp-server restart
fi

# Allow commands like mysqladmin processlist without un/pw
# Needed for logrotate
plesk db "install plugin unix_socket soname 'auth_socket'; CREATE USER 'root'@'localhost' IDENTIFIED VIA unix_socket;"
plesk db "GRANT RELOAD ON *.* TO 'root'@'localhost';"

# Update systemctl to recognize latest mariadb
if [ "$CENTOS_MAJOR_VER" = '7' ]; then
  systemctl daemon-reload
fi
