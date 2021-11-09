#!/bin/bash

#######################################
# Bash script to install an LAMP stack in ubuntu
# Author: Josh Cairns

# Check if user is running script as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Ask value for phpmyadmin admin username
# read -p 'Choose phpmyadmin admin username: ' phpmyadmin_admin_username
# echo

# Ask for email that login credentials are to be sent to
email_match=0
while [ $email_match = 0 ]
do
   echo
   read -p 'Email for credentials to be sent to: ' creds_email
   read -p 'Confirm email: ' creds_check
   if [ "$creds_email" != "$creds_check" ];
   then
      echo 'Entered emails do not match. Please try again.'
   else email_match=1
   fi  
done

host_name=$(hostname)

# Randomly generate a sql root password
db_root_password=$(openssl rand -base64 14)
phpmyadmin_admin_password=$(openssl rand -base64 14)
mySQL_application_password_phpmyadmin=$(openssl rand -base64 14)

# Update system
sudo apt-get update -y

# Install apache2
sudo apt install apache2 -y

# Install MySQL database server and use previously generated root password
export DEBIAN_FRONTEND="noninteractive"
debconf-set-selections <<< "mysql-server mysql-server/root_password password $db_root_password"
debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $db_root_password"
apt-get install mysql-server -y


# Install Expect for "mysql_secure_installation" script
sudo apt-get -qq install expect > /dev/null

# Build Expect script
tee ~/secure_our_mysql.sh > /dev/null << EOF
spawn $(which mysql_secure_installation)

expect "Enter password for user root:"
send "$db_root_password\r"

expect "Press y|Y for Yes, any other key for No:"
send "y\r"

expect "Please enter 0 = LOW, 1 = MEDIUM and 2 = STRONG:"
send "2\r"

expect "Change the password for root ? ((Press y|Y for Yes, any other key for No) :"
send "n\r"

expect "Remove anonymous users? (Press y|Y for Yes, any other key for No) :"
send "y\r"

expect "Disallow root login remotely? (Press y|Y for Yes, any other key for No) :"
send "y\r"

expect "Remove test database and access to it? (Press y|Y for Yes, any other key for No) :"
send "y\r"

expect "Reload privilege tables now? (Press y|Y for Yes, any other key for No) :"
send "y\r"

EOF

# This runs the "mysql_secure_installation" script which removes insecure defaults.
sudo expect ~/secure_our_mysql.sh

# Cleanup
rm -v ~/secure_our_mysql.sh # Remove the generated Expect script
#############

# Install PHP
sudo apt install php libapache2-mod-php php-mysql -y

mysql -u root -p$db_root_password <<EOF
UNINSTALL COMPONENT "file://component_validate_password";
exit
EOF

export DEBIAN_FRONTEND="noninteractive"
debconf-set-selections <<< "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2"  
debconf-set-selections <<< "phpmyadmin phpmyadmin/dbconfig-install boolean true"  
# debconf-set-selections <<< "phpmyadmin phpmyadmin/mysql/admin-user string $phpmyadmin_admin_username"  
# debconf-set-selections <<< "phpmyadmin phpmyadmin/mysql/admin-pass password $phpmyadmin_admin_password"  
debconf-set-selections <<< "phpmyadmin phpmyadmin/mysql/app-pass password $mySQL_application_password_phpmyadmin"  
debconf-set-selections <<< "phpmyadmin phpmyadmin/app-password-confirm password $mySQL_application_password_phpmyadmin"

# Install phpmyadmin
sudo apt install phpmyadmin php-mbstring php-zip php-gd php-json php-curl -y

mysql -u root -p$db_root_password <<EOF
INSTALL COMPONENT "file://component_validate_password";
exit
EOF

sudo phpenmod mbstring
# sudo systemctl restart apache2

mysql -u root -p$db_root_password <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '$phpmyadmin_admin_password';
exit
EOF

# Install Cockpit
sudo apt install cockpit -y

# Install sendmail to allow credentials to be sent to user
sudo apt-get install sendmail -y

# Configure /etc/hosts file
sudo sed -i "1 s|$| $host_name|" /etc/hosts

# Run sendmailconfig and select 'y' for every prompt
yes | sudo sendmailconfig

# Restart apache2 so all changes take effect
sudo systemctl restart apache2

# Send the email with the credentials
sendmail -v "$creds_email" <<EOF
Subject: Webserver credentials
From: yourwebserver
phpmyadmin admin username: root
phpmyadmin admin password: $phpmyadmin_admin_password
mySQL root password: $db_root_password
mySQL application password for phpmyadmin: $mySQL_application_password_phpmyadmin
.
EOF

# Uninstall dos2unix
sudo apt-get purge dos2unix -y

# Uninstall Expect
sudo apt-get -qq purge expect > /dev/null

# Uninstall sendmail
apt-get purge sendmail* -y

echo
echo "############################################################################################"
echo "Lamp installation complete! Find login credentials in your email: $creds_email"
echo "############################################################################################"
echo

rm install_lamp.sh