# Description
A script to upgrade MariaDB from 5.5 to 10.2
Integrated with Plesk tools to back up, upgrade DBs, and notify Plesk of version changes.

# Usage
`./mariadb-10.2-upgrade.sh`


# Changelog ##
 2019-02-20
 - Initial version

 2019-02-21
 - Removed whitespace from Repo file (errors)
 - Removed linebreak between MYSQL_PWD and mysql_upgrade commands (did not function separately)
 - Added "stop" before upgrading MariaDB-Server as per MariaDB Recommendation
 - Only rpm -e --nodeps on MariaDB-server (other elements update successfully prior)
 - Repaired syntax for major version IF comparison (req'd spaces within square brackets).
 - Added MariaDB/MySQL version checks. Switch case to allow for different options.
 - Added ability to upgrade from MariaDB 5.5 w/warning and user prompt.
 - Offers to make backup of DBs (and actually does if you tell it to)
