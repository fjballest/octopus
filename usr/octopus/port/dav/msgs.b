# Request parsing and processing for the dav server
# procesing for dav requests should go to a different module
# for xml, the xml module should be used.
implement Msgs;
include "sys.m";
	sys: Sys;
	fprint, FD, tokenize, sprint: import sys;
include "bufio.m";
	bufio: Bufio;
	OREAD, Iobuf: import bufio;
include "error.m";
	err: Error;
	checkload, stderr, error, kill: import err;
include "string.m";
	str: String;
	tolower, tobig, splitl, drop: import str;
include "msgs.m";
include "daytime.m";
include "readdir.m";
include "xml.m";
include "xmlutil.m";
include "svc.m";
include "names.m";
include "dlock.m";
include "dat.m";

Maxsz: con 64 * 1024 * 1024;

init(d: Dat)
{
	sys = d->sys;
	err = d->err;
	str = d->str;
	bufio = d->bufio;
}

chop(ln: string): string
{
	for(i := len ln-1; i >= 0; i--)
		if(ln[i] != ' ' && ln[i] != '\t' && ln[i] != '\n' && ln[i] != '\r')
			return ln[0:i+1];
	return "";
}

# from url with escapes to utf. (taken from httpd)
urlunesc(s : string): string
{
	c, n : int;
	t : string;
	for(i := 0;i<len s ; i++){
		c = int s[i];
		if(c == '%'){
			n = int s[i+1];
			if(n >= '0' && n <= '9')
				n = n - '0';
			else if(n >= 'A' && n <= 'F')
				n = n - 'A' + 10;
			else if(n >= 'a' && n <= 'f')
				n = n - 'a' + 10;
			else
				break;
			c = n;
			n = int s[i+2];
			if(n >= '0' && n <= '9')
				n = n - '0';
			else if(n >= 'A' && n <= 'F')
				n = n - 'A' + 10;
			else if(n >= 'a' && n <= 'f')
				n = n - 'a' + 10;
			else
				break;
			i += 2;
			c = c * 16 + n;
		}
	#	else if( c == '+' )
	#		c = ' ';
		t[len t] = c;
	}
	return t;
}

# read one option, perhaps multiple lines.
# return 0 when no more options are available (consuming the empty line)
# BUG: This does not fulfill rfc822/rfc1521 but it should.
Hdr.parseopt(h: self ref Hdr): int
{
	ln := h.iobin.gets('\n');
	if(ln == nil)
		return 0;
	ln = drop(ln, " \t\n\r");
	ln = chop(ln);
	if(len ln == 0){
		# an empty line terminates options
		return 0;
	}
	(opt, val) := splitl(ln, ":");
	opt = tolower(opt);
	if(val != nil)
		val = drop(val[1:], " \t\n\r");
	else
		val = "";
	for(;;){
		c := h.iobin.getc();
		if(c != ' ' || c != '\t'){
			h.iobin.ungetc();
			break;
		}
		nln := h.iobin.gets('\n');
		if(nln == nil)
			break;
		nln = drop(nln, " \t\n\r");
		nln = chop(nln);
		if(len nln > 0)
			val += " " + nln;
	}
	h.opts = (opt, val)::h.opts;
	return 1;
}

# setup hdr fields according to known options
Hdr.lookopt(h: self ref Hdr)
{
	(opt, val) := hd h.opts;
	case opt {
	"content-length" =>
		h.clen = big val;
	"transfer-encoding" =>
		h.enc = tolower(val);
	"connection" =>
		if(tolower(val) == "close")
			h.keep = 0;
	}
}

# read a full header and look at its options to fill a Hdr.
Hdr.parsereq(iobin, iobout: ref Iobuf, cdir: string): ref Hdr
{
	ln: string;
	do {
		ln = iobin.gets('\n');
		if(ln == nil){
			if(debug)
				fprint(stderr, "o/dav: EOF on %s: %r\n", cdir);
			return nil;
		}
		ln = drop(ln, " \t\n\r");
	} while(len ln == 0);
	(ntoks, toks) := tokenize(ln, " \t\n\r");
	if(ntoks < 3)
		return nil;
	hdr := ref Hdr.Req;
	hdr.iobin = iobin;
	hdr.iobout = iobout;
	hdr.cdir = cdir;
	hdr.clen = big 0;
	hdr.method = tolower(hd toks);
	hdr.uri = urlunesc(hd tl toks);
	hdr.proto = tolower(hd tl tl toks);
	hdr.keep = (hdr.proto != "HTTP/1.0");
	if(len toks > 3 && debug)
		fprint(stderr, "dav: extra header fields (%s...)\n", hd tl tl tl toks);
	while(hdr.parseopt())
		hdr.lookopt();
	return hdr;
}

Hdr.getopt(h: self ref Hdr, o: string): string
{
	for(ol := h.opts; ol != nil; ol = tl ol){
		(k, v) := hd ol;
		if(k == o)
			return v;
	}
	return nil;
}

Hdr.putopt(h: self ref Hdr, k, v: string)
{
	h.opts = (k, v)::h.opts;
}

Hdr.mkrep(h: self ref Hdr, c: int, msg: string): ref Hdr
{
	return ref Hdr.Rep(h.iobin, h.iobout, h.cdir, h.keep, big 0, nil, nil, "HTTP/1.1", c, msg);
}

Hdr.dump(h: self ref Hdr, verb: int)
{
	if(verb == 0)
		return;
	if(h == nil){
		fprint(stderr, "null hdr\n");
		return;
	}
	pick hh := h {
	Req =>
		fprint(stderr, "req: %s %s %s\t%s\n", hh.method, hh.uri, hh.proto, hh.cdir);
	Rep =>
		fprint(stderr, "rep: %s %d %s\t%s\n", hh.proto, hh.code, hh.msg, hh.cdir);
	}
	if(verb < 2)
		return;
	for(ol := h.opts; ol != nil; ol = tl ol){
		(k, v) := hd ol;
		fprint(stderr, "%s: %s\n", k, v);
	}
	fprint(stderr, "\n");
}

readall(iob: ref Iobuf): array of byte
{
	buf := array[4096] of byte;
	tot := 0;
	for(;;){
		nr := iob.read(buf[tot:], len buf - tot);
		if(nr == 0)
			return buf[:tot];
		if(nr < 0)
			return nil;
		tot += nr;
		if(tot == len buf){
			nbuf := array[len buf + 4096] of byte;
			nbuf[0:] = buf;
			buf = nbuf;
		}
		if(tot >= Maxsz){	# enough
			fprint(stderr, "dav: truncating body\n");
			return buf[:tot];
		}
	}
}

readn(iob: ref Iobuf, cnt: big): array of byte
{
	if(cnt <= big 0)
		return nil;
	if(cnt >= big Maxsz){
		cnt = big Maxsz;
		fprint(stderr, "dav: chunk too large: truncating body\n");
	}
	buf := array[int cnt] of byte;
	tot := 0;
	do{
		nr := iob.read(buf[tot:], len buf - tot);
		if(nr == 0)
			return buf[:tot];
		if(nr < 0)
			return nil;
		tot += nr;
	} while (tot < int cnt);
	return buf;
}

readchunk(iob: ref Iobuf): array of byte
{
	s: string;
	do {
		s = iob.gets('\n');
		if(s == nil)
			return nil;
		s = drop(s, " \t\n\r");
	}while(s == nil);
	(cnt, nil) := tobig(s, 16);
	return readn(iob, cnt);
}

readchunks(iob: ref Iobuf): array of byte
{
	b := array[0] of byte;
	while((c := readchunk(iob)) != nil){
		nb := array[len b + len c] of byte;
		nb[0:] = b;
		nb[len b:] = c;
		b = nb;
	}
	return b;
}

Msg.getreq(iobin, iobout: ref Iobuf, cdir: string): ref Msg
{
	hdr := Hdr.parsereq(iobin, iobout, cdir);
	if(hdr == nil)
		return nil;
	if(hdr.enc != nil && hdr.clen == big 0){
		# request with body but no length known: read till eof.
		hdr.keep = 0;
		hdr.clen = big -1;
	}
	body: array of byte;
	if(hdr.enc == "chunked")
		body = readchunks(hdr.iobin);
	else if(hdr.clen < big 0)
		body = readall(hdr.iobin);
	else if(hdr.clen > big 0)
		body = readn(hdr.iobin, hdr.clen);
	if(hdr.clen != big 0 && body == nil){
		if(debug)
			fprint(stderr, "dav: reading body: %r\n");
		return nil;
	}
	return ref Msg(hdr, body);
}

Msg.putrep(r: self ref Msg): int
{
	bio := r.hdr.iobout;
	s := "";
	pick h := r.hdr {
	Req =>
		fprint(stderr, "putrep called with request\n");
		return -1;
	Rep =>
		s += sprint("%s %d %s\r\n", h.proto, h.code, h.msg);
	}
	if(r.hdr.clen == big 0)
		r.hdr.clen = big len r.body;
	r.hdr.putopt("Content-length", sprint("%bd", r.hdr.clen));
	for(ol := r.hdr.opts; ol != nil; ol = tl ol){
		(k, v) := hd ol;
		s += sprint("%s: %s\r\n", k, v);
	}
	r.hdr.dump(debug);
	if(bio.puts(s + "\r\n") < 0)
		return -1;
	if(len r.body > 0)
		if (bio.write(r.body, len r.body) != len r.body)
			return -1;
	if(bio.flush() < 0)
		return -1;
	if(debug > 1 && len r.body > 0)
		fprint(stderr, "body: [%s]\n", string r.body);
	return 0;
}
