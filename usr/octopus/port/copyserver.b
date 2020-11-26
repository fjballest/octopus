implement CopyServer;

include "sys.m";
include "draw.m";
include "string.m"; 
include "styx.m";
include "styxservers.m";
include "sh.m";

CopyServer: module
{ 
  init: fn(ctxt: ref Draw->Context, argv: list of string);
};

sys: Sys;
str: String;
styx: Styx;
styxservers: Styxservers;
nametree: Nametree;
sh: Sh;

Styxserver, Navigator: import styxservers;
Tree: import nametree;
Tmsg, Rmsg: import styx;

SRCMNT: con "cpsrv_src";	# dirname prefix for temp source mount
DSTMNT: con "cpsrv_dst";	# dirname prefix for temp dest mount

RUNNING, EOF, DONE, 
RWERR, KILL, ABORT: con iota;	# state codes

CopyOpDesc: adt {
	# request arguments
	srcmntopt: string;	# source mount option
	srcaddr: string;	# source dial address
	srcfname: string;	# source file pathname
	srcoff: big;		# source read offset
	dstmntopt: string;	# dest mount option
	dstaddr: string;	# dest dial address
	dstfname: string; 	# dest file pathname
	dstoff: big;		# dest write offset
	nofbytes: big;		# nof bytes to copy from source to dest
	iounit: int;		# data buffer size to use for copying
	delay: int;		# artificial delay between r/w ops
	ctlfname: string;	# name of control file for this copy op
	# additional state
	state: int;		# current state of copy op
	bytecnt: big;		# nof bytes copied so far
	srcmntdir: string; 	# source mount dir
	srcfd: ref sys->FD;	# source file descriptor for reading
	dstmntdir: string;	# dest mount dir
	dstfd: ref sys->FD;	# dest file descriptor for writing
	qid: big;		# qid of the copy op control file in the server tree
	mtag: int;		# tag of the write request that started the copy op 
	reply: ref Rmsg;	# reply message to this request, for normal completion	
};

# BUG:
# the r/w synchronization for the bytescopied field 
# between the copy thread and the main server thread is dirty
# see BUG comments in routines handleTmsg and copyThread

cqid := big 0;			# seed for generating unique qids for the server file tree
Qroot, Qctrl: big;		# root and control file qids
nfy: chan of ref CopyOpDesc;	# notification copy threads -> main server thread
cpopsl: list of ref CopyOpDesc; # list of ongoing copy ops

debug: int;			# print msgs sent/received and other state info

# aux routines

dprint(msg: string)
{
	if(debug)
		sys->fprint(sys->fildes(2), "%s\n", msg);
}

buildDir(name: string, perm: int, qid: big): Sys->Dir
{
	d := sys->zerodir;
	d.name = name; 
	d.qid.path = qid;
	d.uid = "*"; 
	d.gid = "*";
	if(perm & Sys->DMDIR)
		d.qid.qtype = Sys->QTDIR;
	else 
		d.qid.qtype = Sys->QTFILE; 
	d.mode = perm;
	return(d);
}


# copy op management stuff; simple and non-optimized

printCopyOps()
{
	s := "ongoing copy ops: ";
	for(cl := cpopsl; cl != nil; cl = tl cl) 
		s = s + sys->sprint("%s ",(hd cl).ctlfname);
	s = s + "~";
	dprint(s);
}

initCopyOps()
{
	cpopsl = nil;
}

addCopyOp(cpop: ref CopyOpDesc)
{
	cpopsl = cpop :: cpopsl;
	printCopyOps();
}

rmvCopyOp(cpop: ref CopyOpDesc)
{
	cpopslnew: list of ref CopyOpDesc;

	cpopslnew = nil;
	for(cl := cpopsl; cl != nil; cl = tl cl)
		if(hd cl != cpop)
			cpopslnew = hd cl :: cpopslnew;
	cpopsl = cpopslnew;
	printCopyOps();
}

fndCopyOpByName(ctlfname: string): int
{
	for(cl := cpopsl; cl != nil; cl = tl cl)
		if((hd cl).ctlfname == ctlfname)
			return(1);
	return(0);
}

fndCopyOpByQid(qid: big): ref CopyOpDesc
{
	for(cl := cpopsl; cl != nil; cl = tl cl)
		if((hd cl).qid == qid)
			return(hd cl);
	return(nil); 
}

fndCopyOpByTag(mtag: int): ref CopyOpDesc
{
	for(cl := cpopsl; cl != nil; cl = tl cl)
		if((hd cl).mtag == mtag)
			return(hd cl);
	return(nil); 
}


# cmd execution via shell

runcmd(ctxt: ref Draw->Context, cmdline: string): string
{
	sh = load Sh Sh->PATH;
	if(sh == nil)
		return(sys->sprint("could not load Sh module: %r"));

	(n, args) := sys->tokenize(cmdline, " \t\n");
	if(n == 0)
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
	} while(!str->prefix(pidstr, waitstr));

	(res, d) := sys->fstat(fds[0]);
	if(d.length == big 0) { return(nil); } 

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


# mount and unmount stuff; for convenience implemented using shell commands

unmount(opt, mnt: string)
{
	if(opt != nil) {
		runcmd(nil, "unmount "+mnt);
		runcmd(nil, "rm "+mnt);
	}
}


mount_open(mntopt, addr, mntdir, fname: string, off: big, mode : int): (string, ref sys->FD)
{
	fpath := fname;

	if(fpath[0] != '/')
		fpath = "/" + fpath;

	if(mntopt != nil) {

		err := runcmd(nil, "mkdir " + mntdir);
		if(err != nil)
			return((err, nil));

		authopt := "";
		if(str->in('A', mntopt))
			authopt = "-A";

		if(str->in('o', mntopt))
			err = runcmd(nil, "o/ofs" + " -m " + mntdir + " " + authopt + " " + addr + " /");
		else if(str->in('s', mntopt))
			err = runcmd(nil, "mount" + " " + authopt + " " + addr + " " + mntdir);
		else {
			sys->fprint(sys->fildes(2), "copy server fatal: illegal option: %s", mntopt);
			raise "fatal:mntopt";
		}

		if(err != nil) {
			runcmd(nil, "rm " + mntdir);
			return((err, nil));
		}
		
		fpath = mntdir + fpath;

	}

	fd: ref sys->FD;
	if(mode == sys->OREAD)
		fd = sys->open(fpath, mode);
	else if(mode == sys->OWRITE)
		fd = sys->create(fpath, mode, 8r777);
		#BUG:
		# ownership and access rights when creating a file?
	
	if(fd == nil) {
		err := sys->sprint("could not open %s: %r", fname);
		unmount(mntopt, mntdir);
		return ((err, nil));
	}

	sys->seek(fd, off, Sys->SEEKSTART);

	return((nil, fd));
}


# cmd parsing stuff

isValidMntOption(opt: string): int
{
	return ((opt == "-s") || (opt == "-sA") | 
	        (opt == "-o") || (opt == "-oA"));
}

isValidInt(num: string): (int, int)
{
	(i, s) := str->toint(num, 10);
	return(((s == nil) && (i >= 0), i));
} 

isValidBig(num: string): (int, big)
{
	(b, s) := str->tobig(num, 10);
	return(((s == nil) && (b >= big 0), b));
} 

parseFileSpec(cmdlist: list of string): (string, string, string, string, big, list of string)
{
	if(cmdlist == nil)
		return (("no file name", nil, nil, nil, big 0, nil));
	fname := hd cmdlist; cmdlist = tl cmdlist;
	opt := string nil;
	addr := string nil;
 
	if(fname[0] == '-') {
		opt = fname;
		if(!isValidMntOption(opt))
			return (("invalid mount option", nil, nil, nil, big 0, nil));
		
		if(cmdlist == nil)
			return (("no dial address", nil, nil, nil, big 0, nil));
		addr = hd cmdlist; cmdlist = tl cmdlist;
		
		if(cmdlist == nil)
			return (("no file name", nil, nil, nil, big 0, nil));
		fname = hd cmdlist; cmdlist = tl cmdlist;
	}	
	
	if(cmdlist == nil)
		return (("no offset", nil, nil, nil, big 0, nil));

	(ok, off) := isValidBig(hd cmdlist); cmdlist = tl cmdlist;
	if(!ok)
		return (("invalid offset", nil, nil, nil, big 0, nil));

	return((nil, opt, addr, fname, off, cmdlist)); 
}

parseCmd(cmdline: string): (string, ref CopyOpDesc)
{ 
	dprint(sys->sprint("request: %s", cmdline));

	(n, cmdlist) := sys->tokenize(cmdline, " \n"); 
	
	if(cmdlist == nil)
		return (("empty cmd string", nil));
	
	cmd := hd cmdlist; cmdlist = tl cmdlist;
	if(cmd != "copy")
		return (("copy expected", nil));

	cpop := ref CopyOpDesc(nil, nil, nil, big 0, nil, nil, nil, big 0, big 0, 0, 0, nil,
	                       0, big 0, nil, nil, nil, nil, big 0, 0, nil);

	err: string;

	(err, cpop.srcmntopt, cpop.srcaddr, cpop.srcfname, cpop.srcoff, cmdlist) = parseFileSpec(cmdlist);
	if(err != nil)
		return (("source: " + err, nil));

	(err, cpop.dstmntopt, cpop.dstaddr, cpop.dstfname, cpop.dstoff, cmdlist) = parseFileSpec(cmdlist);
	if(err != nil)
		return (("dest: " + err, nil));
	
	if(len cmdlist != 4)
		return (("nof bytes, iounit, delay and ctlfname expected", nil));

	ok: int;

	(ok, cpop.nofbytes) = isValidBig(hd cmdlist); cmdlist = tl cmdlist;
	if(!ok)
		return (("invalid nofbytes", nil));

	(ok, cpop.iounit) = isValidInt(hd cmdlist); cmdlist = tl cmdlist;
	if(!ok)
		return (("invalid iounit", nil));

	(ok, cpop.delay) = isValidInt(hd cmdlist); cmdlist = tl cmdlist;
	if(!ok)
		return (("invalid delay", nil));

	cpop.ctlfname = hd cmdlist; cmdlist = tl cmdlist;

	return ((nil, cpop)); 
}


# copy thread stuff

startCopyThread(filetree: ref Tree, msg: ref Tmsg.Write): string
{
	(err, cpop) := parseCmd(string msg.data);
	
	if(err != nil) 
		return(err); 

	if((cpop.ctlfname == "ctl") || fndCopyOpByName(cpop.ctlfname))
		return("ctl file name already in use");

	cpop.srcmntdir = SRCMNT + "_" + cpop.ctlfname;
	(err, cpop.srcfd) = mount_open(cpop.srcmntopt, cpop.srcaddr, cpop.srcmntdir, 
	                               cpop.srcfname, cpop.srcoff, sys->OREAD);
	if(err != nil)
		return(err);

	cpop.dstmntdir = DSTMNT + "_" + cpop.ctlfname;
	(err, cpop.dstfd) = mount_open(cpop.dstmntopt, cpop.dstaddr, cpop.dstmntdir, 
	                               cpop.dstfname, cpop.dstoff, sys->OWRITE);
	if(err != nil) {
		unmount(cpop.srcmntopt, cpop.srcmntdir); 
		return(err);
	}
	
	cpop.state = RUNNING;
	cpop.bytecnt = big 0;
	cpop.qid = cqid++;
	cpop.mtag = msg.tag;
	cpop.reply = ref Rmsg.Write(msg.tag, len msg.data);

	filetree.create(Qroot, buildDir(cpop.ctlfname, 8r666, cpop.qid));
	#BUG:
	# ownership and access rights when creating a control file?
	addCopyOp(cpop);

	spawn copyThread(cpop);

	return(nil);
}

copyThread(cpop: ref CopyOpDesc)
{
	cnt := big 0; 
	data := array [cpop.iounit] of byte;
	
	dprint(sys->sprint("copyThread started: %s", cpop.ctlfname));
  
	while(cpop.state == RUNNING) {
		rcnt := len data;
		if((cpop.nofbytes > big 0) && (big rcnt > cpop.nofbytes - cnt)) 
				rcnt = int (cpop.nofbytes - cnt); 
		
		n1 := sys->read(cpop.srcfd, data, rcnt);
		if(n1 < 0) {
			cpop.reply = ref Rmsg.Error(cpop.mtag, sys->sprint("read error: %r"));
			cpop.state = RWERR;
			break;
		}
		else if(n1 == 0) {
			cpop.state = EOF;
			break;
		}
		
		n2:= sys->write(cpop.dstfd, data, n1);
		if(n2 != n1) {
			cpop.reply = ref Rmsg.Error(cpop.mtag, sys->sprint("write error: %r")); 
			cpop.state = RWERR;
			break;
		}
		
		cnt = cnt + big n1;
		cpop.bytecnt = cnt;

		# BUG: 
		# we change the value of bytescopied in "a single shot"
		# however, this does not guarantee read atomicity
		# so the main server thread may read invalid data
		# see BUG comment in function handleTMsg

		if(cnt == cpop.nofbytes) {
			cpop.state = DONE;
			break;
		}
		 
		sys->sleep(cpop.delay);
	}
	
	if(cpop.state == KILL)
		cpop.reply = ref Rmsg.Error(cpop.mtag, sys->sprint("killed after %bd bytes", cnt));
	nfy <- = cpop; # termination signal to main server thread

	dprint(sys->sprint("copyThread stopped: %s", cpop.ctlfname));
}

gcCopyOp(srv: ref Styxserver, filetree: ref Tree, cpop: ref CopyOpDesc)
{
	termcodes := array [ABORT+1] of {"RUNNING", "EOF", "DONE", "RWERRROR", "KILLED", "ABORTED"}; 
	dprint(sys->sprint("term signal from %s: %s", cpop.ctlfname, termcodes[cpop.state]));
	
	unmount(cpop.srcmntopt, cpop.srcmntdir); 
	unmount(cpop.dstmntopt, cpop.dstmntdir);
	
	filetree.remove(cpop.qid);
	rmvCopyOp(cpop);

	# send reply msg to unblock client
	if(cpop.state != ABORT)
		srv.reply(cpop.reply);
} 

killCopyThread(cpop: ref CopyOpDesc, cmd: int)
{
	cpop.state = cmd;  # force copy thread to terminate, if not done yet
} 


killAllCopyThreads(srv: ref Styxserver, filetree: ref Tree, cmd: int)
{
	for(cl := cpopsl; cl != nil; cl = tl cl)
		killCopyThread(hd cl, cmd);
		
	while(cpopsl != nil) {
		cpop := <- nfy;
		gcCopyOp(srv, filetree, cpop);
	}
		
}


# main server thread stuff

handleTmsg(srv: ref Styxserver, filetree: ref Tree, msg: ref Tmsg)
{
	if(msg == nil) {
		killAllCopyThreads(srv, filetree, ABORT);
		dprint("stopping copy server");
		srv.default(msg);   # kills this process
		sys->fprint(sys->fildes(2), "copy server fatal: should be dead at this point");
		raise "fatal:noterm";
	}
	pick m := msg {
		Open => {
			fid := srv.open(m);
			if(fid != nil) {
				if((fid.path != Qctrl) && (fid.path != Qroot) && 
				   ((cpop:=fndCopyOpByQid(fid.path)) != nil))
					# cache for subsequent reads on this fid
					fid.data = array of byte sys->sprint("%bd",cpop.bytecnt);
					# BUG:
					# reading bytescopied is not necessarily atomic
					# see BUG comment in function copyThread
			}
		}
		Write => {
			(fid, err) := srv.canwrite(m);
			if(err != nil) 
				srv.reply(ref Rmsg.Error(m.tag, err)); 
			else if(fid.path == Qctrl) {
				err = startCopyThread(filetree, m); 
				if(err != nil)
					srv.reply(ref Rmsg.Error(m.tag, err));
				# if all went well, we do not reply to block the client
			}
			else {
				(n,cmd) := sys->tokenize(string m.data, " \n");
              			if((n != 1) || (hd cmd != "kill"))
					srv.reply(ref Rmsg.Error(m.tag,"usage: kill")); 
				else {
					if((cpop:=fndCopyOpByQid(fid.path)) != nil)
						killCopyThread(cpop, KILL);
					srv.reply(ref Rmsg.Write(m.tag, len m.data));
					# killing a terminated copy op succeeds as well
				} 
			}
		}
		Read => {
			(fid, err) := srv.canread(m);
			if(err != nil)
				srv.reply(ref Rmsg.Error(m.tag, err)); 
			else if((fid.path == Qctrl) || (fid.path == Qroot)) 
				srv.default(msg);
			else 
				srv.reply(styxservers->readbytes(m, fid.data));
		}
		Flush => {
			srv.default(msg);
			if((cpop:=fndCopyOpByTag(m.oldtag)) != nil)
				killCopyThread(cpop, ABORT);
		}
		* => { srv.default(msg); }
	};
}

serve(fd: ref sys->FD, c: chan of int)
{
	pid := sys->pctl(Sys->FORKNS|Sys->NEWFD|Sys->NEWPGRP, list of {1,2,fd.fd});
	
	styx->init();
	styxservers->init(styx);
	nametree->init();

	styxservers->traceset(debug);

	Qroot = cqid++;
	Qctrl  = cqid++;

	(filetree, filetreeop) := nametree->start();
	filetree.create(Qroot, buildDir(".", 8r555|Sys->DMDIR, Qroot));
	filetree.create(Qroot, buildDir("ctl", 8r222, Qctrl));

	(tchan, srv) := Styxserver.new(fd, Navigator.new(filetreeop), Qroot);
  
	initCopyOps(); 
	
	nfy = chan of ref CopyOpDesc;

	dprint("copy server started");

	c <- = pid;

	while(1) {
		alt {
			tmsg := <- tchan =>
				handleTmsg(srv, filetree, tmsg); 			
			cpop := <- nfy =>
				gcCopyOp(srv, filetree, cpop);
		}
	}

}


init(nil: ref Draw->Context, args: list of string)
{
	dirname: string; ok: int;
	
	sys = load Sys Sys->PATH;
	str = load String String->PATH;

	if((len args < 2) || (len args > 3)) {
		sys->print("usage: copyserver [-d] mnt\n"); 
		exit;
	} 
	
	if(len args == 2) {
		debug = 0;
		dirname = hd tl args;
	}
	else if(hd tl args == "-d") { 
		debug = 1; 
		dirname = hd tl tl args;
	}
	else {
		sys->print("usage: copyserver [-d] mnt\n"); 
		exit; 
	}
	
	styx = load Styx Styx->PATH;
	styxservers = load Styxservers Styxservers->PATH;
	nametree = load Nametree Nametree->PATH;

	fds := array[2] of ref Sys->FD;
	sys->pipe(fds);
	c := chan of int;

	spawn serve(fds[0], c);
	<- c;
	fds[0] = nil;

	res := sys->mount(fds[1], nil, dirname, sys->MREPL, nil);
	if(res == -1) {
		sys->print("could not mount: %r\n"); 
		exit;
	} 
	
	sys->print("server mounted on %s\n", dirname);  
	fds[1] = nil;
}
