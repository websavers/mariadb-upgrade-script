#!/bin/bash

RED='\033[0;31m'
NC='\033[0m' # No Color

echo "Beginning upgrade procedure."

read -p "Do you wish to back up all existing databases? (y/n) " -n 1 -r
echo # new line
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
  echo "Proceeding with backup to /root/all_databases_pre_maria_upgrade.sql.gz ... This may take 5 minutes or so depending on size of databases."
  if erroutput=$(mysqldump -u admin -p$(cat /etc/psa/.psa.shadow) --all-databases --routines --triggers --max_allowed_packet=1G | gzip >/root/all_databases_pre_maria_upgrade.sql.gz 2>&1); then
    echo "Backups successfully created"
  else
    echo -e "${RED}Error:"
    echo -e "$erroutput ${NC}"
    exit 1
  fi
else
  echo "A risk taker, I see. Carrying on with upgrade procedures without backup..."
fi

read -p "Are you sure you wish to proceed with the upgrade to MariaDB 10.5? (y/n) " -n 1 -r
echo # new line
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  # shellcheck disable=SC2128
  [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
fi

do_mariadb_upgrade() {

  MDB_VER=$1
  #MAJOR_VER=$(rpm --eval '%{rhel}')
  # Gets us ID and VERSION_ID vars
  # shellcheck disable=SC1091
  source /etc/os-release
  MAJOR_VER="${VERSION_ID:0:1}" #ex: 7 or 8 rather than 7.4 or 8.4

  if [[ "$ID" = "almalinux" ]]; then 
    ID=rhel; 
  fi

  echo "Beginning upgrade to MariaDB $MDB_VER..."

  DATE=$(date)
  if [ "$MDB_VER" = "10.0" ]; then

    echo "# MariaDB $MDB_VER CentOS repository list - created $DATE
# 10.0.38 is the latest version in 10.0.x
[mariadb]
name = MariaDB
baseurl = https://archive.mariadb.org/mariadb-10.0.38/yum/centos7-amd64/
module_hotfixes=1
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1" >/etc/yum.repos.d/mariadb.repo

  else
    echo "# MariaDB $MDB_VER CentOS repository list - created $DATE
# http://downloads.mariadb.org/mariadb/repositories/
[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/$MDB_VER/$ID$MAJOR_VER-amd64
module_hotfixes=1
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1" >/etc/yum.repos.d/mariadb.repo
  fi

  echo "- Clearing mariadb repo cache"
  if erroutput=$(yum clean all --disablerepo="*" --enablerepo=mariadb 2>&1); then
    echo "mariadb repo cache cleared"
  else
    echo -e "${RED}Failed to clear mariadb repo cache"
    echo -e "$erroutput ${NC}"
  fi
  echo "- Stopping current db server"
  if systemctl | grep -i "mariadb.service"; then
    systemctl stop mariadb
  elif systemctl | grep -i "mysql.service"; then
    systemctl stop mysql
  fi

  echo "- Removing packages"
  rpm --quiet -e --nodeps MariaDB-server
  rpm --quiet -e --nodeps mariadb-server
  rpm --quiet -e --nodeps mysql-common mysql-libs mysql-devel mariadb-backup mariadb-gssapi-server

  echo "- Updating and installing packages"
  yum -y -q update MariaDB-*
  yum -y -q install MariaDB-server MariaDB MariaDB-gssapi-server

  echo "- Starting MariaDB $MDB_VER"
  if [ "$MDB_VER" = "10.0" ]; then
    systemctl restart mysql
  else
    systemctl restart mariadb
  fi

  echo "- Running mysql_upgrade"
  MYSQL_PWD=$(cat /etc/psa/.psa.shadow) mysql_upgrade -uadmin
}

MySQL_VERS_INFO=$(mysql --version)

#Consistency in repo naming, if one already exists
if [ -f "/etc/yum.repos.d/MariaDB.repo" ]; then
  mv /etc/yum.repos.d/MariaDB.repo /etc/yum.repos.d/mariadb.repo
fi

systemctl stop sw-cp-server

case $MySQL_VERS_INFO in
*"Distrib 5.5."*)
  echo "MySQL / MariaDB 5.5 detected. Proceeding with 5.5 -> 10.0 -> 10.5"
  rpm -e --nodeps mysql-server
  mv -f /etc/my.cnf /etc/my.cnf.bak
  do_mariadb_upgrade '10.0'
  do_mariadb_upgrade '10.5'
  ;;

*"Distrib 5.6."*)
  echo "MySQL or Percona 5.6 detected. Proceeding with 5.6 -> 10.0 -> 10.5"
  # shellcheck disable=SC2143
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

  mv -f /etc/my.cnf /etc/my.cnf.bak

  do_mariadb_upgrade '10.0'
  do_mariadb_upgrade '10.1'
  do_mariadb_upgrade '10.2'
  do_mariadb_upgrade '10.5'
  ;;

*"Distrib 10.0"*)
  echo "MariaDB 10.0 detected. Proceeding with upgrade to 10.5"
  mv -f /etc/my.cnf /etc/my.cnf.bak
  do_mariadb_upgrade '10.1'
  do_mariadb_upgrade '10.2'
  do_mariadb_upgrade '10.5'
  ;;

*"Distrib 10.1"*)
  echo "MariaDB 10.1 detected. Proceeding with upgrade to 10.5"
  do_mariadb_upgrade '10.2'
  do_mariadb_upgrade '10.5'
  ;;

*"Distrib 10.2"*)
  echo "MariaDB 10.2 detected. Proceeding with upgrade to 10.5"
  do_mariadb_upgrade '10.5'
  ;;

*"Distrib 10.3"*)
  echo "MariaDB 10.3 detected. Proceeding with upgrade to 10.5"
  do_mariadb_upgrade '10.5'
  ;;
*"Distrib 10.4"*)
  echo "MariaDB 10.4 detected. Proceeding with upgrade to 10.5"
  do_mariadb_upgrade '10.5'
  ;;

*"Distrib 10.5"*)
  echo "Already at 10.5. Exiting."
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
sed -i 's/^\[mysqld\]/&\nmax_allowed_packet=256M/' /etc/my.cnf.d/server.cnf
sed -i 's/^\[mysqld\]/&\nopen_files_limit=8192/' /etc/my.cnf.d/server.cnf

# Enable the event scheduler like it was in 10.4 and earlier
sed -i 's/^\[mariadb\]/&\nevent_scheduler=ON/' /etc/my.cnf.d/server.cnf

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

echo "Fixing Plesk bug MDEV-27834"
# BUGFIX MDEV-27834: https://support.plesk.com/hc/en-us/articles/4419625529362-Plesk-Installer-fails-when-MariaDB-10-5-or-10-6-is-installed

mdb_ver=$(rpm -q MariaDB-shared | awk -F- '{print $3}')

if echo "$mdb_ver" | grep -q 10.3.34; then

  #rpm -Uhv --oldpackage --justdb http://yum.mariadb.org/10.3/rhel8-amd64/rpms/MariaDB-shared-10.3.32-1.el8.x86_64.rpm
  yum -y -q downgrade MariaDB-shared-10.3.32
  echo "exclude=MariaDB-shared-10.3.34" >>/etc/yum.repos.d/mariadb.repo

elif echo "$mdb_ver" | grep -q 10.4.24; then

  #rpm -Uhv --oldpackage --justdb http://yum.mariadb.org/10.4/rhel8-amd64/rpms/MariaDB-shared-10.4.22-1.el8.x86_64.rpm
  yum -y -q downgrade MariaDB-shared-10.4.22
  echo "exclude=MariaDB-shared-10.4.24" >>/etc/yum.repos.d/mariadb.repo

elif echo "$mdb_ver" | grep -q 10.5.15; then

  #rpm -Uhv --oldpackage --justdb http://yum.mariadb.org/10.5/rhel8-amd64/rpms/MariaDB-shared-10.5.13-1.el8.x86_64.rpm
  yum -y -q downgrade MariaDB-shared-10.5.13
  echo "exclude=MariaDB-shared-10.5.15" >>/etc/yum.repos.d/mariadb.repo

fi

# If you needed the above to install Plesk updates, now run `plesk installer update`

# END BUGFIX

echo "Informing Plesk of Changes"
#plesk bin service_node --update local
plesk sbin packagemng -sdf
restorecon -v /var/lib/mysql/*

systemctl restart sw-cp-server
systemctl daemon-reload

# Allow commands like mysqladmin processlist without un/pw
# Needed for logrotate
plesk db "install plugin unix_socket soname 'auth_socket';" >/dev/null 2>&1
plesk db "CREATE USER 'root'@'localhost' IDENTIFIED VIA unix_socket;" >/dev/null 2>&1
plesk db "GRANT RELOAD ON *.* TO 'root'@'localhost';" >/dev/null 2>&1
