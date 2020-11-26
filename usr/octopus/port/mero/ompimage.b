implement Pimpl;
include "sys.m";
	sys: Sys;
	sprint, fprint: import sys;
include "styx.m";
include "styxservers.m";
	Styxserver: import Styxservers;
include "daytime.m";
include "merocon.m";
include "dat.m";
	dat: Dat;
	mnt, debug, appl, slash: import dat;
include "string.m";
	str: String;
	splitl: import str;
include "names.m";
	names: Names;
	dirname: import names;
include "error.m";
	err: Error;
	checkload, panic, stderr: import err;
include "tbl.m";
	tbl: Tbl;
	Table: import tbl;
include "lists.m";
include "mpanel.m";
	Attr, Amax, Panel, Repl, Tappl, Trepl: import Panels;
include "merop.m";
include "blks.m";
include "merotree.m";

init(d: Dat): list of string
{
	dat = d;
	sys = dat->sys;
	err = dat->err;
	str = dat->str;
	names = dat->names;
	return list of {"image:", "page:"};
}

pinit(nil: ref Panel)
{
}

rinit(nil: ref Panel, r: ref Repl)
{
	nattrs := array[len r.attrs] of Attr;
	nattrs[0:] = r.attrs;
	r.attrs = nattrs;
}

newdata(nil: ref Panel): string
{
	# Could assume all viewers are in Inferno, and thus, check out the image
	# for validity. But let's try this.
	return nil;
}

ctl(nil: ref Panel, nil: ref Repl, nil: list of string): (int, string, string)
{
	return (0, "not mine", nil);
}
