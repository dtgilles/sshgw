#!/bin/bash
[ "$1" = -x ] && shift && set -x
##### global variables
##### UserDir  (default is /etc/user)
##### HomeBase (default is /home)
##### HostKeys (default is /etc/ssh, -- if there are no keys, they will be generated)
##### LoginSleep        time to sleep, executing login shell "LoginSleep"
#####                   default=3600
##### SSHD_OPTS         here you can define additional options for ssh daemon
##### RootKey           here you can define one initial root key
##### LOGFILE           defines absolute path of logfile (realized by sshd option -E)
#####                   if not set (default) regarding sshd option is "-e"
##### IpTables          apply user based iptables
#####                   - docker container must be started with
#####                     --cap-add=NET_ADMIN --cap-add=NET_RAW
#####                   - if $IpTables is
#####                     yes          /etc/rose/bin/iptables.rose is used
#####                     <script>     <script> is used
#####                     ""|no        feature is disabled
#
#  $UserDir could be external mounted directory
#  using this dir you can simply define the users
#  that have to be accessible via ssh and
#  you may define some of their parameters
#  like uid and so on....:
#
#  "$UserDir/<user>/key"	key file (in openssh format)
#  "$UserDir/<user>/uid"	uid of the user (only a number)
#  "$UserDir/<user>/shell"	name of the login shell (has to exist)
#  "$UserDir/<user>/iptables"	iptables rules (for definition see your iptables script)
#
#  The files uid and shell are optional and key file could be substituted by a directory
#  "key_build" with possibly more than one key inside an a prefix definition for each key:
#
#      "$UserDir/<user>/key_build/"
#      "$UserDir/<user>/key_build/subuser1.pub"    # key file (in openssh format)
#      "$UserDir/<user>/key_build/subuser2.pub"    # key file (in openssh format)
#      "$UserDir/<user>/key_build/_keyprefix"      # prefix for each key (see below)
#      "$UserDir/<user>/key_build/"        # key file (in openssh format)
#      "$UserDir/<user>/uid"               # uid of the user (only a number)
#      "$UserDir/<user>/shell"             # name of the login shell (has to exist)
#
#  If "_keyprefix" has a %u inside it will be substituted by name of the subuser, e.g.
#  "_keyprefix" could look like 'nopty,command="/usr/local/bin/show_app_permissions %u"'.
#  So if if either "subuser1" or "subuser2" login via ssh they will see their own
#  permissions, because of the personalized forced command.
#
UserDir="${UserDir:-/etc/user}"
HomeBase="${HomeBase:-/home}"
HostKeys="${HostKeys:-/etc/ssh}"
LoginSleep="${LoginSleep:-3600}"

echo "LoginSleep=$LoginSleep" >/etc/default/LoginSleep
if [ "$RootKey" != "" ]
   then
      usermod -aG ssh root
      sed -ie 's/^PermitRootLogin.*/PermitRootLogin without-password/' /etc/ssh/sshd_config
      mkdir -p              /root/.ssh
      (echo "$RootKey"; cat /root/.ssh/authorized_keys 2>/dev/null) | sort -u > /tmp/root.key || exit 2
      cat /tmp/root.key   > /root/.ssh/authorized_keys             && rm   -f   /tmp/root.key
   fi
if [ -z "$LOGFILE" ]				##### if variable is not set
   then
      SSHD_OPTS="-e ${SSHD_OPTS}"		##### then log to `docker logs`
   else
      SSHD_OPTS="-E ${LOGFILE} ${SSHD_OPTS}"	##### else use the given Logfile
      mkdir -p "${LOGFILE%/*}"			##### and create needed log directory
   fi
if [ "${SleepyTask}" != "" ]
   then
      (
         read sec task <<< "$SleepyTask"
         [ "${sec#*[^0-9]}" = "$sec" ] || exit 4 ##### sec must be the time to sleep (in seconds)
         while sleep "$sec"                      ##### this is an endless loop:
             do                                  #####  - sleep a while...
                eval "$task"                     #####  - ...and execute a single task
             done
      ) &
   fi

case "$1"
   in
      ""|sshd)  : ;;
      *)        exec $*;;
   esac

# check for keyfiles // copy or generate them
# append the list of keys to sshd_config
hostkeys=`ls "${HostKeys}"/*_key 2>/dev/null`
if [ "${#hostkeys}" = 0 ]
   then
      dpkg-reconfigure -f noninteractive openssh-server   ##### create host keys if they do not exist
      service openssh stop                                ##### but do not start ssh -- it could collide with later start command
      mkdir -p "${HostKeys}"                              ##### create host key dir if it doesn't exist
      if [ "${HostKeys}" != /etc/ssh ]
         then
            cp -p /etc/ssh/*_key     "${HostKeys}/."
            cp -p /etc/ssh/*_key.pub "${HostKeys}/."
         fi
      hostkeys=`ls "${HostKeys}"/*_key`
   fi
sed -i /^HostKey/d  /etc/ssh/sshd_config
for f in ${hostkeys}
   do
      echo "HostKey $f"
   done \
>> /etc/ssh/sshd_config

##### if there are some users defined in $UserDir
##### then create them and distribute keys:
/usr/local/bin/add_user_keys.sh

##### if there is an iptables script definned, then call it and send it to background
[ "$IpTables" = "yes" ] && export IpTables=/etc/rose/bin/iptables.rose
if [ -f "$IpTables"   ] && [ -x "$IpTables" ]
   then
      [ -f /etc/rose/ipout/.global ] || /usr/local/bin/init_ipout global
      [ -f /etc/rose/ipout/_apt    ] || /usr/local/bin/init_ipout apt
      "$IpTables" start &
   fi

for file in /entry.add.*                       ##### perhaps it could make sence to source
   do                                          ##### *.sh or simply execute all other files
      [ -f "$file" ] && source "$file"         ##### -- later perhaps
   done                                        ##### let me know, write me a ticket!
##### final destination
exec /usr/sbin/sshd -D ${SSHD_OPTS}
