# Notify the system about a new terminal mounted through ofs.
# This is octopus-specific and might not be of help for a std inferno system.

implement Ofsnotify;

include "sys.m";
	sys: Sys;
	pctl, sprint, fprint: import sys;
include "error.m";
	err: Error;
	checkload, stderr, error: import err;
include "registries.m";
	regs: Registries;
	Service, Registered, Attributes, Registry: import regs;

include "ofsnotify.m";

what: string;
sname: string;
pidreg: ref Registered;

init(w: string)
{
	sys = load Sys Sys->PATH;
	err = load Error Error->PATH;
	err->init(sys);
	regs = checkload(load Registries Registries->PATH, Registries->PATH);
	regs->init();
	what =  "/terms/" + w;
	sname = w;
}

arrived()
{
	reg := Registry.new(nil);
	if(reg == nil){
		fprint(stderr, "ofs: registry: %r");
		return;
	}
	pid := pctl(0, nil);
	a:= Attributes.new(nil);
	a.set("name", "ofs");
	a.set("sys", sname);
	a.set("pid", sprint("%d", pid));
	name := sprint("%s!ofs", sname);
	(r, e) := reg.register(name, a, 0);
	if(e != nil){
		fprint(stderr, "ofs: reg: %r");
		return;
	}
	pidreg = r;
}

gone()
{
	pidreg = nil;
}
