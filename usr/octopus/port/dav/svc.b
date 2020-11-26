# service procedures.
# this implements the known methods.
implement Svc;
include "sys.m";
	sys: Sys;
	open, OREAD, Dir, QTDIR, OWRITE, OTRUNC, FD,
	create, DMDIR, write, remove, tokenize, wstat,
	stat, werrstr, announce, fprint, sprint: import sys;
include "draw.m";
include "error.m";
	err: Error;
	checkload, stderr, error, kill: import err;
include "string.m";
	str: String;
	splitstrr, splitl, prefix, toupper, tolower: import str;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "daytime.m";
	daytime: Daytime;
	gmt: import daytime;
include "names.m";
	names: Names;
	cleanname, dirname, basename, rooted: import names;
include "msgs.m";
	msgs: Msgs;
	Cok, Sok, Cbad, Sbad, Cperm, Cmulti, Smulti, Cnotfound,
	Cnotallow, Snotallow, Ccreated, Screated, Csto, Clocked,
	Slocked, Cnone, Snone, Cprecond, Sprecond,
	Msg, Hdr: import msgs;
include "xml.m";
	xml: Xml;
	Parser, Item, Locator, Attributes, Mark: import xml;
include "xmlutil.m";
	xmlutil: Xmlutil;
	Textname, Rootname, Tag, Attr: import xmlutil;
include "dlock.m";
	dlock: Dlock;
	canlock, locked, unlock, rmlocks, renew: import dlock;
	Lease, Lfree, Lread, Lwrite, Lrenew: import dlock;
include "readdir.m";
	readdir: Readdir;
include "dat.m";
include "svc.m";

Svcfn: adt {
	method:	string;
	handler:	ref fn(m: ref Msg, uri: string): ref Msg;
};

# bits defining properties. As returned by tag2prop.
	Pmtime,
	Plength,
	Ptype,
	Pname,

	Pctime,
	Pctype,
	Plang,
	Pqid,

	Plock,
	Powner :	con 1<<iota;

# properties retrieved by allprop request
# these must not include ACL props.
	Pall :	con 16rFF;

svcs: array of Svcfn;
fsdir: string;
rdonly := 0;

init(d: Dat, dir: string, ro: int)
{
	sys = d->sys;
	err = d->err;
	str = d->str;
	msgs = d->msgs;
	daytime = d->daytime;
	readdir = d->readdir;
	bufio = d->bufio;
	dlock = d->dlock;
	xml = d->xml;
	xmlutil = d->xmlutil;
	names = d->names;

	fsdir = dir;
	rdonly = ro;

	svcs = array[] of {
		("options",	soptions),
		("propfind",	spropfind),
		("get",		sget),
		("head",	shead),
		("put",		sput),
		("mkcol",	smkcol),
		("lock",	slock),
		("unlock",	sunlock),
		("delete",	sdelete),
		("move",	smove),
		("copy",	scopy),
		("proppatch", sno),
	};
}

sno(m: ref Msg, nil: string): ref Msg
{
	pick h := m.hdr {
	Req =>
		if(debug)fprint(stderr, "\n*****\n");
		fprint(stderr, "dav: %s not implemented\n", h.method);
		if(debug)fprint(stderr, "*****\n\n");
	}
	return ref Msg(m.hdr.mkrep(Cnotallow, Snotallow), nil);
}

soptions(m: ref Msg, nil: string): ref Msg
{
	rhdr := m.hdr.mkrep(Cok, Sok);
	what := toupper(svcs[0].method);
	for(i := 1; i < len svcs; i++)
		what += ", " + toupper(svcs[i].method);
	rhdr.putopt("Allow", what);
	rhdr.putopt("DAV", "1, 2, access-control");
	rhdr.putopt("Date", daytime->time());
	rhdr.putopt("Server", "o/dav");
	return ref Msg(rhdr, nil);
}

getxml(m: ref Msg): (ref Tag, string)
{
	if(m.body == nil)
		return (nil, nil);
	ct := m.hdr.getopt("content-type");
	if(ct == nil)
		return (nil, "no content-type");
	ct = tolower(ct);
	(ct0, nil) := splitl(ct, ";");
	if(ct0 != nil)
		ct = ct0;
	if(ct != "text/xml" && ct != "application/xml")
		return (nil, "not xml");
	xio := bufio->aopen(m.body);
	x := Tag.parse(xio, 1);
	xio.close();
	return (x, nil);
}

mdepth(m: ref Msg): int
{
	ds := m.hdr.getopt("depth");
	if(ds == nil)
		return -1; # infinite; not an error.
	if(tolower(ds) == "infinity")
		return -1;
	return int ds;
}


# rfc2518; 8.1 and 12.14 for dav
# rfc3744 for acls
#
spropfind(m: ref Msg, uri: string): ref Msg
{
	(xp, xe) := getxml(m);
	if(xe != nil)
		return ref Msg(m.hdr.mkrep(Cbad, Sbad+": "+xe), nil);
	if(xp != nil && debug > 1)
		fprint(stderr, "%s\n", xp.text());
	depth := mdepth(m);
	# support only depths 0 and 1. Do not want to retrieve full trees.
	if(depth < 0)
		return ref Msg(m.hdr.mkrep(Cbad, Sbad+": too dangerous"), nil);
	props := wantedprops(uri, xp);

	rhdr := m.hdr.mkrep(Cmulti, Smulti);
	rhdr.putopt("Content-Type", "text/xml; charset=\"utf-8\"");
	(rc, dir) := sys->stat(uri);
	if(rc < 0)
		return ref Msg(m.hdr.mkrep(Cnotfound, sprint("%r")), nil);
	rl := list of { propfind(uri, ref dir, props) };
	if(depth > 0 && dir.qid.qtype&QTDIR){
		(dirs, n) := readdir->init(uri, readdir->NONE);
		for(i := 0; i < n; i++){
			furi := names->rooted(uri, dirs[i].name);
			if(dirs[i].qid.qtype&QTDIR)
				furi += "/";
			rl = propfind(furi, dirs[i], props)::rl;
		}
	}
	ms := ref Tag("multistatus", list of {Attr("xmlns", "DAV:")}, rl, nil);
	rx := ref Tag(Rootname, nil, list of {ms}, nil);
	body := array of byte rx.text();
	return ref Msg(rhdr, body);
}

wantedprops(uri: string, xp: ref Tag): int
{
	# xp may be nil, meaning all props.
	props := Pall;
	if(xp == nil || xp.tags == nil)
		return Pall;

	pf := hd xp.tags;
	if(pf.name != "dav:propfind" && pf.name != "propfind")
		fprint(stderr, "dav: warning: tag not propfind\n");
	if(pf.tags == nil){
		# none asked for, assume all.
		return Pall;
	}
	props = 0;
	for(l := pf.tags; l != nil; l = tl l){
		pfr := hd l;
		case pfr.name {
		"dav:allprop" or "allprop" =>
			props = Pall;
		"dav:propname" or "propname"=>
			return 0;	# means just names
		"dav:prop" or "prop" =>
			for(pl := pfr.tags; pl != nil; pl = tl pl)
				props |= tag2prop(uri, hd pl);
		* =>
			if(debug)
			fprint(stderr, "dav: wantedprops: %s?\n", pfr.name);
		}
	}
	return props;
}


# rfc2518; 13.
# Should also provide the supportedlock property in case the client asks for it
# to see if we have locks.
tag2prop(uri: string, t: ref Tag): int
{
	if(t == nil)
		return 0;
	if(prefix(uri, t.name))
		t.name = t.name[len uri:];
	case t.name {
	"dav:getlastmodified" or  "getlastmodified" =>
		return Pmtime;
	"dav:getcontentlength" or  "getcontentlength" =>
		return Plength;
	"dav:resourcetype" or "resourcetype" =>
		return Ptype; # must be defined, and must be empty!
	"dav:displayname" or "displayname" or "name" =>
		return Pname;
	"dav:creationdate" or  "creationdate" =>
		return Pctime;
	"dav:getcontenttype" or "getcontenttype" =>
		return Pctype;
	"dav:getcontentlanguage" or "getcontentlanguage" =>
		return Plang;
	"dav:getetag" or  "getetag" =>
		return Pqid;
	"dav:supportedlock" or   "supportedlock" =>
		return Plock;
	"dav:owner" or "owner" =>
		return Powner;
	}
	return 0;
}


propfindtag(t: string, d: ref Dir, props: int, p: int): string
{
	if(props == 0)
		return "<"+t+"/>";
	else if(props&p){
		s := "";
		case p {
		Pmtime or Pctime =>
			s = daytime->text(gmt(d.mtime));
		Plength =>
			# should be the content length.
			s = sprint("%bd", d.length);
		Ptype =>
			if(d.qid.qtype&QTDIR)
				s = "<collection/>";
			else
				s = "";
		Pname =>
			s = d.name;
		Pctype =>
			# should be the content type for this thing.
			if(d.qid.qtype&QTDIR)
				s = "text/xml";
			else
				s = "application/binary";
		Plang =>
			s = "us-en";
		Pqid =>
			s = sprint("%bd", d.qid.path);
		Plock =>
			s = "\r\n\t\t\t\t<DAV:lockentry>\r\n" +
			"\t\t\t\t<DAV:lockscope><DAV:exclusive/></DAV:lockscope>\r\n"+
			"\t\t\t\t<DAV:locktype><DAV:write/></DAV:locktype>\r\n"+
			"\t\t\t\t</DAV:lockentry>\r\n";
			s += "\t\t\t\t<DAV:lockentry>\r\n" +
			"\t\t\t\t<DAV:lockscope><DAV:shared/></DAV:lockscope>\r\n"+
			"\t\t\t\t<DAV:locktype><DAV:write/></DAV:locktype>\r\n"+
			"\t\t\t\t</DAV:lockentry>\r\n";

		Powner =>
			s = d.uid;
		}
		return "\t\t\t<"+t+">" + s + "</"+t+">\r\n";
	}
	return "";
}

propfind(uri: string, d: ref Dir, props: int): ref Tag
{
	# uri = escape uri for http
	s: string;
	s +=  "<response>\r\n" +
		"\t<href>" + uri + "</href>\r\n" +
		"\t<propstat>\r\n" +
			"\t\t<prop>\r\n";
	s += propfindtag("getlastmodified", d, props, Pmtime);
	s += propfindtag("getcontentlength", d, props, Plength);
	s += propfindtag("resourcetype", d, props, Ptype);
	s += propfindtag("displayname", d, props, Pname);
	s += propfindtag("creationdate", d, props, Pctime);
	s += propfindtag("getcontenttype", d, props, Pctype);
	s += propfindtag("getcontentlanguage", d, props, Plang);
	s += propfindtag("getetag", d, props, Pqid);
	s += propfindtag("supportedlock", d, props, Plock);
	s += propfindtag("owner", d, props, Powner);
	s += 		"\t\t</prop>\r\n" +
			"\t\t<status>HTTP/1.1 200 OK</status>\r\n" +
		"\t</propstat>\r\n" +
	"</response>\r\n";
	return ref Tag(Textname, nil, nil, s);
}

sgethead(m: ref Msg, uri: string, isget: int): ref Msg
{
	(rc, dir) := sys->stat(uri);
	if(rc < 0)
		return ref Msg(m.hdr.mkrep(Cnotfound, sprint("%r")), nil);
	if(dir.qid.qtype&QTDIR){
		dt := array of byte "directories are not shown";
		hdr := m.hdr.mkrep(Cok, Sok);
		hdr.putopt("Content-type", "application/text");
		return ref Msg(hdr, dt);
	}
	iob := bufio->open(uri, OREAD);
	if(iob == nil)
		return ref Msg(m.hdr.mkrep(Cnotfound, sprint("%r")), nil);
	rep := ref Msg(m.hdr.mkrep(Cok, Sok), nil);
	rep.hdr.clen = dir.length;
	rep.hdr.putopt("Content-type", "application/binary");
	rep.hdr.putopt("Content-language", "us-en");
	rep.hdr.putopt("Content-encoding", "binary");
	rep.hdr.putopt("Etag", sprint("%bd", dir.qid.path));
	rep.hdr.putopt("Last-modified", daytime->text(gmt(dir.mtime)));
	rep.hdr.putopt("Date", daytime->time());
	rep.hdr.putopt("Server", "o/dav");
	rep.putrep();
	if(isget){
		buf := array[1024] of byte;
		nr := iob.read(buf, len buf);
		while(nr > 0){
			m.hdr.iobout.write(buf[0:nr], nr);
			nr = iob.read(buf, len buf);
		}
	}
	m.hdr.iobout.flush();
	iob.close();
	return nil;
}

sget(m: ref Msg, uri: string): ref Msg
{
	return sgethead(m, uri, 1);
}

shead(m: ref Msg, uri: string): ref Msg
{
	return sgethead(m, uri, 0);
}

sputmkcol(m: ref Msg, uri: string, iscol: int): ref Msg
{
	if(rdonly)
		return sno(m, uri);
#if(!prefix("/tmp", uri))
#return ref Msg(m.hdr.mkrep(Cperm, "not outside /tmp"), nil);


	# surprise: locks may apply to files that do not exist.
	if(locked(uri, 0, hdrlocktoks(m.hdr)) != Lfree){
		if(debug)
			fprint(stderr, "put: %s: fail: locked\n", uri);
		return ref Msg(m.hdr.mkrep(Clocked, Slocked), nil);
	}
	(rc, dir) := stat(uri);
	fd: ref FD;
	if(rc < 0){
		if(iscol)
			fd = create(uri, OREAD, 8r755|DMDIR);
		else
			fd = create(uri, OWRITE, 8r664);
	} else if (dir.qid.qtype&QTDIR)
		if(iscol)
			return ref Msg(m.hdr.mkrep(Ccreated, Screated), nil);
		else
			return ref Msg(m.hdr.mkrep(Cperm, sprint("%r")), nil);
	else
		if(!iscol)
			fd = open(uri, OWRITE|OTRUNC);
		else
			return ref Msg(m.hdr.mkrep(Cperm, sprint("%r")), nil);
	if(fd == nil)
		return ref Msg(m.hdr.mkrep(Cperm, sprint("%r")), nil);
	if(m.body != nil && !iscol)
		if(write(fd, m.body, len m.body) != len m.body)
			return ref Msg(m.hdr.mkrep(Csto, sprint("%r")), nil);
	fd = nil;
	return ref Msg(m.hdr.mkrep(Ccreated, Screated), nil);
}

smkcol(m: ref Msg, uri: string): ref Msg
{
	return sputmkcol(m, uri, 1);
}

sput(m: ref Msg, uri: string): ref Msg
{
	return sputmkcol(m, uri, 0);
}


# build a multistatus reply for just an uri and a sts
# God blesh their single status multi-status replies
multists(m: ref Msg, uri: string, sts: string): ref Msg
{
	errs := "\t<DAV:response>\r\n" +
		"\t\t<DAV:href>"+uri+"</DAV:href>\r\n" +
		"\t\t<DAV:status>" +
		"HTTP/1.1 " + sts + 
		"</DAV:status>\r\n" +
		"\t\t</DAV:response>\r\n";
	rl := list of { ref Tag(Textname, nil, nil, errs) };
	rhdr := m.hdr.mkrep(Cmulti, Smulti);
	rhdr.putopt("Content-Type", "text/xml; charset=\"utf-8\"");
	ms := ref Tag("multistatus", list of {Attr("xmlns", "DAV:")}, rl, nil);
	rx := ref Tag(Rootname, nil, list of {ms}, nil);
	return ref Msg(rhdr, array of byte rx.text());
}

sdelete(m: ref Msg, uri: string): ref Msg
{


	if(rdonly)
		return sno(m, uri);
	uri = names->cleanname(uri);

#if(!prefix("/tmp/", uri) || uri == "/tmp" || prefix("/tmp/cache/", uri))
#	return ref Msg(m.hdr.mkrep(Cperm, "not here"), nil);

	# surprise: locks do not block deletes.
	(rc, dir) := stat(uri);
	if(rc >= 0){
		rmlocks(uri);
		if(fremove(ref dir, uri) < 0)
			return multists(m, uri, sprint("%d %r", Cperm));
	}
	return ref Msg(m.hdr.mkrep(Cok, Sok), nil);
	
}

wantedlock(xp: ref Tag): (int, string)
{
	# xp may be nil, meaning renew
	if(xp == nil || xp.tags == nil)
		return (Lrenew, nil);

	pf := hd xp.tags;
	if(pf.name != "dav:lockinfo" && pf.name  != "lockinfo")
		fprint(stderr, "dav: warning: tag not lockinfo\n");
	if(pf.tags == nil)
		return (-1, nil);
	owner: string;
	kind := -1;
	for(l := pf.tags; l != nil; l = tl l){
		pfr := hd l;
		case pfr.name {
		"dav:lockscope" or  "lockscope" =>
			if(pfr.tags == nil){
				if(debug)
				fprint(stderr, "dav: no lock scope\n");
				return (-1, nil);
			}
			pfl := hd pfr.tags;
			case pfl.name {
			"dav:exclusive" or "exclusive" =>
				kind = Lwrite;
			"dav:shared" or "shared" =>
				kind = Lread;
			* =>
				if(debug)
				fprint(stderr, "dav: lock %s?\n", pfl.name);
				return (-1, nil);
			}
		"dav:locktype" or "locktype"  =>
			; # assume write.
		"dav:owner" or "owner" =>
			# the text including the owner and href tags
			owner = pfr.text();
		}
	}
	if(owner != nil && kind != -1)
		return(kind, owner);
	return (-1, nil);
}

lockreply(depth: int, kind: int, owner: string, tok: string): ref Tag
{
	lstr := "exclusive";
	if(kind == Lread)
		lstr = "shared";
	dstr := "Infinity";
	if(depth == 0)
		dstr = "0";
	lrstr := "\t<DAV:lockdiscovery>\r\n" +
		"\t\t<DAV:activelock>\r\n" +
		"\t\t\t<DAV:locktype> <DAV:write/> </DAV:locktype>\r\n" +
		"\t\t\t<DAV:lockscope><DAV:"+lstr+"/></DAV:lockscope>\r\n" +
		"\t\t\t<DAV:depth>" + dstr + "<DAV:depth/>\r\n" +
		"\t\t\t" + owner + 
		sprint("\t\t\t<DAV:timeout>Second-%d</DAV:timeout>\r\n", Lease) +
		"\t\t\t<DAV:locktoken>" +
			"<DAV:href>" + "opaquelocktoken:"+tok + "</DAV:href>" +
			"</DAV:locktoken>\r\n" +
		"\t\t</DAV:activelock>\r\n" +
		"\t</DAV:lockdiscovery>\r\n";
	rl := list of { ref Tag(Textname, nil, nil, lrstr) };
	ms := ref Tag("prop", list of {Attr("xmlns", "DAV:")}, rl, nil);
	rx := ref Tag(Rootname, nil, list of {ms}, nil);
	return rx;
}

hdrlocktoks(h: ref Hdr): list of string
{
	# search both lock-token and if, so this retrieves
	# always the lock tokens for all methods implemented.
	o := h.getopt("lock-token");
	if(o == nil)
		o = h.getopt("if");
	if(o == nil)
		return nil;
	(nil, toks) := tokenize(o, "(<> \n\t\r)");
	lcks: list of string;
	for(; toks != nil; toks = tl toks){
		(s, lt) := splitstrr(hd toks, "opaquelocktoken:");
		if(s != nil)
			lcks = lt::lcks;
	}
	return lcks;
}

# rfc2518; 7, 8.10
slock(m: ref Msg, uri: string): ref Msg
{
	if(rdonly)
		return sno(m, uri);
	(xp, xe) := getxml(m);
	if(xe != nil){
		if(debug)
			fprint(stderr, "lock: %s\n", xe);
		return ref Msg(m.hdr.mkrep(Cbad, Sbad), nil);
	}
	if(xp != nil && debug > 1)
		fprint(stderr, "%s\n", xp.text());
	depth := mdepth(m);
	(kind, owner) := wantedlock(xp);
	tok: string;
	if(kind == Lrenew){
		toks := hdrlocktoks(m.hdr);
		if(toks != nil)
			(tok, owner) = renew(hd toks);
	} else if(owner == nil)
		return multists(m, uri, sprint("%d %s", Cbad, Sbad));
	else
		tok = canlock(uri, owner, depth, kind);
	if(tok == nil){
		sts := sprint("%d %s", Clocked, Slocked);
		return multists(m, uri, sts);
	}
	t := lockreply(depth, kind, owner, tok);
	rhdr := m.hdr.mkrep(Cok, Sok);
	rhdr.putopt("Content-Type", "text/xml; charset=\"utf-8\"");
	return ref Msg(rhdr, array of byte t.text());
}

sunlock(m: ref Msg, uri: string): ref Msg
{
	if(rdonly)
		return sno(m, uri);
	toks := hdrlocktoks(m.hdr);
	if(toks == nil)
		return ref Msg(m.hdr.mkrep(Cbad, Sbad), nil);
	for(; toks != nil; toks = tl toks)
		unlock(hd toks);
	return ref Msg(m.hdr.mkrep(Cnone, Snone), nil);
}

scopymove(m: ref Msg, uri: string, ismove: int): ref Msg
{
	if(rdonly)
		return sno(m, uri);
#if(!prefix("/tmp", uri))
#return ref Msg(m.hdr.mkrep(Cperm, "not outside /tmp"), nil);


	# surprise: locks may apply to files that do not exist.
	if(locked(uri, 0, hdrlocktoks(m.hdr)) != Lfree){
		if(debug)
			fprint(stderr, "put: %s: fail: locked\n", uri);
		return ref Msg(m.hdr.mkrep(Clocked, Slocked), nil);
	}
	ovwr := 1;
	ovwrs := m.hdr.getopt("overwrite");
	if(ovwrs == "F" || ovwrs == "f")
		ovwr = 0;
	duri := m.hdr.getopt("destination");
	if(duri != nil && prefix("http://", duri))
		(nil, duri)=splitl(duri[7:], "/");
	if(duri == nil)
		return ref Msg(m.hdr.mkrep(Cbad, Sbad), nil);
	duri = cleanname(duri);
#if(!prefix("/tmp", duri))
#return ref Msg(m.hdr.mkrep(Cperm, "not outside /tmp"), nil);
	(drc, dd) := stat(duri);
	if(drc >= 0)
		if(!ovwr){
			rhdr := m.hdr.mkrep(Cprecond, Sprecond);
			return ref Msg(rhdr, nil);
		} else if(fremove(ref dd, duri) < 0){
			rhdr := m.hdr.mkrep(Cperm, sprint("%r"));
			return ref Msg(rhdr, nil);
		}
	(src, sd) := stat(uri);
	erc := src;
	if(src >= 0)
		if(ismove && dirname(uri) == dirname(duri)){
			nd := sys->nulldir;
			nd.name = basename(duri, nil);
			erc = wstat(uri, nd);
		} else {
			if(fcopy(ref sd, uri, duri) < 0)
				erc = -1;
			if(ismove && fremove(ref sd, uri) < 0)
				erc = -1;
		}
	if(erc < 0)
		return ref Msg(m.hdr.mkrep(Cperm, sprint("%r")), nil);
	else if(drc >= 0)
		return ref Msg(m.hdr.mkrep(Cnone, Snone), nil);
	else
		return ref Msg(m.hdr.mkrep(Ccreated, Screated), nil);
}

fremove(d: ref Dir, f: string): int
{
	if(d.qid.qtype&QTDIR){
		(dirs, n) := readdir->init(f, readdir->NONE);
		if(n < 0)
			return -1;
		for(i := 0; i < n; i++)
			if(fremove(dirs[i], f+"/"+dirs[i].name) < 0)
				return -1;
		
	}
	return remove(f);
}

fcopy(d: ref Sys->Dir, sf: string, df: string): int
{
	if(d.qid.qtype&QTDIR){
		(dirs, n) := readdir->init(sf, readdir->NONE);
		if(n < 0)
			return -1;
		for(i := 0; i < n; i++){
			nm := dirs[i].name;
			if(fcopy(dirs[i], sf+"/"+nm, df+"/"+nm) < 0)
				return -1;
		}
		return 0;
	}
	buf := array[16*1024] of byte;
	sfd := open(sf, OREAD);
	dfd := create(df, OWRITE, d.mode);
	if(sfd == nil || dfd == nil)
		return -1;
	for(;;){
		nr := sys->read(sfd, buf, len buf);
		if(nr <= 0)
			return nr;
		if(sys->write(dfd, buf, nr) != nr)
			return -1;
	}
}

scopy(m: ref Msg, uri: string): ref Msg
{
	return scopymove(m, uri, 0);
}

smove(m: ref Msg, uri: string): ref Msg
{
	return scopymove(m, uri, 1);
}

run(m: ref Msg): ref Msg
{
	if(m == nil || m.hdr == nil)
		return nil;	# close reply

	pick h := m.hdr {
	Req =>
		for(i := 0; i < len svcs; i++)
			if(svcs[i].method == h.method)
				return svcs[i].handler(m, cleanname(h.uri));
		if(debug)
			fprint(stderr, "dav: unknown method %s\n", h.method);
	}
	return ref Msg(m.hdr.mkrep(Cbad, Sbad), nil);
}
