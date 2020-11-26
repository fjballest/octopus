implement Camera;
include "sys.m";
	sys: Sys;
	Dir, pctl, NEWPGRP, DMDIR, open, OREAD, FD, OWRITE, ORCLOSE, FORKFD,
	ORDWR, FORKNS, NEWFD, MREPL, MBEFORE, MAFTER, MCREATE, pipe, mount,
	print, fprint, sprint, create, pwrite, read, QTDIR, QTFILE, fildes, Qid: import sys;
include "draw.m";
include "styx.m";
	styx: Styx;
	Rmsg, Tmsg, NOFID: import styx;
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
include "mcamera.m";
	cameracmd: Mcamera;
	takejpg:	import cameracmd;


Camera: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

Qroot, Qctl: con big iota;
debug : int;
user: string;
argv0 := "camera";

image: array of byte;
imagesize: int;


fupdate(oldd: ref Dir, length: int): Dir
{
	d := sys->zerodir;
	d.name = oldd.name;
	d.atime =  now();
	d.mtime =  now();	
	d.uid = oldd.uid;
	d.gid = oldd.gid;
	d.qid.path = oldd.qid.path;
	d.qid.qtype = oldd.qid.qtype;
	d.qid.vers = oldd.qid.vers + 1;
	d.mode = oldd.mode;
	d.length = big length;
	return d;
}


newdir(name: string, perm: int, qid: big): Dir
{
	d := sys->zerodir;
	d.name = name;
	d.uid = user;
	d.gid = user;
	d.atime =  now();
	d.mtime =  now();	
	d.qid.path = qid;
	if(perm & DMDIR)
		d.qid.qtype = QTDIR;
	else
		d.qid.qtype = QTFILE;
	d.mode = perm;
	return d;
}




fsreq(srv: ref Styxserver, tree: ref Tree, req: ref Tmsg) : ref Rmsg
{
	pick m := req {
	Create =>
		return ref Rmsg.Error(m.tag, "creation is forbidden");


	Remove =>
		return ref Rmsg.Error(m.tag, "removing is forbidden");


	Open =>
		if (debug) 
			fprint(sys->fildes(2),"open: m.fid: %d \n" , m.fid);
		(fid, nil, d, e) := srv.canopen(m);
		if(e != nil)
			return ref Rmsg.Error(m.tag, e);
		if(fid.uname != user) 
			return ref Rmsg.Error(m.tag, "permission denied");
		if(fid.qtype&QTDIR)
			return nil;
		if(fid.path  !=  Qctl)
			return ref Rmsg.Error(m.tag, "unknown file");
		fid.open(m.mode, d.qid);
		return ref Rmsg.Open(m.tag, d.qid, srv.iounit());


	Read =>
		if(debug) 
			fprint(sys->fildes(2),
			"read: m.fid: %d m.offset: %bd, m.count: %d srv.msize: %d srv.iounit: %d \n" , 
			m.fid, m.offset, m.count, srv.msize, srv.iounit());
		(fid, e) := srv.canread(m);
		if(e != nil)
			return ref Rmsg.Error(m.tag, e);
		if(fid.qtype&QTDIR)
			return nil; # this means: "return the standar response".
		if(fid.path  !=  Qctl) 
			return ref Rmsg.Error(m.tag, "unknown file");	
		if(image == nil){ 	# empty file
			r := ref Rmsg.Read(m.tag, nil);
			r.data = array[0] of byte; 
			return r;
		}
		return readbytes(m, image[0:imagesize-1]);	

	
	Write =>
		if(debug) 
			fprint(sys->fildes(2),
			"write: m.fid: %d m.offset: %bd, m.count: %d srv.msize: %d\n" , 
			m.fid, m.offset, len m.data, srv.msize);
		(fid, e) :=  srv.canwrite(m);
		if(e != nil)
			return ref Rmsg.Error(m.tag, e);
		if((fid.qtype&QTDIR) || (fid.path != Qctl))
			return ref Rmsg.Error(m.tag, "permission denied");
		cmd := string m.data;
		if(cmd == "take" || cmd == "take\n"){
			(image,imagesize) = takejpg();
			if(image == nil || imagesize == 0)
				return ref Rmsg.Error(m.tag, "cannot get a picture");
			# update metadata to avoid problems with the cache
			(d,errstr) := srv.t.stat(fid.path);
			if(d == nil)
				return ref Rmsg.Error(m.tag, "cannot modify metadata:" + errstr);
			tree.wstat(d.qid.path, fupdate(d, imagesize));
			return ref Rmsg.Write(m.tag, len m.data);
		}
		return ref Rmsg.Error(m.tag, "incorrect command");


	Clunk =>
		if(debug) 
			fprint(sys->fildes(2),"clunk: m.fid: %d \n" , m.fid);
		fid := srv.getfid(m.fid);
		if(fid == nil)
			return ref Rmsg.Error(m.tag, "bad fid");
		srv.delfid(fid);
		return ref Rmsg.Clunk(m.tag);


	Wstat =>
		if(debug) 
			fprint(sys->fildes(2),"wstat: m.fid: %d \n" , m.fid);
		return ref Rmsg.Wstat(m.tag);


	* =>
		return nil;
	}
}




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
	tree.create(Qroot, newdir("ctl", 8r600, Qctl)); # exclusive open
	for(;;) {
		req := <-reqc;
		if(req == nil)
			break;
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
	arg->setusage("camera [-m mnt]");
	cameracmd = checkload(load Mcamera Mcamera->PATH, Mcamera->PATH);
	cameracmd->init();
	mnt: string;
	image = nil;
	imagesize = 0;
	debug = 0;
	flag := MREPL|MCREATE;
	while((opt := arg->opt()) != 0) {
		case opt{
		'm' =>
			mnt = arg->earg();
		'd' =>
			debug = 1;
		* =>
			usage();
		}
	}

	if(debug) 
		fprint(sys->fildes(2),"testing 0011\n");

	if(mnt == nil){
		fs(nil, fildes(0));
	}else {
		pfds := array[2] of ref FD;
		if(pipe(pfds) < 0)
			error(sprint("camera: pipe: %r"));
		pidc := chan of int;
		spawn fs(pidc, pfds[0]);
		<-pidc;
		if(mount(pfds[1], nil, mnt, flag, nil) < 0)
			error(sprint("camera: mount (mnt: %s): %r", mnt));
		pfds[0] = nil;
	}
}
