implement Pimpl;
include "sys.m";
	sys: Sys;
	tokenize, sprint, fprint: import sys;
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
include "blks.m";
include "merop.m";
include "merotree.m";

Drawfunc: type ref fn(args: list of string): string;

Dcmd: adt {
	name: string;
	drawfn: Drawfunc;
};

icols: array of string;
dcmds: array of Dcmd;

init(d: Dat): list of string
{
	dat = d;
	sys = dat->sys;
	err = dat->err;
	str = dat->str;
	names = dat->names;
	# keep in sync with owpdraw.b, including the functions!
	dcmds = array[] of {
		Dcmd("ellipse", dellipse),		# ellipse cx cy rx ry  [w col]
		Dcmd("fillellipse", dfillellipse),	# fillellipse cx cy rx ry  [col]
		Dcmd("line", dline),		# line ax ay bx by [ea eb r col]
		Dcmd("rect", drect),		# rect ax ay bx by [col]
		Dcmd("poly", dpoly),		# poly x0 y0 x1 y1 ... xn yn e0 en w col
		Dcmd("bezspline", dpoly),		# bezspline x0 y0 x1 y1 ... xn yn e0 en w col
		Dcmd("fillpoly", dfillpoly),		# fillpoly x0 y0 x1 y1 ... xn yn w col
		Dcmd("fillbezspline", dfillpoly)	# fillbezspline x0 y0 x1 y1 ... xn yn w col
	};
	icols = array[] of {
		"back", "high", "bord", "text", "htext", "hbord", "set", "clear",
		"mback", "mset", "mclear",
		"black",
		"white",
		"red",
		"green",
		"blue",
		"cyan",
		"magenta",
		"yellow",
		"grey",
		"paleyellow",
		"darkyellow",
		"darkgreen",
		"palegreen",
		"medgreen",
		"darkblue",
		"palebluegreen",
		"paleblue",
		"bluegreen",
		"greygreen",
		"palegreygreen",
		"yellowgreen",
		"medblue",
		"greyblue",
		"palegreyblue",
		"purpleblue"
	};

	return list of {"draw:"};
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

chkcol(s: string): string
{
	for(i := 0; i < len icols; i++)
		if(icols[i] == s)
			return nil;
	return sprint("%s: not a color", s);
}

nth(l: list of string, n: int): string
{
	for(i := 0; i < n && l != nil; i++)
		l = tl l;
	if(l != nil)
		return hd l;
	else
		return nil;
}

dellipse(args: list of string): string
{
	if(len args < 5 || len args > 7)
		return "ellipse: wrong number of args";
	if(len args == 7){
		c := chkcol(nth(args, 6));
		if(c != nil)
			return c;
	}
	return nil;
}

dfillellipse(args: list of string): string
{
	if(len args < 5 || len args > 6)
		return "fillellipse: wrong number of args";
	if(len args == 6){
		c := chkcol(nth(args, 5));
		if(c != nil)
			return c;
	}
	return nil;
}

dline(args: list of string): string
{
	if(len args < 5 || len args > 9)
		return "line: wrong number of args";
	if(len args >= 9){
		c := chkcol(nth(args, 8));
		if(c != nil)
			return c;
	}
	return nil;
}

drect(args: list of string): string
{
	if(len args < 5 || len args > 6)
		return "rect: wrong number of args";
	if(len args == 6){
		c := chkcol(nth(args, 5));
		if(c != nil)
			return c;
	}
	return nil;
}

dpoly(args: list of string): string
{
	l := len args;
	if(l < 5 + 3 * 2)
		return sprint("%s: wrong number of args", hd args);
	np := (l -5)/2;
	args = tl args;
	for(i := 0; i < np; i++)
		args = tl tl args;
	args = tl args;
	args = tl args;
	args = tl args;
	return chkcol(hd args);
}

dfillpoly(args: list of string): string
{
	l := len args;
	if(l < 3 + 3 * 2)
		return sprint("%s: wrong number of args", hd args);
	np := (l - 3)/2;
	args = tl args;
	for(i := 0; i < np; i++){
		args = tl tl args;
	}
	args = tl args;
	return chkcol(hd args);
}

drawcmds(s: string): string
{
	(nil, cmds) := tokenize(s, "\n");
	for(; cmds != nil; cmds = tl cmds){
		(nargs, args) := tokenize(hd cmds, " \t");
		if(nargs > 0){
			for(i := 0; i < len dcmds; i++)
				if(dcmds[i].name == hd args){
					x := dcmds[i];
					e := x.drawfn(args);
					if(e != nil)
						return e;
					else
						break;
				}
			if(i == len dcmds)
				return "bad draw operation";
		}
	}
	return nil;
}

newdata(p: ref Panel): string
{
	return drawcmds(string p.data);
}

ctl(nil: ref Panel, nil: ref Repl, nil: list of string): (int, string, string)
{
	return (0, "not mine", nil);
}
