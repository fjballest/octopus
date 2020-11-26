#
# Tools for registering and implementing
# our network-gadgets
#
implement Netget;
include "sys.m";
	sys: Sys;
	fildes, write, open, read, pctl, fprint, sleep, tokenize, sprint, OREAD, FD: import sys;
include "draw.m";
include "registries.m";
	regs: Registries;
	Service, Registered, Attributes, Registry: import regs;
include "env.m";
	env: Env;
	getenv: import env;
include "error.m";
	err: Error;
	stderr, error, kill: import err;
include "arg.m";
	arg: Arg;
	usage: import arg;
include "io.m";
	io: Io;
	readdev, readfile: import io;
include "netget.m";

Tick: con 30;	# refresh rate, seconds.


procpid := -1;
debug := 0;
ndbstr: string;
constndb: string;

init(nil: ref Draw->Context, args: list of string)
{
	xinit();
	regdir : string;
	arg = load Arg Arg->PATH;
	arg->init(args);
	arg->setusage("netget [-d] [-r regdir] name spec");
	while((opt := arg->opt()) != 0) {
		case opt{
		'r' =>
			regdir = arg->earg();
		'd' =>
			debug = 1;
		* =>
			usage();
		}
	}
	args = arg->argv();
	nargs := len args;
	if(nargs == 0 || (nargs%2) != 0)
		usage();
	l : list of (string, string);
	while(len args > 0){
		l = (hd args, hd tl args) :: l;
		args = tl args; args = tl args;
	}
	e := announcelist(l, regdir);
	if(e != nil){
		fprint(stderr, "netget: %s\n", e);
		raise("fail: errors");
	}
}

xinit()
{
	sys = load Sys Sys->PATH;
	err = load Error Error->PATH;
	err->init(sys);
	regs = load Registries Registries->PATH;
	io = load Io Io->PATH;
	env = load Env Env->PATH;
	if(regs == nil || env == nil || io == nil)
		error("unable to load modules: %r");
	regs->init();
}

devread(n: string) : string
{
	v := getenv(n);
	if(v == nil)
		v = readdev("/dev/" + n, "unknown");
	return v;
}

locate(s: string): (string, string)
{
	location := readdev("/mnt/what/" + s + "/where", nil);
	if(location == nil)
		location = getenv("location");
	if(location == nil)
		location = "none";
	radius := readdev("/mnt/what/" + s + "/radius", "0");
	return (location, radius);
}

announceproc(sysname: string, rs: list of ref Registered)
{
	procpid = pctl(0, nil);
	for(;;){
		(location, radius) := locate(sysname);
		s := sprint("loc %s rad %s lease %d", location, radius, 2*Tick);
		if(debug)
			fprint(stderr, "%s\n", s);
		for(l := rs; l != nil; l = tl l){
			r := hd l;
			d := array of byte s;
			if(write(r.fd, d, len d) != len d)
				error(sprint("netget: announceproc: %r\n"));
			ndbstr = constndb + " " + s;
		}
		sleep(Tick*1000);
	}
	if(debug)
		fprint(stderr, "netget: exiting\n");
}

ndb(): string
{
	return ndbstr;
}

buildattrs(args: list of string) : ref Attributes
{
	a:= Attributes.new(nil);
	while(args != nil){
		nam := hd args;
		args = tl args;
		if(args == nil)
			return nil;
		val := hd args;
		args = tl args;
		a.set(nam, val);
	}
	return a;
}

announcelist(ads: list of (string, string), regdir: string): string
{
	reg : ref Registry;
	if(sys == nil)
		xinit();
	if(regdir != nil)
		reg = Registry.new(regdir);
	else {
		reg = Registry.new(nil);
		if(reg == nil){
			svc := ref Service("tcp!pc!registry", Attributes.new(("auth", "infpk1")::nil));
			reg = Registry.connect(svc, devread("user"), nil);
		}
	}
	if(reg == nil)
		return sprint("announce: reg: %r");
	sysname := devread("sysname");
	user := devread("user");
	(location, radius) := locate(sysname);
	arch := getenv("emuhost") + getenv("cputype");
	regs : list of ref Registered;
	while(ads != nil){
		(name, spec) := hd ads;
		(na, al) := tokenize(spec, " \t\n");
		if(na < 0 || (na%2) != 0)
			return "bad attribute list";
		attrs := buildattrs(al);
		if(attrs == nil)
			return "bad formed attribute list";
		attrs.set("name", name);
		name = "o!" + sysname + "!" + name;
		path := attrs.get("path");
		if(path == nil)
			return "path attribute not found";
		path = "/terms/" + sysname + path;
		attrs.set("path", path);
		attrs.set("sys", sysname);
		attrs.set("user", user);
		attrs.set("loc", location);
		attrs.set("rad", radius);
		attrs.set("arch", arch);
		constndb = "path " + path + " sys " + sysname + " user " + user + " arch " + arch;
		(r, e) := reg.register(name, attrs, 0);
		if(debug)
			fprint(stderr, "netget: announcing %s\n", name);
		if(e != nil)
			return "announce: " + e;
		regs = r :: regs;
		ads = tl ads;
	}
	spawn announceproc(sysname, regs);
	return nil;
}

announce(name: string, spec: string) : string
{
	return announcelist( (name,spec)::nil, nil );

}

terminate()
{
	if(sys != nil)
		kill(procpid, "kill");
}
