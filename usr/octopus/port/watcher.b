#
# Watchs out the registry for the octopus.
# 1. Old, and not refreshed entries are removed, and their Ofs processes killed.
# 2. New ofs entries are announced via plumb messages
# 3. Gone ofs entries are announced as gone via plumb messages

implement Watcher;

include "sys.m";
	sys: Sys;
	FD, fprint, sprint, remove, read, sleep, unmount,
	pctl, NEWPGRP, write, OWRITE, OREAD, dirread, open: import sys;
include "error.m";
	err: Error;
	stderr, checkload, panic, error, kill: import err;
include "arg.m";
	arg: Arg;
	usage: import arg;
include "registries.m";
	regs: Registries;
	Service, Registered, Attributes, Registry: import regs;
include "draw.m";
include "plumbmsg.m";
	plumbmsg: Plumbmsg;
	Msg: import plumbmsg;
include "daytime.m";
	daytime: Daytime;

Watcher: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

verbose := 0;
debug := 0;
terms: list of (string, int);

dump()
{
	s := "terms: ";
	for(l := terms; l != nil; l = tl l){
		(t, p) := hd l;
		s += sprint("%s:%d ", t, p);
	}
	fprint(stderr, "%s\n", s);
}

newterm(name: string)
{
	text := "arrived: " + "/terms/" + name + "\n";
	data:= array of byte text;
	if(verbose)
		fprint(stderr, "watcher: %s\n", text);
	m := ref Msg("ofs", "", "/", "text", nil, data);
	m.send();
	fd := open("/mnt/ports/post", OWRITE);
	if(fd != nil)
		write(fd, data, len data);
}

goneterm(name: string, pid: int)
{
	text := "gone: " + "/terms/" + name + "\n";
	data:= array of byte text;
	if(verbose)
		fprint(stderr, "watcher: %s\n", text);
	m := ref Msg("ofs", "", "/", "text", nil, data);
	m.send();
	kill(pid, "killgrp");
	unmount(nil, "/terms/" + name);
	fd := open("/mnt/ports/post", OWRITE);
	if(fd != nil)
		write(fd, data, len data);
}

scan(reg: ref Registry)
{
	attrs := list of {("name", "ofs")};
	(svcs, e) := reg.find(attrs);
	if(e != nil){
		fprint(stderr, "watcher: scan: %r");
		return;
	}

	nl : list of (string, int);
	for(l := terms; l != nil; l = tl l){
		(tname, pid) := hd l;
		for(sl := svcs; sl != nil; sl = tl sl){
			s := hd sl;
			if(tname == s.attrs.get("sys"))
				break;
		}
		if(sl == nil)
			goneterm(tname, int pid);
		else
			nl = (tname, pid)::nl;
	}
	terms = nl;

	for(; svcs != nil; svcs = tl svcs){
		s := hd svcs;
		sname := s.attrs.get("sys");
		pid := s.attrs.get("pid");
		for(l = terms; l != nil; l = tl l){
			(tname, nil) := hd l;
			if(sname == tname)
				break;
		}
		if(l == nil && pid != nil){
			newterm(sname);
			terms = (sname, int pid)::terms;
		}
	}
}

watcher(cfd: ref FD, reg: ref Registry)
{
	msg := array[30] of byte;
	scan(reg);
	for(;;){
		if(debug)
			dump();
		nr := read(cfd, msg, len msg); # ignore msg; wait for changes
		if(nr <= 0)
			panic("watcher: event eof");
		scan(reg);
	}
}


init(nil: ref Draw->Context, args: list of string)
{
	regdir := "/mnt/registry";
	sys = load Sys Sys->PATH;
	err = load Error Error->PATH;
	err->init(sys);
	regs = checkload(load Registries Registries->PATH, Registries->PATH);
	regs->init();
	plumbmsg = checkload(load Plumbmsg Plumbmsg->PATH, Plumbmsg->PATH);
	if(plumbmsg->init(1, nil, 0) < 0)
		error(sprint("plumbmsg: %r"));
	daytime = checkload(load Daytime Daytime->PATH, Daytime->PATH);
	arg = checkload(load Arg Arg->PATH, Arg->PATH);
	arg->init(args);
	arg->setusage("watcher [-dv] [-r regdir]");
	while((opt := arg->opt()) != 0) {
		case opt{
		'd' =>
			debug = verbose = 1;
		'i' =>
			arg->earg();
			# -i ival not used.
			fprint(stderr, "watcher: update your scripts. called with old flag -i\n");
		't' =>
			arg->earg();
			# -t tmout is not used. kept for a while
			fprint(stderr, "watcher: update your scripts. called with old flag -t\n");
		'r' =>
			regdir = arg->earg();
		'v' =>
			verbose = 1;
		* =>
			usage();
		}
	}
	args = arg->argv();
	if(len args != 0)
		usage();
	reg := Registry.new(regdir);
	if(reg == nil)
		error(sprint("registry: %r"));
	efd := open(regdir + "/event", OREAD);	# open here to abort in parent.
	if(efd == nil)
		error(sprint("no registr event: %r (old inferno?)"));
	pctl(NEWPGRP, nil);
	spawn watcher(efd, reg);
}
