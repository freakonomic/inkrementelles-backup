#!/bin/bash

#------------------------------------------------------------------------------#
#                                                                              #
# Name: backup_daily.sh                                                        #
#                                                                              #
# Version: 1.0                                                               #
# Autor: freakonomic <info@freakonomic.de>                                     #
#                                                                              #
# Zweck: Legt ein inkrementelles Backup auf einem Remote-Host an.              #
#                                                                              #
#------------------------------------------------------------------------------#


#### Variablen -------------------------------------------------------------####
HOSTNAME=`hostname -s`
HOSTNAME_FULL=`hostname -f`
LOGFILE="/var/log/backup_daily.log"
ERRORLOG="/var/log/backup_daily.err"
ERROR_MAIL="/tmp/error_mail.txt"
MAIL_SENDER="mail@example.com"
MAIL_RECIPIENT="mail@example.com"
BACKUP_SENDER="example.com:/"
BACKUP_MOUNT="/mnt/daily"
BACKUP_OPTIONS="-o password_stdin"
ROTATE_SENDER="example.com:/"
ROTATE_MOUNT="/mnt/rotate"
ROTATE_OPTIONS="-o nonempty"
SOURCE_DIR="/boot /etc /home /var/log"
BACKUP_DIR="/mnt/daily/$HOSTNAME"
ROTATE_DIR="/mnt/rotate/$HOSTNAME"
DATE="$(date +%d-%m-%Y)"
TIME="$(date +%H-%M)"
EXCLUDE="--exclude=$LOGFILE --exclude=$ERRORLOG"

## Erweiterung für MySQL-Datenbanken ------------------------------------------#
TARGET="/var/backups/mysql"
IGNORE="phpmyadmin|mysql|information_schema|performance_schema|test"
CONF=/etc/mysql/debian.cnf
DBS="$(/usr/bin/mysql --defaults-extra-file=$CONF -Bse 'show databases' | /bin/grep -Ev $IGNORE)"


#### Funktionen ------------------------------------------------------------####
UMOUNT1_OK() {
    while true; do
        if [ $? = 0 ]; then
            echo "OK"
            break;
        else
            sleep 1 && umount --force $ROTATE_MOUNT
            (($UMOUNT_COUNT++))
            if [ $UMOUNT_COUNT = 20 ]; then
                echo "ERROR 03-1"
                echo -e "\nUnmount von Rotate-Verzeichnis funktioniert nicht!\n" >> $LOGFILE
                echo -e "\nBackup um `date +%T` Uhr mit Fehlern abgebrochen!\n" >> $LOGFILE
                cat $LOGFILE > $ERROR_MAIL
                cat $ERRORLOG >> $ERROR_MAIL
                mail -s "Taegliches Backup auf $HOSTNAME_FULL mit Fehlern abgebrochen!" -r $MAIL_SENDER $MAIL_RECIPIENT < $ERROR_MAIL
                exit 1
            fi
        fi
    done
}

UMOUNT2_OK() {
    while true; do
        if [ $? = 0 ]; then
            echo "OK"
            break;
        else
            sleep 1 && fusermount -u $BACKUP_MOUNT
            (($UMOUNT_COUNT++))
            if [ $UMOUNT_COUNT = 20 ]; then
                echo "ERROR 03-2"
                echo -e "\nUnmount von Backup-Verzeichnis funktioniert nicht!\n" >> $LOGFILE
                echo -e "\nBackup um `date +%T` Uhr mit Fehlern abgebrochen!\n" >> $LOGFILE
                cat $LOGFILE > $ERROR_MAIL
                cat $ERRORLOG >> $ERROR_MAIL
                mail -s "Taegliches Backup auf $HOSTNAME_FULL mit Fehlern abgebrochen!" -r $MAIL_SENDER $MAIL_RECIPIENT < $ERROR_MAIL
                exit 1
            fi
        fi
    done
}

EXEC_OK() {
    if [ $? = 0 ]; then
        echo "OK"
    else
        umount --force $ROTATE_MOUNT
        UMOUNT1_OK
        fusermount -u $BACKUP_MOUNT
        UMOUNT2_OK
        echo "FAIL"
        echo -e "\nBackup um `date +%T` Uhr mit Fehlern abgebrochen!\n" >> $LOGFILE
        cat $LOGFILE > $ERROR_MAIL
        cat $ERRORLOG >> $ERROR_MAIL
        mail -s "Taegliches Backup auf $HOSTNAME_FULL mit Fehlern abgebrochen!" -r $MAIL_SENDER $MAIL_RECIPIENT < $ERROR_MAIL
        exit 1
    fi
}


#### Das eigentliche Script ------------------------------------------------####
## Lege Logfiles an ----------------------------------------------------------##
echo -e "Taegliches Backup am $DATE um `date +%T` Uhr gestartet\n" > $LOGFILE
echo -e "Error Log - $DATE `date +%T`\n" > $ERRORLOG

## Umleitung der Fehler-/Meldungen ins entsprechende Logfile -----------------##
exec 1>> $LOGFILE 2>> $ERRORLOG

## Mounte Backup Server ------------------------------------------------------##
echo -en "Mounte Backup Server\t\t\t\t"
sshfs $BACKUP_SENDER $BACKUP_MOUNT $BACKUP_OPTIONS < ~/rotate_key
if [ $? = 0 ]; then
    echo "OK"
else
    if [ -n 'cat $ERRORLOG | grep "fuse: mountpoint is not empty"' ]; then
        echo "ERROR 01-1"
        break;
    else
        umount --force $ROTATE_MOUNT
        UMOUNT1_OK
        fusermount -u $BACKUP_MOUNT
        UMOUNT2_OK
        echo "FAIL"
        echo -e "\nBackup um `date +%T` Uhr mit Fehlern abgebrochen!\n" >> $LOGFILE
        cat $LOGFILE > $ERROR_MAIL
        cat $ERRORLOG >> $ERROR_MAIL
        mail -s "Taegliches Backup auf $HOSTNAME_FULL mit Fehlern abgebrochen!" -r $MAIL_SENDER $MAIL_RECIPIENT < $ERROR_MAIL
        exit 1
    fi
fi

## Pruefe die Anzahl der Backups und loescht ggf. ----------------------------##
if [ `find $BACKUP_DIR/ -type f | wc -l` -eq 15 ]; then # Pruefe die Anzahl
    echo -en "Mounte Rotate Server\t\t\t\t"
    mount.nfs $ROTATE_SENDER $ROTATE_MOUNT -vs -o $ROTATE_OPTIONS > /dev/null 2> $ERRORLOG
    EXEC_OK
    echo -en "Rotiere alte Backups\t\t\t\t"
    rm $ROTATE_DIR/* # Loesche alte Backups
    mv $BACKUP_DIR/* $ROTATE_DIR/
    EXEC_OK
    echo -en "Unmounte Rotate Server\t\t\t"
    umount $ROTATE_MOUNT
    UMOUNT1_OK
fi

## Erstelle Backup der MySQL-Datenbanken -------------------------------------##
echo -en "Erstelle Backup der MySQL-Datenbanken\t"
for DB in $DBS; do
    /usr/bin/mysqldump --defaults-extra-file=$CONF --skip-extended-insert --skip-comments $DB > $TARGET/$DB.sql
done
EXEC_OK

## Erstelle Backup -----------------------------------------------------------##
while true; do
    echo -en "Erstelle Backup\t\t\t\t\t"
    tar -cpzf $BACKUP_DIR/${DATE}_${TIME}.tgz -g $BACKUP_DIR/timestamp.dat $SOURCE_DIR $EXCLUDE
    if [ $? = 0 ]; then
        echo "OK"
        break;
    else
        if [ -n 'cat $ERRORLOG | grep "nfs - gefolgt von ungültigem Byte"' ] || [ -n 'cat $ERRORLOG | grep "nfs : Das Argument ist ungültig"' ]; then
            rm $BACKUP_DIR/${DATE}_${TIME}.tgz && rm $BACKUP_DIR/timestamp.dat
            echo "ERROR 02"
        else
            umount --force $ROTATE_MOUNT
            UMOUNT1_OK
            fusermount -u $BACKUP_MOUNT
            UMOUNT2_OK
            echo "FAIL"
            echo -e "\nBackup um `date +%T` Uhr mit Fehlern abgebrochen!\n" >> $LOGFILE
            cat $LOGFILE > $ERROR_MAIL
            cat $ERRORLOG >> $ERROR_MAIL
            mail -s "Taegliches Backup auf $HOSTNAME_FULL mit Fehlern abgebrochen!" -r $MAIL_SENDER $MAIL_RECIPIENT < $ERROR_MAIL
            exit 1
        fi
    fi
done

## Unmounte Backup Server ----------------------------------------------------##
echo -en "Unmounte Backup Server\t\t\t"
fusermount -u $BACKUP_MOUNT
EXEC_OK

## Abschluss-Meldungen -------------------------------------------------------##
echo -e "\nBackup um `date +%T` Uhr erfolgreich abgeschlossen\n" >> $LOGFILE
mail -s "Taegliches Backup auf $HOSTNAME_FULL erfolgreich abgeschlossen" -r $MAIL_SENDER $MAIL_RECIPIENT < $LOGFILE
exit 0