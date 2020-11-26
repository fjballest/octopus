Op: module
{
	PATH:	con "/dis/o/op.dis";

	BIT8SZ:	con 1;
	BIT16SZ:	con 2;
	BIT32SZ:	con 4;
	BIT64SZ:	con 8;
	QIDSZ:	con BIT8SZ+BIT32SZ+BIT64SZ;

	NOTAG:	con 16rFFFF;
	NOFD:	con int ~0;

	STATFIXLEN:	con BIT16SZ+QIDSZ+5*BIT16SZ+4*BIT32SZ+BIT64SZ;	
	MAXDATA: con 16*1024;	# `reasonable' iounit (size of .data fields)
	MAXHDR: con 1024;		# reasonable size for biggest header

	Tattach,		# 1
	Rattach,
	Terror,		#  3 illegal
	Rerror,
	Tflush,		# 5
	Rflush,
	Tput,		# 7
	Rput,
	Tget,		# 9
	Rget,
	Tremove,		# 11
	Rremove,
	Tmax: con 1+iota;

	ERRMAX:	con 128;

	# mode bits in Tput/Tget.mode used by the protocol
	ODATA:		con int 1 <<1;		# put/get data
	OSTAT:		con int 1 <<2;		# put/get stat
	OCREATE:	con int 1 <<3;			# create the file (or truncate)
	OMORE:		con int 1 <<4;		# more data going/comming later
	OREMOVEC:	con int 1 <<5;		# remove after final put.

	# Qid.qtype	(only QTDIR used by Op; all used by Styx).
	QTDIR:	con 16r80;
	QTAPPEND:	con 16r40;
	QTEXCL:	con 16r20;
	QTAUTH:	con 16r08;
	QTFILE:	con 16r00;

	Tmsg: adt {
		tag: int;
		pick {
		Readerror =>
			error: string;		# tag is unused in this case
		Attach =>
			uname: string;		# user name responsible for rpcs
			path: string;		# subtree we want to attach to.
		Flush =>
			oldtag: int;		# tag for flushed request
		Put =>
			path: string;		# of file
			fd: int;			# for file
			mode : int;		# bit-or of OSTAT|ODATA|OCREATE|OMORE
			stat: Sys->Dir;		# for file
			offset: big;		# for data
			data: array of byte;
		Get =>
			path: string;		# of file
			fd: int;			# of file
			mode: int;			# bit-or of OSTAT|ODATA|OMORE
			nmsgs: int;		# max number of Rgets for reply. 0==unlimited.
			offset: big;		# byte offset (ignored for dirs)
			count: int;			# max data expected per message
		Remove => 
			path: string;		# of file
		}

		read:	fn(fd: ref Sys->FD, msize: int): ref Tmsg;
		unpack:	fn(a: array of byte): (int, ref Tmsg);
		pack:	fn(nil: self ref Tmsg): array of byte;
		packedsize:	fn(nil: self ref Tmsg): int;
		text:	fn(nil: self ref Tmsg): string;
		mtype: fn(nil: self ref Tmsg): int;
	};

	Rmsg: adt {
		tag: int;
		pick {
		Readerror =>
			error: string;		# tag is unused in this case
		Error =>
			ename: string;
		Attach or Flush =>
		Put =>
			fd: int;
			count: int;
			qid:	Sys->Qid;
			mtime: int;
		Get =>
			fd: int;
			mode: int;		# bit or of OSTAT|ODATA|OMORE
			stat: Sys->Dir;
			data: array of byte;
		Remove =>
		}

		read:	fn(fd: ref Sys->FD, msize: int): ref Rmsg;
		unpack:	fn(a: array of byte): (int, ref Rmsg);
		pack:	fn(nil: self ref Rmsg): array of byte;
		packedsize:	fn(nil: self ref Rmsg): int;
		text:	fn(nil: self ref Rmsg): string;
		mtype: fn(nil: self ref Rmsg): int;
	};

	init:	fn();

	readmsg:	fn(fd: ref Sys->FD, msize: int): (array of byte, string);
	istmsg:	fn(f: array of byte): int;

	packdirsize:	fn(d: Sys->Dir): int;
	packdir:	fn(d: Sys->Dir): array of byte;
	unpackdir: fn(f: array of byte): (int, Sys->Dir);
	dir2text:	fn(d: Sys->Dir): string;
	qid2text:	fn(q: Sys->Qid): string;

};

