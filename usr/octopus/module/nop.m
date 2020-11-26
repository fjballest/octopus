Nop: module
{
	PATH:	con "/dis/o/nop.dis";

	BIT8SZ:	con int 1;
	BIT16SZ:	con int 2;
	BIT32SZ:	con int 4;
	BIT64SZ:	con int 8;
	QIDSZ:	con BIT8SZ+BIT32SZ+BIT64SZ;

	NOTAG:	con 16rFFFF;
	NOFD:	con int ~0;

	MAXDATA:	con 16*1024;	# `reasonable' iounit (size of .data fields)

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
	Tclunk,		# 11
	Rclunk,
	Tremove,		# 13
	Rremove,
	Tinval,		# 15
	Rinval,
	Tmax: con 1+iota;

	ERRMAX:	con 128;

	# open mode bits in Tput/Tget.mode
	OREAD:		con 0; 		# open for read
	OWRITE:		con 1; 		# write
	ORDWR:		con 2; 		# read and write
	ONONE:		con 3;		# do not allocate fd
	OMODE:		con 3;		# mask for open mode bits.

	# flags for Tput/Rget
	OCREATE:		con 16r10;		# create the file (OTRUNC)
	OEOF:		con 16r20;		# no more data avail
	OREMOVEC:		con 16r40;		# remove on clunk. (ORCLOSE).

	# Qid.qtype	(only QTDIR used by Op; all used by Styx).
	QTDIR:		con 16r80;
	QTAPPEND:		con 16r40;
	QTEXCL:		con 16r20;
	QTCACHE:		con 16r10;		# file can be cached.
	QTAUTH:		con 16r08;
	QTTMP:		con 16r04;
	QTFILE:		con 16r00;

	Tmsg: adt {
		tag: int;
		pick {
		Attach =>
			version: string;	# protocol version
			uname: string;	# user responsible for rpcs
			path: string;		# subtree to attach to.
		Flush =>
			oldtag: int;		# tag for flushed request
		Put =>
			path: string;		# of file
			fd: int;		# for file
			mode : int;		# fd mode and flags
			dir: ref Sys->Dir;	# metadata or nil
			offset: big;		# for data
			data: array of byte;	# data or nil
		Get =>
			path: string;		# of file
			fd: int;		# of file
			mode: int;		# fd mode and flags
			mcount: int;		# max nb of reply messages
			offset: big;		# in bytes (ignored for dirs)
			count: int;		# max data expected
		Clunk =>
			fd: int;
		Remove => 
			path: string;	# of file
			fd: int;
		Inval =>
		}

		bread:		fn(b: ref Blks->Blk): ref Tmsg;
		unpack:		fn(a: array of byte): (int, ref Tmsg);
		pack:		fn(nil: self ref Tmsg): array of byte;
		packedsize:		fn(nil: self ref Tmsg): int;
		text:		fn(nil: self ref Tmsg): string;
		mtype: 		fn(nil: self ref Tmsg): int;
	};

	Rmsg: adt {
		tag: int;
		pick {
		Error =>
			ename: string;
		Attach =>
			version: string;
		Put =>
			fd: int;
			count: int;
			qid: Sys->Qid;
			mtime: int;
		Get =>
			fd: int;
			mode: int;
			offset: big;
			dir: ref Sys->Dir;
			data: array of byte;
		Flush or Clunk or Remove =>
		Inval =>
			paths: string;	# paths invalidated
		}

		bread:		fn(b: ref Blks->Blk): ref Rmsg;
		unpack:		fn(a: array of byte): (int, ref Rmsg);
		pack:		fn(nil: self ref Rmsg): array of byte;
		packedsize:		fn(nil: self ref Rmsg): int;
		text:		fn(nil: self ref Rmsg): string;
		mtype: 		fn(nil: self ref Rmsg): int;
	};

	init:		fn(s: Sys, b: Blks);
	packdirsize:		fn(d: ref Sys->Dir): int;
	packdir:		fn(a: array of byte, off: int, d: ref Sys->Dir): int;
	unpackdir: 		fn(f: array of byte, off: int): (int, ref Sys->Dir);
	dir2text:		fn(d: ref Sys->Dir): string;
	qid2text:		fn(q: Sys->Qid): string;
};
