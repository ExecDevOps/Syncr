# Syncr
Syncs files between two servers in a 2-node cluster automagically without having to rely on cron job or other time based mechanism. Syncr is triggered by incron which relies on the filesystem's inotify mechanism, inotify fires events whenever a monitoried file or directory changes.

Besides synchronization of files Syncr also has a basic but very powerful mechanism for executing post-sync tasks. A list of commands can be provided for each monitored file, these will be executed in sequence as soon as the server(s) get a notification of a filechange. This is very handy for i.e. services that needs to be restarted whenever their configuration file changes.

Syncr does not dictate which server should be the source and which should be the target, any server can have a monitored file altered and Syncr happily replicates the file and executes commands that belong to the file, if there are any.

Since Syncr is very simple it does not do any sanity-checks besides what is necessary for it's own functionality. There are probably thousands of ways to break Syncr, it has however worked well for me the way it is described and published here. Have fun but remember: YMMV.
# What Syncr does
Properly setup the following sequence of events will occur whenever a monitored file changes:
1. The file system on the source server notifies incrond that a monitored file has changed
2. Incrond executes `/opt/syncr.sh` with the full pathname of the file and the name of the triggered event
3. Syncr checks whether the notified file has actually changed or not:
   - incron gets a nudge to avoid occasional stop of service
   - it creates a backup of the file with a numbered extension added, i.e. .1, .2, .3, etc. up to 6 copies are kept
   - copies the file to the other server via `rsync`
4. Syncr then processes `/opt/syncr.ini` for any occurrence of the full filename in brackets:
   - each line after the filename in brackets gets executed one after the other via `eval`

Syncr properly handles transfer of the file from one server to the other without creating a loop. This means that the same file can be monitored on each server regardless of which server the file changes on.
# Tested environment
This setup was developed and tested on two servers running Xenserver 7.6 with a direct attached cable between the servers. This link was configured with an IP address of `10.10.10.1/24` on server `xcp-1` and `10.10.10.2/24` on server `xcp-2`. 

Since Xenserver 7.6 is built on CentOS 7 I presume that this setup should work without problem on CentOS 7 as well. And I don't see why it should not work on Ubuntu, etc. with some adjustments for resp. distro.
# Setup
### hosts file on both servers
Add the hostname and the IP addresses of the direct link between the servers to the  `/etc/hosts`:
```
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
10.10.10.1  xcp-1
10.10.10.2  xcp-2
```
### iptables on both servers
Allow any traffic on the direct link between the servers:
```bash
I_ROW=$(iptables --list RH-Firewall-1-INPUT --numeric --line-numbers | tail -n 1 | awk '{print $1}')
iptables -I RH-Firewall-1-INPUT $I_ROW -s 10.10.10.0/24 -j ACCEPT
```
### Passwordless SSH
On `xcp-1` create key with specified keytype and copy to `xcp-2`:
```bash
ssh-keygen -o -a 100 -t ed25519 -f ~/.ssh/id_ed25519 -C "root@xcp-1"
ssh-copy-id xcp-2
```
Do the same on `xcp-2` and copy to `xcp-1`:
```bash
ssh-keygen -o -a 100 -t ed25519 -f ~/.ssh/id_ed25519 -C "root@xcp-2"
ssh-copy-id xcp-1
```
Now passwordless SSH should work on both servers, test SSH on `xcp-1` to `xcp-2`:
```bash
ssh xcp-2
ssh 10.10.10.2
```
Test from `xcp-2` to `xcp-1`:
```bash
ssh xcp-1
ssh 10.10.10.1
```
### Install and configure incron on both servers
Install EPEL repository:
```bash
yum install epel-release --enablerepo=extras
yum install incron
```
Set nano to be default editor instead of vi:
```bash
sed -i -e "s/# editor =/editor = /" /etc/incron.conf
```
Lock down incron to allow only root:
```bash
echo "root" >> /etc/incron.allow
```
Extend inotify if many files are to be monitored (default is 8192):
```bash
echo "fs.inotify.max_user_watches = 1048576" >> /etc/sysctl.conf
sysctl -p
```
### Copy and adjust Syncr files on both servers
Copy `syncr.sh` and `syncr.ini` to `/opt/syncr.sh` resp. `/opt/syncr.ini` on both servers. Set `syncr.sh` to be executable:
```bash
chmod +x /opt/syncr.sh
```
**Note!** `/opt/syncr.sh` has to be modified on each server, replace the `rsync` command target with the other server's name, i.e. on `xcp-1` the rsync target has to be `xcp-2` and vice versa. 
```bash
nano /opt/syncr.sh
```
```
[...]
rsync -azh $S_FILE root@xcp-2:/$S_FILE
[...]
```
### Populate incron on both servers
Add files to be monitored to incrond's list of things to monitor. The event that seems to work best to monitor is `IN_CLOSE_WRITE` that gets triggered every time a file is closed after alteration. And also when a file is opened, at least when nano is used. Syncr takes this into account when processing triggers:
```bash
incrontab -e
```
```
/etc/aliases IN_CLOSE_WRITE /opt/syncr.sh $@ $%
/etc/hosts IN_CLOSE_WRITE /opt/syncr.sh $@ $%
/etc/rsyslog.d/xenserver.conf IN_CLOSE_WRITE /opt/syncr.sh $@ $%
/etc/ssmtp/ssmtp.conf IN_CLOSE_WRITE /opt/syncr.sh $@ $%
/etc/sysconfig/iptables IN_CLOSE_WRITE /opt/syncr.sh $@ $%
```
Create file with tasks to execute after synchronzation. If this file does not exist then no post-sync tasks will be executed, Syncr will only transfer the file to the other server (and create backup of the file). To add post-sync tasks to a file, list the full filename in brackets with the tasks on the following lines, just like a Windows .INI file:
```bash
nano /opt/syncr.ini
```
```
[/etc/rsyslog.d/xenserver.conf]
systemctl stop rsyslog
sleep 5s
systemctl start rsyslog

[/etc/sysconfig/iptables]
systemctl restart iptables.service
```
This setup example will only execute tasks for the two files listed, other monitored files will only be copied.
### Start incrond on both servers
```bash
systemctl start incrond
systemctl enable incrond
```
### Monitor incrond and Syncr
In a separate shell, start a filtered monitoring of events in the syslog:
```bash
tail -f /var/log/messages | egrep 'logger:|incrond'
```
# Syncr FTW!
