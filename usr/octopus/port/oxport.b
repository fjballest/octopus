implement Oxport;

include "sys.m";
	sys: Sys;
	fprint, create, stat, sprint, QTDIR, pwrite, fwstat, OTRUNC, fildes, FD, ORCLOSE, Dir, 
	read, DMDIR, NEWPGRP, FORKNS,
	open, pctl, sleep, nulldir, fstat, pread,
	dial, remove, write, OREAD, OWRITE: import sys;
include "op.m";
	op: Op;
	OSTAT, ODATA, NOFD, OREMOVEC, OCREATE, OMORE, Tmsg, Rmsg, MAXDATA: import op;
include "draw.m";
include "arg.m";
	arg: Arg;
	usage: import arg;
include "names.m";
	names: Names;
	isprefix, basename, cleanname, rooted : import names;
include "error.m";
	err: Error;
	panic, checkload, stderr, error, kill: import err;
include "env.m";
	env: Env;
	getenv: import env;
include "netutil.m";
	util: Netutil;
	netmkaddr, authfd, Client: import util;
include "xproc.m";
	xproc: Xproc;
	Terminate, Shrink, Proc: import xproc;
include "io.m";
	io: Io;
	readfile: import io;
Oxport: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

debug:= 0;
uname, pname : string;
debuglatency:= 0;
xfspid := -1;

# To keep arg lists reasonable.
Fdsc:	type chan of (ref FD, chan of int);	# FD start channel
Fdc:	type chan of (int, chan of ref FD);	# FD channel
Fdec:	type chan of int;			# FD end channel.

# Because many Rgets may be sent for a single Tget
# the replies are handled everywhere as a list of ref Rmsg

topdir:	string;			# absolute path for exported dir
outc:	chan of list of ref Rmsg;	# to send replies to be sent to client.
fdsc:	Fdsc;			# fd start channel	(allocates fd)
fdc:	Fdc;			# fd lookup channel
fdec:	Fdec;			# fd end channel	(deallocates fd)

fds2text(fds: array of ref FD): string
{
	s := "";
	for(i := 0; i < len fds; i++)
		if(fds[i] != nil)
			s += sprint("%d:%d ", i, fds[i].fd);
	return s;
}

# Process keeping file descriptors open, during Tputs/Tgets with OMORE
# A word of caution about the protocol:
# Note that fds are a cache, to try to alert applications about gone clients.
# A Tput/Tget with an invalid fd would still work, and recreate (and return)
# a different fd. They are NOT fids.

fdproc()
{
	Incr: con 8;
	nfds := 0;
	fds := array[Incr] of ref FD;
	for(;;){
		alt {
		(fd, rc) := <- fdsc =>
			if(fd == nil || rc == nil)
				exit;
			for(i:= 0; i < len fds && fds[i] != nil; i++)
				;
			if(i == len fds){
				newfds := array[Incr + len fds] of ref FD;
				newfds[0:] = fds;
				fds = newfds;
			}
			fds[i] = fd; nfds++;
			rc <-= i;
			if(debug)
				fprint(stderr, "fds: %s\n", fds2text(fds));
			else if(nfds > 0 && (nfds%10) == 0)
				fprint(stderr, "oxport: more than %d fds\n", nfds);
		(i, rc) := <- fdc =>
			if(i >= 0 && i < len fds && fds[i] != nil)
				rc <-= fds[i];
			else
				rc <-= nil;
		i := <- fdec =>
			if(i >= 0 && i < len fds){
				fds[i] = nil; nfds--;
			}
			if(debug)
				fprint(stderr, "fds: %s\n", fds2text(fds));
		}
	}
}


serveput(m : ref Tmsg.Put): list of ref Rmsg
{
	fd : ref FD;
	mode := 8r664;
	if(m.mode&OSTAT)
		mode = m.stat.mode&8r777;
	m.mode &=(OSTAT|ODATA|OCREATE|OMORE|OREMOVEC);
	repfd := NOFD;
	isdir := 0;
	path := topdir + m.path;
	if((m.mode&OSTAT) && (m.stat.mode&DMDIR) != 0 && (m.stat.mode != ~0))
		isdir = 1;

	# 1. setup fd

	if(m.fd != NOFD){
		rc := chan of ref FD;
		fdc <-= (m.fd, rc);
		fd = <-rc;
		rc = nil;
		if(m.mode&OREMOVEC){
			if(fd != nil)
				fdec <-= m.fd;
			return list of {ref Rmsg.Error(m.tag, "put: remove on close not in first put")};
		}
		if(m.mode&OCREATE){	# create always releases the old fd
			if(fd != nil)
				fdec <-= m.fd;
			fd = nil;
			m.fd = NOFD;
		} else if(fd == nil)		# fd was lost. recreate.
			m.fd = NOFD;
		else if(m.mode&OMORE)	# keep fd valid
			repfd = m.fd;
		else			# last Tput for file.
			fdec <-= m.fd;	# Release fd. Won't close while we keep a ref.
	}
	if(m.fd == NOFD){
		# either fd was not set (first put) or it was lost (recovered link)
		# use path to setup fd.
		if(m.path == nil || m.path == "" || m.path[0] != '/')
			return list of {ref Rmsg.Error(m.tag, "put: bad op file name")};
		omode:= 0;
		if(m.mode&OREMOVEC){
			if((m.mode&OMORE) == 0)
				return list of {ref Rmsg.Error(m.tag, "put: " +
						"remove on close on single put: pointless")};
			omode |= ORCLOSE;
		}
		if(m.mode&OCREATE){
			if((m.mode&OSTAT) != 0 && isdir){
				mode |= DMDIR;
				fd = create(path, OREAD|omode, mode);
			} else {
				fd = open(path, OTRUNC|OWRITE|omode);
				if(fd == nil)
					fd = create(path, OWRITE|omode, mode);
			}
		} else if(isdir)
			fd = open(path, OREAD|omode);
		else
			fd = open(path, OWRITE|omode);
		if(fd == nil)
			return list of {ref Rmsg.Error(m.tag, sprint("put:  fd: %r"))};
		if((m.mode&OMORE) && !isdir){
			rc := chan of int;
			fdsc <-= (fd, rc);
			repfd = <- rc;
			rc = nil;
		}
	}

	# 2.  Data and Stat I/O. Errors close the fd used for further puts.

	cnt := 0;
	if((m.mode&ODATA) != 0 && !isdir){
		cnt = pwrite(fd, m.data, len m.data, m.offset);
		if(cnt < 0){
			if(repfd != NOFD)
				fdec <-= repfd;
			return list of {ref Rmsg.Error(m.tag, sprint("pwrite: %r"))};
		}
	}
	if(m.mode&OSTAT){
		d := nulldir;
		d.mode = m.stat.mode;
		d.name = m.stat.name;
		d.uid = m.stat.uid;
		d.gid = m.stat.gid;
		if(fwstat(fd, d) < 0){
			# Try again without chown/chgrp
			d.uid = nil;
			d.gid = nil;
			# If this is a create the mode was already set at
			# creation time; ignore errors on wstat because it
			# might not be allowed by devices, but create did work.
			if(fwstat(fd, d) < 0 && !(m.mode&OCREATE)){
				if(repfd != NOFD)
					fdec <-= repfd;
				return list of {ref Rmsg.Error(m.tag, sprint("wstat: %r"))};
			}
		}
	}
	(e, d) := fstat(fd);	# ouch! we must issue a Tstat to get the reply qid and mtime,
	if(e < 0){		# with appropriate values after any write made by us.
		if(repfd != NOFD)
			fdec <-= repfd;
		return list of {ref Rmsg.Error(m.tag, sprint("put: I'm finding nemo"))};
	}
	fd = nil;
	return list of {ref Rmsg.Put(m.tag, repfd, cnt, d.qid, d.mtime)};
}

app(l: list of ref Rmsg, r: ref Rmsg): list of ref Rmsg
{
	if(l == nil)
		return list of {r};
	else
		return hd l::app(tl l, r);
}

serveget(m : ref Tmsg.Get): list of ref Rmsg
{
	fd : ref FD;
	m.mode &=(OSTAT|ODATA|OMORE);
	repfd := NOFD;

	# 1. setup fd
	path := topdir + m.path;

	if(m.fd != NOFD){
		rc := chan of ref FD;
		fdc <-= (m.fd, rc);
		fd = <-rc;
		rc = nil;
		if(fd == nil)			# fd lost, recreate
			m.fd = NOFD;
		else if(m.mode&OMORE)	# keep fd valid
			repfd = m.fd;
		else
			fdec <-= m.fd;
	}
	if(m.fd == NOFD){
		# either fd was not set (first get) or it was lost (recovered link)
		# use path to setup fd.
		if(m.path == nil || m.path == "" || m.path[0] != '/')
			return list of {ref Rmsg.Error(m.tag, "bad Op file name")};
		fd = open(path, OREAD);
		# This may report a permission denied for -wx-wx-wx files
		# if this is OSTAT, we should try to send just OSTAT back, because we
		# could not open the file. Only for ODATA-only messages should we report an
		# error back.
		if(fd == nil){
			if((m.mode&OSTAT) == 0)
				return list of {ref Rmsg.Error(m.tag, sprint("%r"))};
			else
				m.mode = OSTAT;	# clear others
		}
		if(m.mode&OMORE){
			rc := chan of int;
			fdsc <-= (fd, rc);
			repfd = <-rc;
			rc = nil;
		}
	}
	d := nulldir;
	e: int;
	m.mode &= (ODATA|OSTAT);
	if(fd == nil)		# may happen for -wx files and OSTAT gets
		(e, d) = stat(path);
	else
		(e, d) = fstat(fd);
	if(e < 0){
		if(repfd != NOFD)
			fdec <-= repfd;
		return  list of {ref Rmsg.Error(m.tag, sprint("%r"))};
	}
	d.name = basename(path, nil);
	if(d.name == "")
		d.name = "/";
	if(m.mode == OSTAT)
		return list of {ref Rmsg.Get(m.tag, repfd, OSTAT, d, array [0] of byte)};

	# We must respond with up to m.nmsgs,
	# considering that m.nmsgs is infinite for directories.
	# The entire sequence of directory gets must be atomic.
	# OMORE must be sent back when there's more data
	# awating for further gets.
	if(m.count > MAXDATA)
		m.count = MAXDATA;
	repls: list of ref Rmsg;
	repls = nil;
	if((d.qid.qtype&QTDIR) != 0){
		if(repfd != NOFD)
			fdec <-= repfd;
		repfd = NOFD;
		data := readfile(fd);
		sent := 0;
		rest := len data;
		mode : int;
		do {
			nr := m.count;
			mode = m.mode;
			if(nr > rest)
				nr = rest;
			else
				mode |= OMORE;
			m.mode &= ~OSTAT;
			repls = app(repls, ref Rmsg.Get(m.tag, repfd, mode, d, data[sent:sent+nr]));
			sent += nr;
			rest -= nr;
		} while(mode&OMORE);
	} else {
		mode : int;
		do {
			data := array[m.count] of byte;
			nr := pread(fd, data, m.count, m.offset);
			if(nr < 0){
				if(repfd != NOFD)
					fdec <-= NOFD;
				repls = app(repls, ref Rmsg.Error(m.tag, sprint("%r")));
				break;
			}
			if(nr == 0){
				if(repfd != NOFD)
					fdec <-= NOFD;
				repls = app(repls, ref Rmsg.Get(m.tag, NOFD, m.mode, d, data[0:nr]));
				break;
			}
			m.offset += big nr;
			mode = m.mode;
			if(m.offset < d.length && nr > 0)
				mode |= OMORE;
			m.mode &= ~OSTAT;
			repls = app(repls, ref Rmsg.Get(m.tag, repfd, mode, d, data[0:nr]));
		} while(--m.nmsgs != 0 && (mode&OMORE));
	}
	return repls;
}

serve(t : ref Tmsg): list of ref Rmsg
{
	if(debuglatency > 0)
		sleep(debuglatency);
	if(topdir == "/")
		topdir = "";	# so that dir + path makes sense.
	pick m := t {
	Attach =>
		return list of {ref Rmsg.Error(m.tag, "already attached")};
	Flush =>
		panic("flush reached serve");
	Remove =>
		if(m.path == nil || m.path == "" || m.path[0] != '/')
			return list of {ref Rmsg.Error(m.tag, "bad Op file name")};
		path := topdir + m.path;
		if(remove(path) < 0)
			return list of {ref Rmsg.Error(m.tag, sprint("%r"))};
		return list of {ref Rmsg.Remove(m.tag)};
	Put =>
		return serveput(m);
	Get =>
		return serveget(m);

	}
	panic("serve bug");
	return nil;
}

flush(t: ref Tmsg): list of ref Rmsg
{
	r: ref Rmsg;
	pick tt := t {
	Flush =>
		r = ref Rmsg.Flush(t.tag);
	* =>
		r = ref Rmsg.Error(t.tag, "flushed");
	}
	return list of {r};
}

outproc(fd: ref FD)
{
	for(;;){
		rl := <- outc;
		if(rl == nil)
			break;
		for(; rl != nil; rl = tl rl){
			r := hd rl;
			if(debug)
				fprint(stderr, "<= %s\n", r.text());
			b := r.pack();
			nw := write(fd, b, len b);
			if(nw != len b){
				if(debug)
					fprint(stderr, "outproc: write error: %r\n");
				kill(xfspid, "kill");
				raise "fail: write error";
			}
		}
	}
}

getmsg(fd: ref FD) : (ref Tmsg, string)
{
	m := Tmsg.read(fd, 0);
	if(m == nil)
		return (nil, nil);
	pick mm := m {
	Readerror =>
		fprint(stderr, "oxport: read error: %s\n", mm.error);
		return (m,  "read: " + mm.error);
	}
	if(debug)
		fprint(stderr, "=> %s\n", m.text());
	return (m, nil);
}

xfs(fd : ref FD)
{
	xfspid = pctl(0, nil);
	attached := 0;
	(am, ae) := getmsg(fd);
	if(am == nil){
		fprint(stderr, "oxport: premature eof\n");
		return;
	}
	if(ae != nil){
		outc <-= nil;
		raise "fail:"+ ae;
	}
	pick mm := am {
	Attach =>
		uname = mm.uname;
		pname = mm.path;
		if(mm.uname == nil){
			outc <-= list of {ref Rmsg.Error(am.tag, "no uname")};
			raise "fail: attach";
		} else if(mm.path != "/"){
			outc <-= list of {ref Rmsg.Error(am.tag, "permission denied")};
			raise "fail: attach";
		} else {
			uname = mm.uname;
			pname = mm.path;
			outc <-= list of {ref Rmsg.Attach(am.tag)};
			attached = 1;
		}
	* =>
		outc <-= list of {ref Rmsg.Error(am.tag, "not attached")};
		raise "fail: attach";
	}
	fdsc = chan of (ref FD, chan of int);
	fdc = chan of (int, chan of ref FD);
	fdec = chan of int;
	spawn fdproc();
	xp := ref Proc[ref Tmsg, list of ref Rmsg];
	xp.serve = serve;
	xp.flush = flush;
	(xc, xfc) := xp.init();
	fc := chan of ref Tmsg;
	nreq := 0;
	while(attached){
		(m, e) := getmsg(fd);
		if(m == nil)
			break;
		if(e != nil){
			outc <-= nil;
			fdsc <-= (nil, nil);
			xc <-= (Terminate, nil, nil);
			raise "fail:"+ e;
		}
		pick mm := m {
		Flush =>
			xfc <-= (mm.oldtag, fc);
			<-fc;
			outc <-= list of {ref Rmsg.Flush(m.tag)};
		* =>
			xc <-= (m.tag, m, outc);
		}
		# collect idle xprocs from time to time.
		if((nreq++ % 50) == 0)
			xc <-= (Shrink, nil, nil);
	}
	if(debug)
		fprint(stderr, "oxport: eof\n");
	outc <-= nil;
	xc <-= (Terminate, nil, nil);
	fdsc <-= (nil, nil);
}

export(fd: ref FD)
{
	s := getenv("sysname");
	if(s == nil)
		s = "terminal";
	data := array of byte s;
	if(fprint(fd, "%08d\n", len data) < 0)
		error("export failed: %r");
	if(write(fd, data, len data) != len data)
		error("export failed: %r");
	if(debug){
		fprint(stderr, "%08d\n", len data);
		write(stderr, data, len data);
	}
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	err = load Error Error->PATH;
	err->init(sys);
	names = checkload(load Names Names->PATH, Names->PATH);
	op = checkload(load Op Op->PATH, Op->PATH);
	util = checkload(load Netutil Netutil->PATH, Netutil->PATH);
	io = checkload(load Io Io->PATH, Io->PATH);
	env = checkload(load Env Env->PATH, Env->PATH);
	arg = checkload(load Arg Arg->PATH, Arg->PATH);
	xproc = checkload(load Xproc Xproc->PATH, Xproc->PATH);
	arg->init(args);
	arg->setusage("oxport [-Ad] [-L ms] [-x addr] dir");
	calladdr: string;
	doauth := 1;
	while((opt := arg->opt()) != 0) {
		case opt{
		'A' =>
			doauth = 0;
		'L' =>
			debuglatency = int arg->earg();
		'd' =>
			debug = 1;
		'x' =>
			calladdr = arg->earg();
		* =>
			usage();
		}
	}
	args = arg->argv();
	if(len args != 1)
		usage();
	topdir = cleanname(hd args);
	if(topdir == "/")
		topdir = "";	# so that topdir + req.path always works.
	srvfd := fildes(0);
	if(calladdr != nil){
		# Only under "-x" do we call pctl(FORKNS,nil) to avoid deadlocks.
		# To export the PC ns we do NOT want the ns to be forked.
		# because we want to see mounts made after exporting the name space.
		# However, terminals exporting devices should export a frozen copy
		# of the ns that cannot deadlock with the files imported from the pc.
		pctl(FORKNS, nil);
		calladdr = netmkaddr(calladdr, "tcp", "16699");
		(rc, c) := dial(calladdr, nil);
		if(rc < 0)
			error(sprint("%s: %r\n", calladdr));
		if(doauth){
			(fd, e) := authfd(c.dfd, Client, nil, nil, calladdr);
			if(fd == nil)
				error("dial: " + e);
			srvfd = fd;
		} else
			srvfd = c.dfd;
		c.dfd = c.cfd = nil;
		export(srvfd);
	}
	op->init();
	outc = chan of list of ref Rmsg;
	spawn outproc(srvfd);
	xfs(srvfd);
}
