# Description
A script to upgrade MariaDB from 5.5/10.0/10.1 to 10.2 on CentOS 6 or 7 and intended for use with Plesk Onyx. It also configures `/root/.my.cnf` with the Plesk admin credentials to ensure standard CentOS logrotate works properly. This has the added benefit of ensuring you can easily run mysqladmin without entering admin DB credentials.

It is integrated with Plesk tools to provide back up, upgrade DBs, and notify Plesk of version changes.

# Usage
`./mariadb-10.2-upgrade.sh`


# Changelog ##
 2019-02-20
 - Initial version

 2019-02-21
 - Removed whitespace from Repo file (errors)
 - Removed line break between MYSQL_PWD and mysql_upgrade commands (did not function separately)
 - Added "stop" before upgrading MariaDB-Server as per MariaDB Recommendation
 - Only rpm -e --nodeps on MariaDB-server (other elements update successfully prior)
 - Repaired syntax for major version IF comparison (req'd spaces within square brackets).
 - Added MariaDB/MySQL version checks. Switch case to allow for different options.
 - Added ability to upgrade from MariaDB 5.5 w/warning and user prompt.
 - Offers to make backup of DBs (and actually does if you tell it to)
 
 2019-02-22
 - Add detection of MariaDB.repo file and rename to lowercase prior to remaining steps
 
## Current Status:
Tested and working OK except as (if) noted.

## Complete test cases:
- Default CentOS7 5.5 -> 10.2
- MariaDB CentOS7 Repo 10.0 -> 10.2
- MariaDB CentOS7 Repo 10.1 -> 10.2
