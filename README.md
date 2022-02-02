# Description
A script to upgrade MariaDB from 5.5/10.x to 10.5 on CentOS 7 or AlmaLinux 8 (likely works with Rocky Linux too) and intended for use with Plesk. Configures MariaDB so you can easily run mysqladmin without entering admin DB credentials.

It is integrated with Plesk tools to provide back up, upgrade DBs, and notify Plesk of version changes.

# Usage
`./mariadb-upgrade.sh`
