#!/bin/bash
# User data from the CloudFormation (CorpWeb) assignment, unchanged.
dnf update -y
dnf install -y git httpd php
service httpd start
chkconfig httpd on
aws s3 cp s3://seis665-public/index.php /var/www/html/
