#!/dis/sh.dis
load std
cd /keydb
echo auth/createsignerkey `{ndb/query sys pc dom} may take a while...
test -e signerkey || auth/createsignerkey `{ndb/query sys pc dom}

ndb/cs
echo type your PC password if prompted.
echo Later, an account will be created for you.
svc/auth -n /keydb/nvr
user=`{cat /dev/user}
echo auth/changelogin $user
auth/changelogin $user
ls -l /mnt/keys/$user
getauthinfo default
echo your PC is installed and configured.
echo run o/pcrc from a shell window in your new Inferno
echo to start running your octopus PC
echo halt >/dev/sysctl

