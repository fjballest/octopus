implement Browserfs;
include "sys.m";
	sys: Sys;
	Dir, pctl, NEWPGRP, DMDIR, open, OREAD, FD, OWRITE, ORCLOSE, FORKFD,
	ORDWR, FORKNS, NEWFD, MREPL, MBEFORE, MAFTER, MCREATE, pipe, mount,
	fprint, sprint, create, pwrite, read, QTDIR, QTFILE, fildes, Qid: import sys;
include "draw.m";
include "styx.m";
	styx: Styx;
	Rmsg, Tmsg: import styx;
include "error.m";
	err: Error;
	checkload, stderr, panic, kill, error: import err;
include "styxservers.m";
	styxs: Styxservers;
	Styxserver, readbytes, readstr, Navigator, Fid: import styxs;
	nametree: Nametree;
	Tree: import nametree;
include "daytime.m";
	daytime: Daytime;
	now: import daytime;
include "arg.m";
	arg: Arg;
	usage: import arg;
include "netget.m";
	netget: Netget;
include "string.m";
	str: String;
	splitr: import str;
include "env.m";
	env: Env;
	getenv: import env;

include "io.m";
	io: Io;
	readdev: import io;
include "browsercmd.m";
	browsercmd: Browsercmd;
	puthistory, putbookmarks, getbookmarks, getopen, gethistory, openurls, 
	closebrowser, startbrowser, restartbrowser, getstatus:	import browsercmd;


Browserfs: module {
	PATH:	con "/dis/o/browserfs.dis";

	init: fn(nil: ref Draw->Context, argv: list of string);
};

MAXDATALEN: con 1024*1024*10;
DIRTY: con 666;

Qroot, Qctl, Qopen, Qhistory, Qbookmarks: con big iota;
Uctl, Uopen, Uhistory, Ubookmarks: int; # exclusive open flag for each file 
Dopen, Dhistory, Dbookmarks: string; # data string for each readable file
debug: int;
user: string;
argv0 := "browserfs";

newdir(name: string, perm: int, qid: big): Dir
{
	d := sys->zerodir;
	d.name = name;
	d.uid = user;
	d.gid = user;
	d.qid.path = qid;
	if(perm & DMDIR)
		d.qid.qtype = QTDIR;
	else
		d.qid.qtype = QTFILE;
	d.mode = perm;
	return d;
}

## open, bookmarks and history files have write-back semantics
## their data is "written" in the host when files are clunked

fsreq(srv: ref Styxserver, nil: ref Tree, req: ref Tmsg) : ref Rmsg
{
	pick m := req {
	Readerror =>
		if(debug)  fprint(sys->fildes(2),"fsreq: readerror\n");
		return nil;
	Version =>
		if(debug) fprint(sys->fildes(2),"fsreq: version\n");
		return nil;
	Auth =>
		if(debug) fprint(sys->fildes(2),"fsreq: auth\n");
		return nil;
	Attach =>
		if(debug) fprint(sys->fildes(2),"fsreq: attach\n");
		return nil;
	Flush =>
		if(debug) fprint(sys->fildes(2),"fsreq: flush\n");
		return nil;
	Walk =>
		if(debug) fprint(sys->fildes(2),"fsreq: walk\n");
		return nil;
	Stat  => 
		if(debug) fprint(sys->fildes(2),"fsreq: stat\n");
		return nil;
	Open => 
		if(debug) fprint(sys->fildes(2),"fsreq: open: m.fid: %d \n" , m.fid);
		(fid, nil, d, e) := srv.canopen(m);
		if(fid.qtype & QTDIR)
			return nil;
		if(e != nil)
			return ref Rmsg.Error(m.tag, e);
		if(fid.uname != user) 
			return ref Rmsg.Error(m.tag, "permission denied");
		case fid.path {
		Qctl =>
			;
			 # no exclusive open for ctl
		Qopen =>
			if(Uopen)
				return ref Rmsg.Error(m.tag,"open file already open");
			if(m.mode == Sys->OREAD || m.mode == Sys->ORDWR)
				Dopen = getopen();
			Uopen++;
		Qhistory =>
			if(Uhistory)
				return ref Rmsg.Error(m.tag,"history file already open");
			if(m.mode == Sys->OREAD || m.mode == Sys->ORDWR)
				Dhistory = gethistory();
			Uhistory++;
		Qbookmarks =>
			if(Ubookmarks)
				return ref Rmsg.Error(m.tag,"bookmarks file already open");
			if(m.mode == Sys->OREAD || m.mode == Sys->ORDWR)
				Dbookmarks = getbookmarks();
			Ubookmarks++;
		* =>
			return ref Rmsg.Error(m.tag, "unknown file");
		}
		fid.open(m.mode, d.qid);
		return ref Rmsg.Open(m.tag, d.qid, srv.iounit());
	Create =>
		if(debug) fprint(sys->fildes(2),"fsreq: create\n");
		return ref Rmsg.Error(m.tag, "creation is forbidden");
	Remove =>
		return ref Rmsg.Error(m.tag, "removing is forbidden");
	Read =>
		if(debug) fprint(sys->fildes(2),"fsreq: read: m.fid: %d \n" , m.fid);
		(fid, e) := srv.canread(m);
		if(e != nil)
			return ref Rmsg.Error(m.tag, e);
		if(fid.qtype&QTDIR)
			return nil;
		case fid.path {
		Qctl =>
			status := getstatus();
			return readstr(m, status + "\n");
		Qopen =>
			return readstr(m, Dopen);	
		Qbookmarks =>
			return readstr(m, Dbookmarks);	
		Qhistory =>
			return readstr(m, Dhistory);	
		}
		return ref Rmsg.Error(m.tag, "no such file");
	Write =>
		if(debug) fprint(sys->fildes(2),"fsreq: write: m.fid: %d \n" , m.fid);
		(fid, nil) := srv.canwrite(m);
		if(fid.qtype & QTDIR)
			return ref Rmsg.Error(m.tag, "permission denied");
		case fid.path{
		Qctl =>
			# CTL does not handle big writes, it can do the job here.
			if(processctl(m.data) < 0)
				return ref Rmsg.Error(m.tag, "wrong ctl data");
			return ref Rmsg.Write(m.tag, len m.data);
		Qopen =>
			f := writefile(Dopen , int m.offset,  m.data);
			if(f == nil)
				return ref Rmsg.Error(m.tag, "file is too long");
			Uopen = DIRTY;
			Dopen =  f;
			return ref Rmsg.Write(m.tag, len m.data);
		Qhistory =>
			f := writefile(Dhistory , int m.offset,  m.data);
			if(f == nil)
				return ref Rmsg.Error(m.tag, "file is too long");
			Uhistory = DIRTY;
			Dhistory =  f;
			return ref Rmsg.Write(m.tag, len m.data);
		Qbookmarks =>
			f := writefile(Dbookmarks , int m.offset,  m.data);
			if(f == nil)
				return ref Rmsg.Error(m.tag, "file is too long");
			Ubookmarks = DIRTY;
			Dbookmarks =  f;
			return ref Rmsg.Write(m.tag, len m.data);
		}
		return ref Rmsg.Error(m.tag, "permission denied");
	Clunk =>		
		if(debug) 	fprint(sys->fildes(2),"fsreq: clunk: m.fid: %d \n" , m.fid);
		fid := srv.getfid(m.fid);
		if(fid == nil)
			return ref Rmsg.Error(m.tag, "bad fid");
		if(fid.isopen){
			case fid.path {
			# no exclusive open and write back  for Qctl file
			Qopen =>
				if(!Uopen)
					return ref Rmsg.Error(m.tag, "browserfs: bug : clunk open ref == 0");
				if(Uopen == DIRTY){
		 			if(openurls(Dopen) < 0){
						Uopen = 0;
						Dopen = nil;
						srv.delfid(fid);
						return ref Rmsg.Error(m.tag, "data not commited");
					}
				}
				Uopen = 0;
				Dopen = nil;
			Qhistory =>
				if(!Uhistory)
					return ref Rmsg.Error(m.tag, "browserfs: bug : clunk history ref == 0");
				if(Uhistory == DIRTY){
		 			if(puthistory(Dhistory) < 0){
						Uhistory = 0;
						Dhistory = nil;
						srv.delfid(fid);
						return ref Rmsg.Error(m.tag, "data not commited");
					}
				}
				Uhistory = 0;
				Dhistory = nil;
			Qbookmarks =>
				if(!Ubookmarks)
					return ref Rmsg.Error(m.tag, "browserfs: bug : clunk bookmarks ref == 0");
				if(Ubookmarks == DIRTY){
		 			if(putbookmarks(Dbookmarks) < 0){
						Ubookmarks = 0;
						Dbookmarks = nil;
						srv.delfid(fid);
						return ref Rmsg.Error(m.tag, "data not commited");
					}
				}
				Ubookmarks = 0;
				Dbookmarks = nil;
			}
		}
		srv.delfid(fid);
		return ref Rmsg.Clunk(m.tag);
	Wstat =>
		return ref Rmsg.Wstat(m.tag);
	* =>
		return nil;
	}
}


# emulates a standard write()
writefile(f: string , offset: int,  data: array of byte): string
{
	if(len data == 0)
		return f;
	ori := array of byte f;
	if(offset + len data >= MAXDATALEN){
		if(debug) sys->fprint(fildes(2), "writefile: error: too long\n");
		return nil;
	}
	if(offset + len data > len ori){
		buf := array [offset + len data ] of { * => byte 0};
		buf[0:] = ori;
		buf[offset:] = data;
		if(debug) sys->fprint(fildes(2), "writefile: file:\n%s\n", string buf);
		return string buf;
	}
	ori[offset:] = data;
	if(debug) sys->fprint(fildes(2), "writefile: file:\n%s\n", string ori);
	return string ori;
}


# The second parameter is the fd to listen for styx RPCs
# it can be stdin or a pipe (if its mounted in mnt)
# styxservers reads RPCs and forwards them through a chan (reqc)
fs(pidc: chan of int, fd: ref FD)
{
	styx->init();
	styxs->init(styx);
 	user = getenv("user");
	if(user == nil)
		user = readdev("/dev/user", "none");
	if(pidc != nil)
		pidc <-= pctl(FORKNS|NEWPGRP|NEWFD, list of {0,1,2,fd.fd});
	else
		pctl(NEWPGRP, nil);
	stderr = fildes(2);
	netget->announce(argv0, sprint("path /%s", argv0));
	(tree, navc) := nametree->start();
	nav := Navigator.new(navc);
	# init styxservers with FD, navigator and the root qid
	(reqc, srv) := Styxserver.new(fd, nav, Qroot);
	tree.create(Qroot, newdir(".", DMDIR|8r775, Qroot));
	tree.create(Qroot, newdir("ctl", 8r660, Qctl));
	tree.create(Qroot, newdir("open", 8r660, Qopen));
	tree.create(Qroot, newdir("history", 8r660, Qhistory));
	tree.create(Qroot, newdir("bookmarks", 8r660, Qbookmarks));
	for(;;) {
		req := <-reqc;
		if(req == nil)
			break;	
		if(debug) 	fprint(sys->fildes(2),"fs: request received\n" );
		rep := fsreq(srv, tree, req);
		if(rep == nil)
			srv.default(req);
		else
			srv.reply(rep);
	}
	tree.quit();
	netget->terminate(); 
	kill(pctl(0, nil),"killgrp");	# be sure to quit
}


processctl(data: array of byte): int
{
	strdata := string data[0:len data -1];
	(ntok, tok) :=  sys->tokenize(strdata, " 	");
	# for now, no argument are allowed
	if(ntok != 1)
		return -1;
	if(hd tok == "inactive"){
		if(debug)  fprint(sys->fildes(2),"processctl: inactive\n");
		return closebrowser();
	}else if(hd tok == "active"){
		if(debug) fprint(sys->fildes(2),"processctl: active\n");
		return startbrowser();
	}else if(hd tok == "restart"){
		if(debug) fprint(sys->fildes(2),"processctl: restart\n");
		return restartbrowser();
	}
	return -1;
}


init(nil: ref Draw->Context, args: list of string)
{

	sys = load Sys Sys->PATH;
	err = load Error Error->PATH;
	err->init(sys);
	str = checkload(load String String->PATH, String->PATH);
	styx = checkload(load Styx Styx->PATH, Styx->PATH);
	styxs = checkload(load Styxservers Styxservers->PATH, Styxservers->PATH);
	nametree = checkload(load Nametree Nametree->PATH, Nametree->PATH);
	nametree->init();
 	daytime = checkload(load Daytime Daytime->PATH, Daytime->PATH);
	io = checkload(load Io Io->PATH, Io->PATH);
	env = checkload(load Env Env->PATH, Env->PATH);
	netget = checkload(load Netget Netget->PATH, Netget->PATH);
	arg = checkload(load Arg Arg->PATH, Arg->PATH);
	arg->init(args);
	arg->setusage("browserfs [-d] [-m mnt]");
	browsercmd = checkload(load Browsercmd Browsercmd->PATH, Browsercmd->PATH);
	browsercmd->init();
	mnt: string;
	Uctl = 0;
	Uopen = 0;
	Uhistory= 0;
	Ubookmarks = 0;
	flag := MREPL|MCREATE;
	while((opt := arg->opt()) != 0) {
		case opt{
		'd' =>
			debug = 1;
			browsercmd->debug = 1;
			styxs->traceset(1);
		'm' =>
			mnt = arg->earg();
		* =>
			usage();
		}
	}

	# fildes returns the Limbo file descriptor in this position
	if(mnt == nil){
		fs(nil, fildes(0));
	}else {
		pfds := array[2] of ref FD;
		if(pipe(pfds) < 0)
			error(sprint("browserfs: pipe: %r"));
		pidc := chan of int;
		spawn fs(pidc, pfds[0]);
		<-pidc;
		if(mount(pfds[1], nil, mnt, flag, nil) < 0)
			error(sprint("browserfs: mount (mnt: %s): %r", mnt));
		pfds[0] = nil;
	}
}



