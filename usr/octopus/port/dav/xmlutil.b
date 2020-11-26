implement Xmlutil;
include "sys.m";
	sys: Sys;
	open, fildes, OREAD, OWRITE, werrstr, announce, fprint, sprint: import sys;
include "draw.m";
include "error.m";
	err: Error;
	checkload, stderr, error, kill: import err;
include "string.m";
	str: String;
	splitl, tolower: import str;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "daytime.m";
	daytime: Daytime;
include "readdir.m";
include "msgs.m";
	msgs: Msgs;
	Cok, Sok, Cbad, Sbad, Msg, Hdr: import msgs;
include "xml.m";
	xml: Xml;
	Parser, Item, Locator, Attributes, Mark: import xml;
include "names.m";
include "svc.m";
include "dat.m";
include "xmlutil.m";
include "dlock.m";

init(d: Dat)
{
	sys = d->sys;
	str = d->str;
	xml = d->xml;
	err = d->err;
	bufio = d->bufio;
}

# build a tag tree. Put tags in lowercase if lc and
# expand names according to XML name spaces.
Tag.parse(iob: ref Iobuf, lc: int): ref Tag
{
	(p, e) := xml->fopen(iob, "xml", nil, nil);
	if(e != nil)
		return nil;
	t := mktree(p, Rootname, nil, nil, lc);
	return t;
}

tagtext(t: ref Tag, lv: int): string
{
	ts := "";
	for(i := 0; i < lv; i++)
		ts += "\t";

	if(t.name == Textname && t.txt != nil)
		return t.txt;
	s := "";
	if(t.name == Rootname)
		# fake top-level node. Use it to print our version.
		s += "<?xml version=\"1.0\" encoding=\"utf-8\"?>\r\n";
	else {
		lv++;
		s += sprint("%s<%s", ts, t.name);
		for(l := t.attrs; l != nil; l = tl l)
			s += sprint(" %s=\"%s\"", (hd l).name, (hd l).value);
		if(t.attrs == nil && t.tags == nil) # print short form
			return s + "/>\r\n";
		s += ">\r\n";
	}
	if(t.txt != nil)
		s += t.txt;
	for(cl := t.tags; cl != nil; cl = tl cl)
		s += tagtext(hd cl, lv);
	if(t.name != Rootname)
		s += sprint("%s</%s>\r\n", ts, t.name);
	return s;
}

Tag.text(t: self ref Tag): string
{
	return tagtext(t, 0);
}

# We should probably remove the "dav:" prefix from
# tag names after expanding ns processing and translating
# to lowercase.
nsname(ns: list of Attr, nm: string): string
{
	(n, s) := splitl(nm, ":");
	if(len n == 0 || len s == 0)
		return nm;
	for(; ns != nil; ns = tl ns)
		if((hd ns).name == n)
			return (hd ns).value + s[1:];
	return nm;
}

nsbind(ns: list of Attr, al: list of Xml->Attribute): list of Attr
{
	for(; al != nil; al = tl al){
		a := hd al;
		if(len a.name > 6 && a.name[0:6] == "xmlns:")
			ns = (a.name[6:], a.value)::ns;
	}
	return ns;
}

mktree(xp: ref Parser, nm: string, al: list of Attr, ns: list of Attr, lc: int): ref Tag
{
	nm = nsname(ns, nm);
	if(lc)
		nm = tolower(nm);
	cl: list of ref Tag;
	while((n := xp.next()) != nil){
		pick nn := n {
		Tag =>
			tal := nn.attrs.all();
			ns = nsbind(ns, tal);
			xp.down();
			ct := mktree(xp, nn.name, tal, ns, lc);
			xp.up();
			cl = ct::cl;
		Text =>
			if(len nn.ch > 0)
				cl = ref Tag(Textname, nil, nil, nn.ch)::cl;
		Process =>
			;
		Doctype =>
			;
		Error =>
			fprint(stderr, "dav: xmlutil: error %s\n", nn.msg);
		}
	}
	tags: list of ref Tag;
	for(; cl != nil; cl = tl cl)
		tags = hd cl::tags;
	return ref Tag(nm, al, tags, nil);
}
