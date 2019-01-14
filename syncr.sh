#!/bin/sh

S_FILE=$1
S_ACTION=$2


if [ -z $S_FILE ] || [ -z $S_ACTION ]
then
  logger "${0} Empty file ($S_FILE) or action ($S_ACTION) argument, exiting"
  exit 1
fi


incrontab -d


if [ ! -e $S_FILE.1 ]
then
  cp -f  $S_FILE $S_FILE.1
fi

diff -q  $S_FILE $S_FILE.1 > /dev/null
if [ $? -eq 0 ]  &&  [ $S_ACTION != "IN_IGNORED" ]
then
  logger "${0} $S_ACTION no change in $S_FILE, exiting"
  exit 1
fi


logger "${0} Process $S_ACTION for $S_FILE"

rm -rf $S_FILE.6
mv     $S_FILE.5 $S_FILE.6
mv     $S_FILE.4 $S_FILE.5
mv     $S_FILE.3 $S_FILE.4
mv     $S_FILE.2 $S_FILE.3
mv     $S_FILE.1 $S_FILE.2
cp -f  $S_FILE   $S_FILE.1

rsync -azh $S_FILE root@xcp-2:/$S_FILE


S_INIFILE="/opt/syncr.ini"
S_IFS_TEMP=$IFS


if [ ! -e $S_INIFILE  ]
then
  exit 0
fi


I_START=$(cat -n $S_INIFILE | grep "\[$S_FILE\]" | awk {'print $1'})
if [ -z $I_START ]
then
  logger "${0} No tasks for $S_FILE, exiting"
  exit 0
fi

I_END=$(cat -n $S_INIFILE | tail -n +$((I_START+1)) | grep "\[" | awk {'print $1'} | head -n 1)


IFS=$'\n'

S_TASKS=$(awk 'NR=='$((I_START+1))', NR=='$((I_END-1))'' $S_INIFILE)
for S_TASK in $S_TASKS
do
  logger "${0} Exec task ($S_TASK) for $S_FILE"
  eval "$S_TASK"
done

IFS=$IFS_TEMP
