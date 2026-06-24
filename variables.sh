#!/bin/bash

# change these variables to what you need
MYSQLROOT=root
MYSQLPASS=
S3BUCKET=my_bucket
#Path for full backup and differential backup. Must end with /
BACKUP_PATH=/backups/
# Name of backup dir, within BACKUP_PATH 
BACKUP_DIRNAME=music_collect
# the following line prefixes the backups with the defined directory. it must be blank or end with a /
S3PATH=
# when running via cron, the PATHs MIGHT be different
PERCONA_BACKUP_COMMAND=/usr/bin/innobackupex
