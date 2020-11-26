# Srvs module for Nop import, adapted from Inferno's
# styxservers.b
Ssrv: module
{
	PATH: con "/dis/o/ofs/ofsstyx.dis";

	Fid: adt {
		fid:	int;
		path:	big;
		qtype:	int;
		isopen:	int;
		mode:	int;	# if open, the open mode
		doffset:	(int, int);	# (internal) cache of directory offset
		uname:	string;	# user name from original attach
		param:	string;	# attach aname from original attach

		ofd:	int;	# fid used by Op, if any.
		cfd:	ref Sys->FD;# fd used by the cache, if any.
		nawrites:	int;	# nb. of writes (to decide if async)

		clone:	fn(f: self ref Fid, nf: ref Fid): ref Fid;
		open:	fn(f: self ref Fid, mode: int, qid: Sys->Qid);
		walk:	fn(f: self ref Fid, qid: Sys->Qid);
	};

	Srv: adt {
		fids:	array of list of ref Fid;
		fidlock:	chan of int;
		rootpath:	big;
		msize:	int;
		reqc:	chan of ref Styx->Tmsg;
		repc:	chan of ref Styx->Rmsg;

		new:	fn(rq: big): ref Srv;

		version:	fn(srv: self ref Srv, m: ref Styx->Tmsg.Version):
			ref Styx->Rmsg;
		auth:	fn(srv: self ref Srv, m: ref Styx->Tmsg.Version):
			ref Styx->Rmsg;
		attach:	fn(srv: self ref Srv, m: ref Styx->Tmsg.Attach):
			ref Styx->Rmsg;
		stat:	fn(srv: self ref Srv, m: ref Styx->Tmsg.Stat):
			ref Styx->Rmsg;
		walk:	fn(srv: self ref Srv, m: ref Styx->Tmsg.Walk):
			ref Styx->Rmsg;
		open:	fn(srv: self ref Srv, m: ref Styx->Tmsg.Open):
			ref Styx->Rmsg;
		create:	fn(srv: self ref Srv, m: ref Styx->Tmsg.Create):
			ref Styx->Rmsg;
		read:	fn(srv: self ref Srv, m: ref Styx->Tmsg.Read):
			ref Styx->Rmsg;
		write:	fn(srv: self ref Srv, m: ref Styx->Tmsg.Write):
			ref Styx->Rmsg;
		clunk:	fn(srv: self ref Srv, m: ref Styx->Tmsg.Clunk):
			ref Styx->Rmsg;
		remove:	fn(srv: self ref Srv, m: ref Styx->Tmsg.Remove):
			ref Styx->Rmsg;
		wstat:	fn(srv: self ref Srv, m: ref Styx->Tmsg.Wstat):
			ref Styx->Rmsg;

		getfid:	fn(srv: self ref Srv, fid: int): ref Fid;
		newfid:	fn(srv: self ref Srv, fid: int): ref Fid;
		delfid:	fn(srv: self ref Srv, c: ref Fid);
		allfids:	fn(srv: self ref Srv): list of ref Fid;

		iounit:	fn(srv: self ref Srv): int;
	};

	init:	fn(styx: Styx);

	Einuse:	con "fid already in use";
	Ebadfid:	con "bad fid";
	Eopen:	con "fid already opened";
	Enotfound:	con "file does not exist";
	Enotdir:	con "not a directory";
	Eperm:	con "permission denied";
	Ebadarg:	con "bad argument";
	Eexists:	con "file already exists";
	Emode:	con "open/create -- unknown mode";
	Eoffset:	con "read/write -- bad offset";
	Ecount:	con "read/write -- count negative or exceeds msgsize";
	Enotopen:	con "read/write -- on non open fid";
	Eaccess:	con "read/write -- not open in suitable mode";
	Ename:	con "bad character in file name";
	Edot:	con ". and .. are illegal names";
	Enotempty:	con "directory not empty";
	debug:	int;
};
