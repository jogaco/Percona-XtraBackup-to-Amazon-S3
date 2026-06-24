#!/bin/bash

# Based on https://github.com/woxxy/MySQL-backup-to-Amazon-S3
# Full backups every start of month and week. Differential backups the rest of days.
# Param: auto | month | week | day
# By default: auto
#
# Source the variables script (DRY)
DIR="${BASH_SOURCE%/*}"
if [[ ! -d "$DIR" ]]; then DIR="$PWD"; fi
. "$DIR/variables.sh"

#Week num, from 01 to 53 starting Monday
week_curr=$(date +"%V")
#Week num, from 01 to 53 starting Monday
week_minus2=$(date --date="2 weeks ago" +"%V")
#Week num, from 01 to 53 starting Monday
month_curr=$(date +"%m")
# Month minus 2 (1..12)
month_minus2=$(date --date="2 months ago" +"%m")

DATESTAMP=$(date +"_%Y%m%d_%H%M%S")
# Day: 01-31
DAY=$(date +"%d")
# Day of week: Monday-Sunday
DAYOFWEEK=$(date +"%u")

PERIOD=${1-auto}

if [ ${PERIOD} = "auto" ]; then
	if [ ${DAY} = "01" ]; then
		PERIOD=month
	elif [ ${DAYOFWEEK} = "1" ]; then
		PERIOD=week
	else
		PERIOD=day
	fi	
fi

if [ ${PERIOD} = "month" ]; then
	CURRENT_MINUS2="month_${month_minus2}"
	CURRENT="month_${month_curr}"
elif [ ${PERIOD} = "week" ]; then
	CURRENT_MINUS2="week_${week_minus2}"
	CURRENT="week_${week_curr}"
else
	CURRENT="day_$(date +"%u")"
fi

echo "*************** Selected period: $PERIOD. Current: $CURRENT *************"

echo "*************** Starting backing up the database to a file... ***********"

if [ ${PERIOD} = "week" ] || [ ${PERIOD} = "month" ] ; then
	# Remove previous full-backup from local filesystem
	BACKUP_DIRNAME=${BACKUP_DIRNAME}_full
	rm -rf ${BACKUP_PATH}${BACKUP_DIRNAME}
	# perform backup
	${PERCONA_BACKUP_COMMAND} --user=${MYSQLROOT} --password=${MYSQLPASS} --no-timestamp ${BACKUP_PATH}${BACKUP_DIRNAME} --parallel=4 --use-memory=640M
	# apply logs
	${PERCONA_BACKUP_COMMAND} --user=${MYSQLROOT} --password=${MYSQLPASS} --no-timestamp ${BACKUP_PATH}${BACKUP_DIRNAME} --parallel=4 --use-memory=640M --apply-log
else
	# Remove previous differential-backup
	echo "*************** Removing previous differential backup dir ***************"
	rm -rf ${BACKUP_PATH}${BACKUP_DIRNAME}
	# perform backup
	${PERCONA_BACKUP_COMMAND} --user=${MYSQLROOT} --password=${MYSQLPASS} --no-timestamp --incremental ${BACKUP_PATH}${BACKUP_DIRNAME} --incremental-basedir=${BACKUP_PATH}${BACKUP_DIRNAME}_full --parallel=4 --use-memory=640M
	# apply logs
	${PERCONA_BACKUP_COMMAND} --user=${MYSQLROOT} --password=${MYSQLPASS} --no-timestamp --incremental ${BACKUP_PATH}${BACKUP_DIRNAME} --incremental-basedir=${BACKUP_PATH}${BACKUP_DIRNAME}_full --parallel=4 --use-memory=640M --apply-log
fi

echo "*************** Done backing up the database to a file. *****************"
echo "*************** Starting compression... *********************************"

echo "tar czf ${BACKUP_PATH}${BACKUP_DIRNAME}${DATESTAMP}.tar.gz -C ${BACKUP_PATH} ${BACKUP_DIRNAME}" 

tar czf ${BACKUP_PATH}${BACKUP_DIRNAME}${DATESTAMP}.tar.gz -C ${BACKUP_PATH} ${BACKUP_DIRNAME}

echo "*************** Done compressing the backup file. ***********************"

# upload all databases
echo "*************** Uploading the new backup... *****************************"
s3cmd put --acl-private -f ${BACKUP_PATH}${BACKUP_DIRNAME}${DATESTAMP}.tar.gz s3://${S3BUCKET}/${S3PATH}${CURRENT}/
echo "*************** New backup uploaded. ************************************"

# Remove old backups from 2 periods ago, if period is month or week, plus daily differential backups
if [ ${PERIOD} = "week" ] || [ ${PERIOD} = "month" ] ; then
	echo "Removing old backup (2 ${PERIOD}s ago)..."
	s3cmd del --recursive s3://${S3BUCKET}/${S3PATH}${CURRENT_MINUS2}/
	echo "Old backup removed."
	echo "Removing daily differential backups..."
	week_days=(day_1 day_2 day_3 day_4 day_5 day_6 day_7)
	for i in "${week_days[@]}"
	do
		echo "Removing $i"
		s3cmd del --recursive s3://${S3BUCKET}/${S3PATH}${i}/
	done
fi

echo "*************** Removing the cache files... *****************************"
# remove compressed databases dump
rm ${BACKUP_PATH}${BACKUP_DIRNAME}${DATESTAMP}.tar.gz
echo "*************** Cache files removed. ************************************"
echo "All done."

