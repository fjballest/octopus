#!/bin/sh
#
# Octopus installation script for Unix.
# 
fail() {
	echo error: $*
	exit 1
}

ask() {
	if test $# -eq 1 ; then
		p="$1? " 
	else
		p="$1? [$2] "
	fi
	read -p"$p" r

	if test -z $r ; then
		if test $# -eq 2 ; then
			r=$2
		fi
	fi
	result=$r
}

readsecret() {
	x1=a
	x2=b
	while test $x1 != $x2 ; do
		stty -echo
		read -p'your new PC password? ' x1
		echo
		read -p'confirm your new PC password? ' x2
		echo
		stty echo
	done
	/bin/echo -n $x1 >keydb/nvr
	chmod 600 keydb/nvr
}

if test ! -e libprefab ; then
	echo change the directory to the place
	echo where you extracted the distribution
	echo and run this script from there.
	exit 1
fi
dir=`pwd`

echo $dir
echo Install directory is $dir
cd $dir
chmod +x ./*/386/bin/* 
chmod +x ./usr/octopus/lib/*.sh ./usr/octopus/lib/*.rc ./usr/octopus/lib/wmsetup
chmod  +x dis/*/*/* dis/*/* dis/*
user=`whoami`
sysname=`uname -n | sed 's/\..*//'`
if test ! -d usr/$user ; then
	echo creating your inferno home
	mv usr/inferno usr/$user || fail cannot create home
fi

grep -s $sysname lib/ndb/local || {
	echo configuring ndb
	ok=no
	while test $ok = no ; do
		ask 'your sysname name' $sysname ; sysname=$result
		ask 'your domain name'  ; dom=$result
		ask 'your ip' ; ip=$result
		ask 'your PC fully qualified name' ; pc=$result
		ask 'your PC ip' ; pcip=$result
		ask 'your dns server' ; dns=$result
		echo 'sys=' $sysname
		echo 'dom=' $dom
		echo 'ip=' $ip
		echo 'dns=' $dns
		echo 'pc=' $pc
		echo 'pcip=' $pcip
		ask 'is this ok' yes ; ok=$result
	done
}
cat >lib/ndb/local <<EOF
database=
	file=/lib/ndb/local
	file=/lib/ndb/dns
	file=/lib/ndb/inferno
	file=/lib/ndb/common
	file=/lib/ndb/octopus

#
# default site-wide resources
#
infernosite=
	dnsdomain=$dom
	dns=$dns
	SIGNER=$pc
	FILESERVER=$pc
	smtp=$pc
	pop3=$pc
	PROXY=$pc
	GAMES=$pc
	registry=$pc
	gridsched=$pc

sys=$sysname dom=$sysname.$dom ip=$ip
sys=pc dom=$pc ip=$pcip
EOF

if test -d /Library ; then
	MacOSX/386/bin/emu -r $dir /usr/octopus/lib/setupterm.sh
else
	Linux/386/bin/emu -r $dir /usr/octopus/lib/setupterm.sh
fi
echo all done
echo
echo 'After starting Inferno, you have to run'
echo '	' o/termrc
echo on a shell window to start the octopus terminal.
echo You might also edit your lib/wmsetup file to do just this.
echo

exit 0
