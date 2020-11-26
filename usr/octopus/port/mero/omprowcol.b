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
	vgen, mnt, debug, appl, slash: import dat;
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
include "merop.m";
include "blks.m";
include "merotree.m";
include "mpanel.m";
	panels: Panels;
	Attr, Atag, Amax, Panel, Repl, Tappl, Trepl: import panels;

Aorder, Arow: con Amax + iota;

init(d: Dat): list of string
{
	dat = d;
	sys = dat->sys;
	err = dat->err;
	str = dat->str;
	names = dat->names;
	panels = dat->panels;
	return list of {"row:", "col:"};
}

pinit(p: ref Panel)
{
	p.container = 1;
}

rinit(p: ref Panel, r: ref Repl)
{
	(t, nil) := splitl(p.name, ":");
	rowcol: string;
	case t {
	"row" =>
		rowcol = "row";
	* =>
		rowcol = "col";
	}
	r.attrs[Atag] = ("tag", vgen);
	attrs := array[] of { ("order", vgen), (rowcol, vgen) };
	nattrs := array[len r.attrs + len attrs] of Attr;
	nattrs[0:] = r.attrs;
	nattrs[len r.attrs:] = attrs;
	r.attrs = nattrs;
}

newdata(nil: ref Panels->Panel): string
{
	return "not to a container";
}

ctl(p: ref Panels->Panel, r: ref Panels->Repl, ctl: list of string): (int, string, string)
{
	case hd ctl {
	"row" or "col" =>
		if(len ctl != 1)
			return (0, "no arguments wanted", nil);
		return p.setattr(r, Arow, 0, hd ctl);
	* =>
		# order is handled by the tree, not by us.
		return (0, "not mine", nil);
	}
}

