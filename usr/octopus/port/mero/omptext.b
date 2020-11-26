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
	lists: Lists;
	append: import lists;
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
include "mpanel.m";
	panels: Panels;
	Attr, Amax, Panel, Repl, Tappl, Trepl: import panels;
	escape, chkargs: import panels;
include "merop.m";
include "blks.m";
include "merotree.m";

Aclean, Afont, Asel, Atab, Ausel, Ascroll, Atemp: con Amax + iota;

init(d: Dat): list of string
{
	dat = d;
	sys = dat->sys;
	err = dat->err;
	str = dat->str;
	lists = dat->lists;
	names = dat->names;
	panels = dat->panels;
	return list of {"text:", "button:", "label:", "tag:", "tbl:"};
}

pinit(p: ref Panel)
{
	(t, n) := splitl(p.name, ":");
	if(n != nil)
		n = n[1:];
	else
		n = "";
	case t {
	* =>
		p.data = array of byte "";
	"button" or "label" =>
		p.data = array of byte n;
	}
	p.editions = 1;
	p.edits = "";
}

rinit(p: ref Panel, r: ref Repl)
{
	(t, nil) := splitl(p.name, ":");
	nfont := "font R";
	case t {
	"tbl" =>
		nfont = "font T";
	"label" or "button" or "tag" =>
		nfont = "font B";
	* =>
		nfont = "font R";
	}
	++vgen;
	attrs := array[] of { ("clean", vgen), (nfont, vgen), ("sel 0 0", vgen),
		("tab 4", vgen), ("usel", vgen), ("noscroll", vgen), ("notemp", vgen)};
	nattrs := array[len r.attrs + len attrs] of Attr;
	nattrs[0:] = r.attrs;
	nattrs[len r.attrs:] = attrs;
	r.attrs = nattrs;

}

newdata(p: ref Panel): string
{
	for(i := 0; i < len p.data; i++)
		if(p.data[i] == byte 0)
			return "UTF 0 not allowed";
	p.edits = "";
	p.editing = 0;
	# panels in scroll mode ket the last 16K of text.
	if(len p.repl > 0 && (r := p.repl[0]) != nil)
	if(r.attrs[Ascroll].v == "scroll" && len p.data > 64 * 1024){
		off := len p.data - 32 * 1024;
		p.data = p.data[off:];
	}
	return nil;
}

sel(p: ref Panel, r: ref Repl, args: list of string): (int, string, string)
{
	n := int hd tl args;
	n2:= int hd tl tl args;
	if(n < 0 || n2 < 0)
		return (0, "negative pos", nil);
	if(n > len p.data)
		n = len p.data;
	if(n2 > len p.data)
		n2 = len p.data;
	return p.setattr(r, Asel, 0, sprint("sel %d %d", n, n2));
}

font(p: ref Panel, r: ref Repl, args: list of string): (int, string, string)
{
	fonts := array[] of  { "L", "B", "S", "R", "I", "T" };
	for(x := 0; x < len fonts; x++)
		if(hd tl args == fonts[x])
			break;
	if(x == len fonts)
		return (0, "not a font", nil);
	return p.setattr(r, Afont, 1, "font " + fonts[x]);
}

tab(p: ref Panel, r: ref Repl, args: list of string): (int, string, string)
{
	n := int hd tl args;
	if(n < 3 || n > 10)
		return (0, "tab must be in [3:10]", nil);
	return p.setattr(r, Atab, 0, sprint("tab %d", n));
}

# Cooperative editing is done via edstart/ins/del/edend.
# edstart starts editing and must supply the actual version as seen from
# outside o/mero. It locks the version and accepts further ins/del that
# match the same locked version. A final edend unlocks and increments
# the version.
# Note that in this case the qid vers for the data is not updated, this means
# that during coop. editing no data updates should be sent.
# A data update event would reset the data and edits list from the scratch.

# BUG: Although we store data as array of byte, positions refer
# to runes. Converting to string and back to array of byte was fine
# for testing, but it's not reasonable anymore. This affects ins() and del().

del(p: ref Panel, nil: ref Repl, args: list of string): (int, string, string)
{
	tag := int hd tl args;
	vers := int hd tl tl args;
	if(p.editing != 1)
		return (0, sprint("%d panel editors", p.editing), nil);
	if(vers != p.evers)
		return(0, sprint("version is %d (not %d)", p.evers, vers), nil);
	pos := int hd tl tl tl args;
	n := int hd tl tl tl tl args;
	data := string p.data;
	if(pos > len data)
		pos = len data;
	if(pos < 0)
		return (0, "negative pos", nil);
	if(pos + n > len data)
		n = len data - pos;
	if(n == 0)
		return (0, nil, nil);
	if(n < 0)
		return (0, "negative del", nil);
	s := sprint("del %d %d %d %s", tag, vers, pos, data[pos:pos+n]);
	data = data[0:pos] + data[pos+n:];
	p.data = array of byte data;
	p.edits += escape(s) + "\n";
	return (0, nil, s);
}

ins(p: ref Panel, nil: ref Repl, args: list of string): (int, string, string)
{
	tag := int hd tl args;
	vers := int hd tl tl args;
	if(p.editing != 1)
		return (0, sprint("%d panel editors", p.editing), nil);
	if(vers != p.evers)
		return(0, sprint("version is %d (not %d)", p.evers, vers), nil);
	pos := int hd tl tl tl args;
	b := hd tl tl tl tl args;
	data := string p.data;
	if(pos+1 > len data)
		pos = len data;
	if(pos < 0)
		return (0, "negative pos", nil);
	s := sprint("ins %d %d %d %s", tag, vers, pos, b);
	data = data[0:pos] + b + data[pos:];
	p.data = array of byte data;
	p.edits += escape(s) + "\n";
	return (0, nil, s);
}

edstart(p: ref Panel, nil: ref Repl, args: list of string): (int, string, string)
{
	vers := int hd tl args;
	if(debug)
		fprint(stderr, "o/mero: edstart for vers %d\n", vers);
	if(p.editing)
		return(0, "panel being edited", nil);
	if(vers != p.evers)
		return(0, sprint("version is %d (not %d)", p.evers, vers), nil);
	p.editing = 1;
	return (0, nil, nil);
}

edend(p: ref Panel, nil: ref Repl, args: list of string): (int, string, string)
{
	tag := int hd tl args;
	vers := int hd tl tl args;
	if(debug)
		fprint(stderr, "o/mero: edend for vers %d\n", vers);
	if(p.editing != 1)
		return (0, sprint("%d panel editors", p.editing), nil);
	if(vers != p.evers)
		return(0, sprint("version is %d (not %d)", p.evers, vers), nil);
	p.editing = 0;
	p.evers++;		# and report one more.
	return (0, nil, sprint("edend %d %d", tag, p.evers));
}

argl: list of (string, int);
ctl(p: ref Panels->Panel, r: ref Panels->Repl, ctl: list of string): (int, string, string)
{
	if(argl == nil)
		argl = list of {("clean", 1), ("dirty", 1), ("font", 2), ("sel", 3),
		("ins", 5), ("del", 5), ("edstart", 2), ("edend", 3),
		("tab", 2), ("usel", 1), ("nousel", 1),
		("scroll", 1), ("noscroll", 1), ("temp", 1), ("notemp", 1)};

	e := chkargs(ctl, argl);
	if(e != nil)
		return (0, e, nil);
	case hd ctl {
	"clean" or "dirty" =>
		return p.setattr(r, Aclean, 1, hd ctl);
	"font" =>
		return font(p, r, ctl);
	"sel" =>
		return sel(p, r, ctl);
	"edstart" =>
		return edstart(p, r, ctl);
	"edend" =>
		return edend(p, r, ctl);
	"ins" =>
		return ins(p, r, ctl);
	"del" =>
		return del(p, r, ctl);
	"tab" =>
		return tab(p, r, ctl);
	"usel" or "nousel" =>
		return p.setattr(r, Ausel, 1, hd ctl);
	"scroll" or "noscroll" =>
		return p.setattr(r,  Ascroll, 1, hd ctl);
	"temp" or "notemp" =>
		return p.setattr(r, Atemp, 1, hd ctl);
	* =>
		return (0, "not mine", nil);
	}
}
