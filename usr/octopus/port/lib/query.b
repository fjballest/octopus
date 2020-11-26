#
# Quering paths for network gadgets
#
implement Query;
include "sys.m";
	sys: Sys;
	fildes, write, open, read, fprint, MBEFORE, OREAD,
	print, bind, MREPL, sprint, MCREATE, FD: import sys;
include "draw.m";
include "registries.m";
	regs: Registries;
	Service, Registered, Attributes, Registry: import regs;
include "error.m";
	err: Error;
	checkload, stderr, error, kill: import err;
include "arg.m";
	arg: Arg;
	usage: import arg;
include "env.m";
	env: Env;
	getenv: import env;
include "io.m";
	io: Io;
	readdev: import io;
include "query.m";

userloc(): string
{
	l := readdev("/mnt/who/" + getenv("user") + "/where", nil);
	if(l == nil)
		l = getenv("location");
	return l;
}

expand(n, v: string): string
{
	if(n == "loc"){
		if(v == "$user")
			return userloc();
		if(v == "$term")
			return getenv("location");
	}
	if(n == "arch" && v == "$term")
			return getenv("emuhost") + getenv("cputype");
	return v;
}

lookup(args: list of string) : (list of string, string)
{
	if(sys == nil){
		sys = load Sys Sys->PATH;
		err = load Error Error->PATH;
		err->init(sys);
		io = checkload(load Io Io->PATH, Io->PATH);
		regs = checkload(load Registries Registries->PATH, Registries->PATH);
		regs->init();
		env = checkload(load Env Env->PATH, Env->PATH);
	}
	nargs := len args;
	if(nargs == 0 || (nargs%2) != 0)
		return(nil, "odd lookup arguments");
	reg := Registry.new(nil);
	if(reg == nil)
		return (nil, sprint("can't locate registry: %r"));
	l : list of (string, string);
	while(len args > 0){
		# could add $min as value: collect name appart, and later,
		# after reg.find(), put first the entry with min. value for name
		(name, val) := (hd args, expand(hd args, hd tl args));
		l = (name, val) :: l;
		args = tl args; args = tl args;
	}
	(svcs, e) := reg.find(l);
	if(e != nil)
		return (nil, sprint("query: %s\n", e));
	paths: list of string;
	while(svcs != nil){
		s := hd svcs;
		svcs = tl svcs;
		path := s.attrs.get("path");
		if(path == nil)
			fprint(stderr, "no path for svc\n");
		else
			paths = path :: paths;
	}
	return (paths, nil);
}

init(nil: ref Draw->Context, args: list of string)
{
	mnt: string;
	sys = load Sys Sys->PATH;
	err = load Error Error->PATH;
	err->init(sys);
	io = checkload(load Io Io->PATH, Io->PATH);
	regs = checkload(load Registries Registries->PATH, Registries->PATH);
	regs->init();
	arg = checkload(load Arg Arg->PATH, Arg->PATH);
	arg->init(args);
	arg->setusage("query [-m mnt] [-u mnt] attr val...");
		env = checkload(load Env Env->PATH, Env->PATH);
	union := 0;
	while((opt := arg->opt()) != 0) {
		case opt {
		'u' =>
			mnt = arg->earg();
			union = 1;
		'm' =>
			mnt = arg->earg();
		* =>
			usage();
		}
	}
	(paths, e) := lookup(arg->argv());
	if(e != nil)
		error(e);
	if(len paths == 0)
		error("resource not found");
	if(mnt == nil)
		for(; paths != nil; paths = tl paths)
			print("%s\n", hd paths);
	else {
		if(bind(hd paths, mnt, MREPL|MCREATE) < 0)
			error(sprint("query: bind: %r"));
		if(union){
			for(paths = tl paths; paths != nil; paths = tl paths)
				if(bind(hd paths, mnt, MBEFORE|MCREATE) < 0)
					error(sprint("query: bind: %r"));
		}
	}
}
