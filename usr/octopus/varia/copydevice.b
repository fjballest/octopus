implement CopyDevice;

include "sys.m";
include "draw.m";
include "string.m"; 
include "styx.m";
include "styxservers.m";
include "daytime.m";
include "sh.m";

CopyDevice: module
{ 
  init: fn(ctxt: ref Draw->Context, argv: list of string);
};

sys: Sys;
str: String;
styx: Styx;
styxservers: Styxservers;
nametree: Nametree;
dtime: Daytime;
sh: Sh;

Styxserver, Navigator, Fid: import styxservers;
Tree: import nametree;
Tmsg, Rmsg: import styx;

MNTDIR: con "/tmp/cpd_mnts";	# dirname prefix for temp mounts

IDLE, RUNNING, EOF, DONE, 
RWERR, ABORT, KILL: con iota;	# state codes

MNTIDLETIME: con 60;		# mount point idle time in seconds 

MntPnt: adt {
	addr: string;		# addr of remote server
	path: string;		# local mount point
	lifet: int;		# lifetime before removed
	used: int;		# used by an ongoing copy op
};

CopyOpDesc: adt {
#	ctlfname: string;	# name of control file
#	qid: big;		# qid of the control file
	fid: int;		# fid of the opened control file
	# mount stuff
	srcaddr: string;	# source dial address
	dstaddr: string;	# dest dial address
	#copy arguments
	srcfname: string;	# source file pathname
	srcoff: big;		# source read offset
	dstfname: string; 	# dest file pathname
	dstoff: big;		# dest write offset
	nofbytes: big;		# nof bytes to copy from source to dest
	# additional state
	state: int;		# current state of copy op
	bytecnt: big;		# nof bytes copied so far
#	srcmntdir: string; 	# temp source mount dir
	srcmntpnt: ref MntPnt;	# source mount point
	srcfd: ref sys->FD;	# source file descriptor for reading
#	dstmntdir: string;	# temp dest mount dir
	dstmntpnt: ref MntPnt;	# destination mount point
	dstfd: ref sys->FD;	# dest file descriptor for writing
	mtag: int;		# tag of the write msg that started the copy 
	reply: ref Rmsg;	# write reply message, for normal completion	
};

# BUG:
# the r/w synchronization for the bytecnt field 
# see BUG comments in routines handleTmsg and copyThread

cqid := big 0;			# seed for generating unique qids
Qroot, Qnew: big;		# root dir and clone file qids
nfy: chan of ref CopyOpDesc;	# notification copy threads -> main server thread
cpops: list of ref CopyOpDesc;	# list of ongoing copy ops
mntpts: list of ref MntPnt;	# list of active mount points
iobuflen: int;			# size of io buffer for copy ops

debug: int;			# print msgs sent/received and other state info


dprint(msg: string)
{
	if (debug)
		sys->fprint(sys->fildes(2), "%s\n", msg);
}


# copy op management; simple and non-optimized

printCopyOps()
{
	s := "ongoing copy ops: ";
	for (cl := cpops; cl != nil; cl = tl cl) 
		s = s + sys->sprint("%d ",(hd cl).fid);
	s = s + "~";
	dprint(s);
}

initCopyOps()
{
	cpops = nil;
}

addCopyOp(fid: int): ref CopyOpDesc
{
	cp := ref CopyOpDesc(fid,
	                     nil, nil, nil, big 0, nil, big 0, big 0,
	                     IDLE, big 0, nil, nil, nil, nil, 0, nil);
	cpops = cp :: cpops;
	printCopyOps();
	return(cp);
}

rmvCopyOp(cp: ref CopyOpDesc)
{
	cpops2: list of ref CopyOpDesc;

	cpops2 = nil;
	for (cl := cpops; cl != nil; cl = tl cl)
		if (hd cl != cp)
			cpops2 = hd cl :: cpops2;
	cpops = cpops2;
	printCopyOps();
}

fndCopyOpByTag(mtag: int): ref CopyOpDesc
{
	for (cl := cpops; cl != nil; cl = tl cl)
		if ((hd cl).mtag == mtag)
			return(hd cl);
	return(nil); 
}

fndCopyOpByFid(fid: int): ref CopyOpDesc
{
	for (cl := cpops; cl != nil; cl = tl cl)
		if ((hd cl).fid == fid)
			return(hd cl);
	return(nil); 
}


# cmd execution via shell

runcmd(ctxt: ref Draw->Context, cmdline: string): string
{
	sh = load Sh Sh->PATH;
	if (sh == nil)
		return(sys->sprint("could not load Sh module: %r"));

	(n, args) := sys->tokenize(cmdline, " \t\n");
	if (n == 0)
		return sys->sprint("empty command line string\n");

	c := chan of int;
	fd := sys->open("/prog/"+string sys->pctl(0,nil)+"/wait", Sys->OREAD);
	fds := array[2] of ref Sys->FD;
	sys->pipe(fds);

	spawn doruncmd(ctxt, args, fds[1], c);
	pid := <- c;

	pidstr := sys->sprint("%d ",pid);
	waitstr: string;
	buf := array [256] of byte;

	do {
		n = sys->read(fd, buf, len buf);
		waitstr = string buf[0:n];
	} while (!str->prefix(pidstr, waitstr));

	(res, d) := sys->fstat(fds[0]);
	if (d.length == big 0) { return(nil); } 

	n = sys->read(fds[0], buf, len buf);
	return(string buf[0:n]);
}

doruncmd(ctxt: ref Draw->Context, args: list of string, errfd: ref sys->FD, c: chan of int)
{
	pid := sys->pctl(sys->FORKFD, nil);
	sys->dup(errfd.fd, 2);
	c <-= pid;
	sh->run(ctxt, args);
}


# mount and unmount; for convenience implemented using shell commands

unmount(mntdir: string)
{
	runcmd(nil, "unmount " + mntdir);
	runcmd(nil, "rm " + mntdir);
}

mount(addr, mntdir: string): string 
{
	if (addr == "localhost")
		return (nil);
	 
	 err := runcmd(nil, "mkdir " + mntdir);
	if (err != nil)
		return (err);

	err = runcmd(nil, "mount -cA tcp!" + addr + " " + mntdir);
	if (err != nil) {
		runcmd(nil, "rm " + mntdir);
		return (err);
	}

	return (nil);
}


# mount point management; simple and non-optimized

printMntPts()
{
	s := "active mount points: ";
	for (mpl := mntpts; mpl != nil; mpl = tl mpl) 
		s = s + sys->sprint("%s", (hd mpl).addr);
	s = s + "~";
	dprint(s);
}

initMntPnts()
{
	mntpts = nil;
}

gcMntPnts()
{
	for (mpl := mntpts; mpl != nil; mpl = tl mpl)
		unmount((hd mpl).path);

	mntpts = nil;
}

fndMntPnt(addr: string): ref MntPnt
{
	mntptsnew: list of ref MntPnt;
	changed := int 0;
	mp, fmp: ref MntPnt; 

	mntptsnew = nil; fmp = nil;

	for (mpl := mntpts; mpl != nil; mpl = tl mpl) {
		mp := hd mpl;
		if (mp.addr == addr) {
			fmp = mp;
			mntptsnew = mp :: mntptsnew;
		}
		else if (mp.used)
			mntptsnew = mp :: mntptsnew;
		else if (mp.lifet - dtime->now() > 0)
			mntptsnew = mp :: mntptsnew;
		else {
			unmount(mp.path);
			changed = 1;
		}
	}

	mntpts = mntptsnew;
	if (changed)
		printMntPts();
	return (fmp);
}

addMntPnt(addr, path: string): (string, ref MntPnt)
{	
	err := mount(addr, path);
	if (err != nil)
		return ((err, nil));

	mp := ref MntPnt(addr, path, 0, 0);
	mntpts = mp :: mntpts;
	printMntPts();
	return((nil, mp));
}


# file open

open(mntdir, fname: string, off: big, mode : int): (string, ref sys->FD)
{
	fd: ref sys->FD;
	if (mode == sys->OREAD)
		fd = sys->open(mntdir + fname, mode);
	else if (mode == sys->OWRITE)
		fd = sys->create(mntdir + fname, mode, 8r777);
		#BUG:
		# ownership and access rights when creating a file?
	
	if (fd == nil) 
		return ((sys->sprint("could not open %s: %r", fname), nil));

	sys->seek(fd, off, Sys->SEEKSTART);
	return((nil, fd));
}

mount_open(addr, fname: string, off: big, mode: int): (string, ref MntPnt, ref sys->FD)
{
	mp: ref MntPnt; mp = nil;
	err, mntdir: string;

	if (addr == "localhost") {
		mntdir = nil;
		if (fname[0] == '/')
			fname = fname[1:];
	} 
	else {
		mp = fndMntPnt(addr);
		if (mp == nil) 
			(err, mp) = addMntPnt(addr, MNTDIR + "_" + addr);
			if (err != nil) 
				return ((err, nil, nil));
		mntdir = mp.path;
	}

	(err2, fd) := open(mntdir, fname, off, mode);
	if (err2 != nil)
		return ((err2, nil, nil));

	return ((nil, mp, fd)); 	
}


# cmd parsing

isValidBig(num: string): (int, big)
{
	(b, s) := str->tobig(num, 10);
	return(((s == nil) && (b >= big 0), b));
} 

setCopyArgs(cpop: ref CopyOpDesc, args: list of string): string
{
	if ((args == nil) || (len args != 7))
		return("srcaddr, srcfname, dstaddr, dstfname, srcoff, dstoff, nofbytes expected");

	cpop.srcaddr = hd args; args = tl args;
	cpop.srcfname = hd args; args = tl args;

	cpop.dstaddr = hd args; args = tl args;
	cpop.dstfname = hd args; args = tl args;
	
	ok: int;
	s: string;

	s = hd args; args = tl args;
	(ok, cpop.srcoff) = isValidBig(s);
	if (!ok)
		return ("invalid srcoff value " + s);

	s = hd args; args = tl args;
	(ok, cpop.dstoff) = isValidBig(s);
	if (!ok)
		return ("invalid dstoff value " + s);

	s = hd args; args = tl args;
	(ok, cpop.nofbytes) = isValidBig(s);
	if (!ok)
		return("invalid nofbytes value " + s);

	return(nil);
}


# copy thread

startCopyThread(cp: ref CopyOpDesc): string
{
	err: string;

	(err, cp.srcmntpnt, cp.srcfd) = mount_open(cp.srcaddr, cp.srcfname, cp.srcoff, sys->OREAD);
	if (err != nil)
		return(err);

	if (cp.srcmntpnt != nil)
		cp.srcmntpnt.lifet = dtime->now() + MNTIDLETIME;

	(err, cp.dstmntpnt, cp.dstfd) = mount_open(cp.dstaddr, cp.dstfname, cp.dstoff, sys->OWRITE);
	if (err != nil)  
		return(err);

	if (cp.dstmntpnt != nil)
		cp.dstmntpnt.lifet = dtime->now() + MNTIDLETIME;
	
	cp.state = RUNNING;
	if (cp.srcmntpnt != nil)
		cp.srcmntpnt.used++;
	if (cp.dstmntpnt != nil)
		cp.dstmntpnt.used++; 
	
	spawn copyThread(cp);
	return(nil);
}

killCopyThread(cp: ref CopyOpDesc, cmd: int)
{
	cp.state = cmd;  # force copy thread to terminate, if not done yet
}

gcCopyOp(srv: ref Styxserver, cp: ref CopyOpDesc)
{
	 
	if (cp.srcmntpnt != nil) {
		cp.srcmntpnt.used--;
		cp.srcmntpnt.lifet = dtime->now() + MNTIDLETIME;
	}

	if (cp.dstmntpnt != nil) {
		cp.dstmntpnt.used--;
		cp.dstmntpnt.lifet = dtime->now() + MNTIDLETIME;
	}
	
	if (cp.state != ABORT)
		srv.reply(cp.reply);
	cp.state = IDLE;
} 

copyThread(cp: ref CopyOpDesc)
{
	cnt := big 0; 
	data := array [iobuflen] of byte;
	
	dprint(sys->sprint("copyThread started: %d", cp.fid));
  
	while (cp.state == RUNNING) {
		rcnt := len data;
		if ((cp.nofbytes > big 0) && (big rcnt > cp.nofbytes - cnt)) 
				rcnt = int (cp.nofbytes - cnt); 
		
		n1 := sys->read(cp.srcfd, data, rcnt);
		dprint(sys->sprint("read %d bytes", n1));
		if (n1 < 0) {
			cp.reply = ref Rmsg.Error(cp.mtag, sys->sprint("read error: %r"));
			cp.state = RWERR;
			break;
		} 
		else if (n1 == 0) {
			cp.state = EOF;
			break;
		}
		
		n2:= sys->write(cp.dstfd, data, n1);
		if (n2 != n1) {
			cp.reply = ref Rmsg.Error(cp.mtag, sys->sprint("write error: %r")); 
			cp.state = RWERR;
			break;
		}
		
		cnt = cnt + big n1;
		cp.bytecnt = cnt;

		# BUG: 
		# we change the value of bytecnt in "a single shot"
		# however, this does not guarantee read atomicity
		# so the main server thread may read invalid data
		# see BUG comment in function handleTMsg

		if (cnt == cp.nofbytes) {
			cp.state = DONE;
			break;
		}

	}
	
	if (cp.state != KILL)
		nfy <- = cp; # termination signal to main server thread

	termcodes := array [KILL+1] of {"IDLE", "RUNNING", "EOF", "DONE", "RWERRROR", "ABORTED", "KILLED"};
	dprint(sys->sprint("copyThread stopped: %d: %s", cp.fid, termcodes[cp.state]));
}


# main server thread

handleTmsg(srv: ref Styxserver, filetree: ref Tree, msg: ref Tmsg)
{
	if (msg == nil) {
		printCopyOps();
		gcMntPnts();
		dprint("stopping copy device");
		srv.default(msg);   # kills this process
		sys->fprint(sys->fildes(2), "copy server fatal: should be dead at this point");
		raise "fatal:noterm";
	}
	pick m := msg {
		
		Attach => {
			srv.default(msg);
			iobuflen = srv.iounit();
		}

		Open => {
			(f, mode, d, err) := srv.canopen(m);
			if (err != nil)
				srv.reply(ref Rmsg.Error(m.tag, err)); 
			else if (d.qid.path == Qroot)
				srv.default(msg);
			else if (d.qid.path != Qnew)
				srv.reply(ref Rmsg.Error(m.tag, "weird qid in open"));
			else if (mode == Sys->OREAD) 
				srv.reply(ref Rmsg.Error(m.tag, "cannot open for read only"));
			else { 
				f.open(mode, d.qid);
				addCopyOp(f.fid);
				srv.reply(ref Rmsg.Open(m.tag, d.qid, srv.iounit()));
			}
		}
		Write => {
			(f, err) := srv.canwrite(m);
			if (err != nil) 
				srv.reply(ref Rmsg.Error(m.tag, err)); 
			else if ((cp := fndCopyOpByFid(f.fid)) == nil) {
				srv.reply(ref Rmsg.Error(m.tag, "internal error"));
				sys->fprint(sys->fildes(2), "write without a copyop\n");
				raise "fatal:writeerror";
			}
			else if (cp.state == RUNNING)
				 srv.reply(ref Rmsg.Error(m.tag, "ongoing write"));
			else {
				dprint(string m.data);
				(n, args) := sys->tokenize(string m.data, " \n");
				err = setCopyArgs(cp, args);
				if (err != nil) {
					srv.reply(ref Rmsg.Error(m.tag, err));
					return;
				}
				else { 
					cp.mtag = m.tag;
					cp.reply = ref Rmsg.Write(m.tag, len m.data);
					if ((err = startCopyThread(cp)) != nil) {
						srv.reply(ref Rmsg.Error(m.tag, err));
						return;
					}
					# else copy started, we do not reply to block the write
				}
			}
		}
		Read => {
			(f, err) := srv.canread(m);
			if (err != nil)
				srv.reply(ref Rmsg.Error(m.tag, err)); 
			else if (f.path == Qroot) 
				srv.default(msg);
			else if ((cp := fndCopyOpByFid(f.fid)) == nil) {
				srv.reply(ref Rmsg.Error(m.tag, "internal error"));
				sys->fprint(sys->fildes(2), "read without a copyop\n");
				raise "fatal:readerror";
			}
			else {
				if (m.offset == big 0)
					f.data = array of byte sys->sprint("%bd", cp.bytecnt);
					# BUG:
					# reading bytescnt is not necessarily atomic
					# see BUG comment in function copyThread
				srv.reply(styxservers->readbytes(m, f.data));
			}
		}
		Flush => {
			srv.default(msg);
			if ((cp := fndCopyOpByTag(m.oldtag)) != nil)
				killCopyThread(cp, ABORT);
		}
		Clunk => {
			f := srv.clunk(m);
			if ((f != nil) && ((cp := fndCopyOpByFid(f.fid)) != nil)) {
				rmvCopyOp(cp);
			}
		}
		* => { srv.default(msg); }
	};
}

buildDir(name, uid, gid: string, perm: int, qid: big): Sys->Dir
{
	d := sys->zerodir;
	d.name = name;
	d.uid = uid;
	d.gid = gid;
	d.mode = perm;
	d.qid.path = qid;
	if (perm & Sys->DMDIR)
		d.qid.qtype = Sys->QTDIR;
	else 
		d.qid.qtype = Sys->QTFILE; 
	return(d);
}

serve(fd: ref sys->FD, rootdir, uid, gid: string, c: chan of int)
{
	pid := sys->pctl(Sys->FORKNS|Sys->NEWFD|Sys->NEWPGRP, list of {1,2,fd.fd});
	err := sys->chdir(rootdir);
	if (err) {
		sys->print("error changing working dir: %r\n");
		c <- = pid;
		exit;
	}
	
	styx->init();
	styxservers->init(styx);
	nametree->init();
	
	styxservers->traceset(debug);

	(filetree, filetreeop) := nametree->start();
	Qroot = cqid++; Qnew = cqid++;
	filetree.create(Qroot, buildDir(".", uid, gid, 8r777|Sys->DMDIR, Qroot));
	filetree.create(Qroot, buildDir("new", uid, gid, 8r777, Qnew));
	(tchan, srv) := Styxserver.new(fd, Navigator.new(filetreeop), Qroot);
	initCopyOps(); 
	initMntPnts();
	nfy = chan of ref CopyOpDesc;
	
	dprint("copy server started");
	dprint(sys->sprint("root dir is %s", rootdir));
	
	c <- = pid;

	while (1) {
		alt {
			tmsg := <- tchan =>
				handleTmsg(srv, filetree, tmsg); 			
			cp := <- nfy =>
				gcCopyOp(srv, cp);
		}
	}

}

printUsageAndExit()
{
	sys->print("usage: copydevice [-d] /dir\n"); 
	exit;
}


init(ctxt: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	str = load String String->PATH;

	args = tl args;

	debug = 0;
	
	if ((len args < 1) || (len args > 2))
		printUsageAndExit();
	
	if (len args == 2) {
		if (hd args != "-d") 
			printUsageAndExit();
		else
			debug = 1;
		args = tl args;
	}

	rootdir := hd args;
	if (rootdir[0] != '/')
		printUsageAndExit();

	(ok, d) := sys->stat(".");
	if (ok) {
		sys->fprint(sys->fildes(2), "could not stat current dir: %r\n");
		exit;
	}
	
	styx = load Styx Styx->PATH;
	styxservers = load Styxservers Styxservers->PATH;
	nametree = load Nametree Nametree->PATH;
	dtime = load Daytime Daytime->PATH;

	c := chan of int;
	spawn serve(sys->fildes(0), rootdir, d.uid, d.gid, c);
	<- c;
}
