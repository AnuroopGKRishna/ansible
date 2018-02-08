#!/bin/bash
rm /var/www/html/ping.html
echo $PATH > /home/ubuntu/initialPath
export PATH=$PATH:/usr/local/bin
echo $PATH > /home/ubuntu/finalPath
date > /home/ubuntu/startTime
#aws s3 sync --exclude ".svn/*"  --delete s3://aws.game_s3_folder /var/www/html/game_name  > /home/ubuntu/syncLog 2>&1;
echo "OK" > /var/www/html/ping.html
date > /home/ubuntu/endTime
chown ubuntu:www-data /var/www/html/ping.html
#chown -R ubuntu:www-data /var/www/html/game_name
service ntp stop
ntpd -gq
service ntp start
