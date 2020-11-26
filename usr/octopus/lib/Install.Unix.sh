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
		ask 'your dns server' ; dns=$result
		ask 'your ip' ; ip=$result
		echo 'sys=' $sysname
		echo 'dom=' $dom
		echo 'dns=' $dns
		echo 'ip=' $ip
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
	SIGNER=pc
	FILESERVER=pc
	smtp=pc
	pop3=pc
	PROXY=pc
	GAMES=pc
	registry=pc
	gridsched=pc

sys=pc dom=$sysname.$dom ip=$ip
sys=$sysname dom=$sysname.$dom ip=$ip
EOF

if test ! -e keydb/nvr ; then
	echo configuring your account. If you interrupt this,
	echo remove all files in $dir/keydb and re-run this script
	readsecret
	cp /dev/null keydb/keys
	chmod 600 keydb/keys
	if test -d /Library ; then
		MacOSX/386/bin/emu -r $dir /usr/octopus/lib/setup.sh
	else
		Linux/386/bin/emu -r $dir /usr/octopus/lib/setup.sh
	fi
fi
echo all done
exit 0
