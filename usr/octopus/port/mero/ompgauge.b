implement Pimpl;
include "sys.m";
	sys: Sys;
	sprint, fprint: import sys;
include "styx.m";
include "styxservers.m";
	Styxserver: import Styxservers;
include "daytime.m";
include "merocon.m";
include "lists.m";
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
	return list of {"gauge:", "slider:"};
}

pinit(p: ref Panel)
{
	p.data = array of byte "30\n";
}

rinit(nil: ref Panel, r: ref Repl)
{
	nattrs := array[len r.attrs] of Attr;
	nattrs[0:] = r.attrs;
	r.attrs = nattrs;
}

strchr(s : string, c : int) : int
{
	for(i := 0; i < len s; i++)
		if(s[i] == c)
			return i;
	return -1;
} 

newdata(p: ref Panel): string
{
	s := string p.data;
	for(i := 0; i < len s; i++)
		if(strchr("0123456789", s[i]) < 0)
			break;
	if((i == len s - 1 && s[i] == '\n') || i == len s){
		n := int s;
		if(n < 0 || n > 100)
			return "value not in [0,100]";
		p.data = array of byte(string n + "\n");
		return nil;
	}
	return "not a number";
}

ctl(nil: ref Panel, nil: ref Repl, nil: list of string): (int, string, string)
{
	return (0, "not mine", nil);
}
