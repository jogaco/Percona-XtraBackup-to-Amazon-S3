#!/bin/bash

# Source the variables script (DRY)
DIR="${BASH_SOURCE%/*}"
if [[ ! -d "$DIR" ]]; then DIR="$PWD"; fi
. "$DIR/variables.sh"

# Colored shell output
red_color=`tput setaf 1`
green_color=`tput setaf 2`
reset_color=`tput sgr0`

# Create directory to restore files in
RESTORED_DIR=${BACKUP_PATH}${BACKUP_DIRNAME}_restored
if [ ! -d "$RESTORED_DIR" ]; then
  mkdir -p $RESTORED_DIR
  mkdir -p ${RESTORED_DIR}_full
fi

first_week_from_month=$(date -d "$(date +"%Y%m01")" +"%W")
week_curr=$(date +"%V")
month_curr=$(date +"%m")
day_of_the_week=$(date +"%u")

# Choose between using the latest weekly or monthly backup
if [ $week_curr -gt $first_week_from_month ]
then
  PERIOD=week
  CURRENT=$week_curr
else
  PERIOD=month
  CURRENT=$month_curr
fi

echo "*************** Selected period: $PERIOD. Current: $CURRENT *************\n"

echo "*************** Downloading full backup for ${PERIOD}_${CURRENT} *********************"
s3cmd get --force s3://${S3BUCKET}/${S3PATH}${PERIOD}_${CURRENT}/*.tar.gz ${RESTORED_DIR}/

echo "*************** Downloading last differential backup for day_${day_of_the_week}"
s3cmd get --force s3://${S3BUCKET}/${S3PATH}day_${day_of_the_week}/*.tar.gz ${RESTORED_DIR}/


echo "*************** Uncompressing backups ***********************************\n"
for file in `ls ${RESTORED_DIR}/*.tar.gz`;
do
  echo "*************** Uncompressing $file to $RESTORED_DIR *********************n"
  tar -xvzf $file --directory ${RESTORED_DIR}
done

# Differential backups will be placed in $RESTORED_DIR/$BACKUP_DIRNAME
# Full backups will be placed in ${RESTORED_DIR}/${BACKUP_DIRNAME}_full
RESTORED_DIFF_DIR=$RESTORED_DIR/$BACKUP_DIRNAME/
RESTORED_FULL_DIR=${RESTORED_DIR}/${BACKUP_DIRNAME}_full/

if [ -d "${RESTORED_DIFF_DIR} && -d "${RESTORED_FULL_DIR} ]
then
  echo "*************** Mergin differential and full backups ********************\n"
  $PERCONA_BACKUP_COMMAND --user=$MYSQLROOT --password=$MYSQLPASS --apply-log $RESTORED_FULL_DIR --incremental-dir=$RESTORED_DIFF_DIR
  echo "${green_color}[NOTICE] Merged backups available in: ${RESTORED_FULL_DIR} ${reset_color}"
else
  echo "${red_color}[ERROR] Something got bR0ken, please check output as recovered dirs are not present${reset_color}"
  echo "Please check directory: '${RESTORED_DIR}"
  exit 1
fi
