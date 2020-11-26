implement Nop;
#
# 2nd version of the Op protocol.
# The same server is meant to serve multiple clients, and use
# leasing to maintain strict coherence.
#

include "sys.m";
	sys: Sys;
	fprint, fildes, print, nulldir, sprint, FD,
	werrstr, DMDIR, DMAPPEND, DMEXCL, DMAUTH, DMTMP, Dir, Qid: import sys;
include "draw.m";
include "blks.m";
	blks: Blks;
	Blk, g32, g16, g64, p16, p32, p64, gstring,
	pstring, utflen, dtxt: import blks;
include "nop.m";

QID:	con BIT8SZ+BIT32SZ+BIT64SZ;
HDR:	con BIT32SZ+BIT8SZ+BIT16SZ;	# size[4] type tag[2]
STATFIXLEN:	con 2*BIT16SZ+QIDSZ+8*BIT32SZ+BIT64SZ;	

stderr: ref FD;

init(s: Sys, b: Blks)
{
	sys = s;
	blks = b;
	stderr = fildes(2);
}

packdirsize(d: ref Dir): int
{
	if(d == nil)
		return BIT16SZ;
	return STATFIXLEN+utflen(d.name)+utflen(d.uid)+utflen(d.gid)+utflen(d.muid);
}

packdir(a: array of byte, o: int, f: ref Dir): int
{
	ds := packdirsize(f);
	if(len a < o + ds)
		return -1;
	o = p16(a, o, (ds-BIT16SZ));
	if(f != nil){
		o = p16(a, o, f.dtype);
		o = p32(a, o, f.dev);
		o = pqid(a, o, f.qid);
		o = p32(a, o, f.mode);
		o = p32(a, o, f.atime);
		o = p32(a, o, f.mtime);
		o = p64(a, o, big f.length);
		o = pstring(a, o, f.name);
		o = pstring(a, o, f.uid);
		o = pstring(a, o, f.gid);
		o = pstring(a, o, f.muid);
	}
	return o;
}

pqid(a: array of byte, o: int, q: Qid): int
{
	a[o] = byte q.qtype; o++;
	o = p32(a, o, q.vers);
	o = p64(a, o, q.path);
	return o;
}

unpackdir(a: array of byte, o: int): (int, ref Dir)
{

	if(len a < BIT16SZ)
		return (o, nil);
	sz := g16(a, o) + BIT16SZ;	o += BIT16SZ;
	if(sz == BIT16SZ)
		return(o, nil);		# nil dir packed
	if(len a < o+sz)
		return (o-BIT16SZ, nil);	# error
	if(len a < STATFIXLEN)
		return (o-BIT16SZ, nil);
	dir:= ref Dir;
	dir.dtype = g16(a, o);		o += BIT16SZ;
	dir.dev = g32(a, o);		o += BIT32SZ;
	dir.qid = gqid(a, o);		o += QID;
	dir.mode = g32(a, o);		o += BIT32SZ;
	dir.atime = g32(a, o);		o += BIT32SZ;
	dir.mtime = g32(a, o);		o += BIT32SZ;
	dir.length = g64(a, o);		o += BIT64SZ;
	(dir.name, o) = gstring(a, o);
	(dir.uid, o) = gstring(a, o);
	(dir.gid, o) = gstring(a, o);
	(dir.muid, o) = gstring(a, o);
	return (o, dir);
}

gqid(f: array of byte, o: int): Qid
{
	qtype := int f[o];	o++;
	vers := g32(f, o);	o += BIT32SZ;
	path := g64(f, o);	o += BIT64SZ;
	return Qid(path, vers, qtype);
}

ttag2type := array[] of {
	tagof Tmsg.Attach => Tattach,
	tagof Tmsg.Flush => Tflush,
	tagof Tmsg.Put => Tput,
	tagof Tmsg.Get => Tget,
	tagof Tmsg.Clunk => Tclunk,
	tagof Tmsg.Remove => Tremove,
	tagof Tmsg.Inval => Tinval
};

Tmsg.mtype(t: self ref Tmsg): int
{
	return ttag2type[tagof t];
}

Tmsg.packedsize(t: self ref Tmsg): int
{
	mtype := ttag2type[tagof t];
	if(mtype <= 0)
		return 0;
	ml := HDR;
	pick m := t {
	Attach =>
		ml += BIT32SZ + utflen(m.version);
		ml += BIT32SZ + utflen(m.uname);
		ml += BIT32SZ + utflen(m.path);
	Flush =>
		ml += BIT16SZ;
	Put =>
		ml += BIT32SZ + utflen(m.path);
		ml += BIT16SZ;	# fd
		ml += BIT16SZ;	# mode
		ml += packdirsize(m.dir);
		ml += BIT64SZ;	# offset
		ml += BIT32SZ;	# len m.data
		ml += len m.data;
	Get =>
		ml += BIT32SZ + utflen(m.path);
		ml += BIT16SZ;	# fd
		ml += BIT16SZ;	# mode
		ml += BIT16SZ;	# mcount
		ml += BIT64SZ;	# offset
		ml += BIT32SZ;	# count
	Clunk =>
		ml += BIT16SZ;	# fd
	Remove =>
		ml += BIT32SZ + utflen(m.path);
		ml += BIT16SZ;	# fd
	Inval =>
		ml += 0;
	}
	return ml;
}

Tmsg.pack(t: self ref Tmsg): array of byte
{
	if(t == nil)
		return nil;
	ds := t.packedsize();
	if(ds <= 0)
		return nil;
	d := array[ds] of byte;
	p32(d, 0, ds);		o := BIT32SZ;
	d[o] = byte ttag2type[tagof t];	o++;
	p16(d, o, t.tag);		o += BIT16SZ;
	pick m := t {
	Attach =>
		o = pstring(d, o, m.version);
		o = pstring(d, o, m.uname);
		pstring(d, o, m.path);
	Flush =>
		p16(d, o, m.oldtag);
	Put =>
		o = pstring(d, o, m.path);
		p16(d, o, m.fd);	o += BIT16SZ;
		p16(d, o, m.mode);	o += BIT16SZ;
		o = packdir(d, o, m.dir);
		p64(d, o, m.offset);	o += BIT64SZ;
		p32(d, o, len m.data); 	o += BIT32SZ;
		if(len m.data > 0)
			d[o:] = m.data;
	Get =>
		o = pstring(d, o, m.path);
		p16(d, o, m.fd);	o += BIT16SZ;
		p16(d, o, m.mode);	o += BIT16SZ;
		p16(d, o, m.mcount);	o += BIT16SZ;
		p64(d, o, m.offset);	o += BIT64SZ;
		p32(d, o, m.count);
	Clunk =>
		p16(d, o, m.fd);
	Remove =>
		o = pstring(d, o, m.path);
		p16(d, o, m.fd);
	Inval =>
		;
	* =>
		fprint(stderr, "nop: pack: bad tag: %d", tagof t);
	}
	return d;
}

Tmsg.unpack(f: array of byte): (int, ref Tmsg)
{
	version, path, uname: string;

	if(len f < HDR)
		return (0, nil);
	size := g32(f, 0);
	if(len f != size){
		if(len f < size)
			return (0, nil);	# need more data
		f = f[0:size];			# trim to exact length
	}
	o := BIT32SZ;
	mtype := int f[o];
	o++;
	if(mtype >= Tmax || (mtype&1) == 0 || mtype <= 0){
		werrstr(sprint("bad mtype %d", mtype));
		fprint(stderr, "nop: unpack: %r\n");
		return (-1, nil);
	}
	tag := g16(f, o);
	o += BIT16SZ;
	case mtype {
	Tattach =>
		(version, o) = gstring(f, o);
		(uname, o) = gstring(f, o);
		(path, o) = gstring(f, o);
		if(version == nil || uname == nil || path == nil){
			werrstr("short tattach msg");
			fprint(stderr, "nop: unpack: %r\n");
			return (-1, nil);
		}
		return (o, ref Tmsg.Attach(tag, version, uname, path));
	Tflush =>
		if(len f < o + BIT16SZ){
			werrstr("short tflush msg");
			fprint(stderr, "nop: unpack: %r\n");
			return (-1, nil);
		}
		oldtag := g16(f, o);	o += BIT16SZ;
		return (o, ref Tmsg.Flush(tag, oldtag));
	Tput =>
		if(len f < o + BIT32SZ + 2*BIT16SZ){
			werrstr("short tput msg");
			fprint(stderr, "nop: unpack: %r\n");
			return (-1, nil);
		}
		(path, o) = gstring(f, o); 
		fd := g16(f, o);	o+= BIT16SZ;
		mode := g16(f, o);	o+= BIT16SZ;
		(o1, dir) := unpackdir(f, o); o = o1;
		if(len f < o + BIT16SZ + BIT32SZ){
			werrstr("short tput data");
			fprint(stderr, "nop: unpack: %r\n");
			return (-1, nil);
		}
		offset := g64(f, o);	o += BIT64SZ;
		count := g32(f, o);	o += BIT32SZ;
		data := f[o:o+count];	o += count;
		return (o, ref Tmsg.Put(tag, path, fd, mode, dir, offset, data));
	Tget =>
		(path, o) = gstring(f, o); 
		if(path == nil || len f < o + BIT16SZ*3 + BIT64SZ + BIT32SZ){
			werrstr("short tget msg");
			fprint(stderr, "nop: unpack: %r\n");
			return (-1, nil);
		}
		fd := g16(f, o);	o += BIT16SZ;
		mode := g16(f, o);	o += BIT16SZ;
		mcount := g16(f, o);	o += BIT16SZ;
		offset := g64(f, o);	o += BIT64SZ;
		count := g32(f, o);	o += BIT32SZ;
		return (o, ref Tmsg.Get(tag, path, fd, mode, mcount, offset, count));
	Tclunk =>
		if(len f < o + BIT16SZ){
			werrstr("short tclunk msg");
			fprint(stderr, "nop: unpack: %r\n");
			return (-1, nil);
		}
		fd := g16(f, o);	o += BIT16SZ;
		return (o, ref Tmsg.Clunk(tag, fd));
	Tremove =>
		if(len f < o + BIT32SZ + BIT16SZ){
			werrstr("short tclunk msg");
			fprint(stderr, "nop: unpack: %r\n");
			return (-1, nil);
		}
		(path, o) = gstring(f, o);
		fd := g16(f, o);
		return (o, ref Tmsg.Remove(tag, path, fd));
	Tinval =>
		return(o, ref Tmsg.Inval(tag));
	* =>
		fprint(stderr, "nop: unpack: bad tmsg type %d\n", mtype);
	}
	return (-1, nil);		# illegal
}

tmsgname := array[] of {
	tagof Tmsg.Attach => "attach",
	tagof Tmsg.Flush => "flush",
	tagof Tmsg.Put => "put",
	tagof Tmsg.Get => "get",
	tagof Tmsg.Clunk => "clunk",
	tagof Tmsg.Remove => "remove",
	tagof Tmsg.Inval => "inval",
};

Tmsg.text(t: self ref Tmsg): string
{
	if(t == nil)
		return "nil";
	s := sprint("T%s %ud", tmsgname[tagof t], t.tag);
	pick m:= t {
	Attach =>
		return s + sprint(" \"%s\" \"%s\" \"%s\"", m.version, m.uname, m.path);
	Flush =>
		return s + sprint(" %ud", m.oldtag);
	Put =>
		s += sprint("\"%s\" fd=%d %s", m.path, m.fd, mode2text(m.mode));
		n := len m.data;
		s += sprint("  o=%bd  c=%ud", m.offset, n);
		if(n > 0)
			s += " \"" + dtxt(string m.data) + "\"";
		if(m.dir != nil)
			s += "\n\t" + dir2text(m.dir);
		return s ;
	Get =>
		s += sprint(" \"%s\" fd=%d %s", m.path, m.fd, mode2text(m.mode));
		s += sprint("  mc=%d o=%bd  c=%ud", m.mcount, m.offset, m.count);
		return s ;
	Clunk =>
		return s + sprint(" fd=%d", m.fd);
	Remove =>
		return s + sprint(" \"%s\" fd=%d", m.path, m.fd);
	Inval =>
		return s;
	* =>
		return s + " BUG: UNKNOWN MESSAGE";
	}
	return nil;
}

Tmsg.bread(b: ref Blk): ref Tmsg
{
	bl := b.blen();
	if(bl < BIT32SZ)
		return nil;
	sz := g32(b.data, b.rp);
	if(bl < sz)
		return nil;
	mb := b.get(sz);
	(nil, m) := Tmsg.unpack(mb);
	return m;
}

rtag2type := array[] of {
	tagof Rmsg.Error	=> Rerror,
	tagof Rmsg.Attach	=> Rattach,
	tagof Rmsg.Flush	=> Rflush,
	tagof Rmsg.Put	=> Rput,
	tagof Rmsg.Get	=> Rget,
	tagof Rmsg.Clunk	=> Rclunk,
	tagof Rmsg.Remove	=> Rremove,
	tagof Rmsg.Inval 	=> Rinval,
};

Rmsg.mtype(r: self ref Rmsg): int
{
	return rtag2type[tagof r];
}

Rmsg.packedsize(r: self ref Rmsg): int
{
	mtype := rtag2type[tagof r];
	if(mtype <= 0)
		return 0;
	ml := HDR;
	pick m := r {
	Error =>
		ml += BIT32SZ + utflen(m.ename);
	Attach =>
		ml += BIT32SZ + utflen(m.version);
	Put =>
		ml += BIT16SZ;	# fd
		ml += BIT32SZ;	# count
		ml += QID;
		ml += BIT32SZ;	# mtime
	Get =>
		ml += BIT16SZ;	# fd
		ml += BIT16SZ;	# mode
		ml += BIT64SZ;	# offset
		ml += packdirsize(m.dir);
		ml += BIT32SZ;	# len m.data
		ml += len m.data;
	Flush or Clunk or Remove =>
	Inval =>
		ml += BIT32SZ+utflen(m.paths);
	}
	return ml;
}

Rmsg.pack(r: self ref Rmsg): array of byte
{
	if(r == nil)
		return nil;
	ps := r.packedsize();
	if(ps <= 0)
		return nil;
	d := array[ps] of byte;
	p32(d, 0, ps);	o := BIT32SZ;
	d[o] = byte rtag2type[tagof r]; o++;
	p16(d, o, r.tag);	o += BIT16SZ;
	if(o != HDR){
		fprint(stderr, "Rmsg.pack: bug");
		return nil;
	}
	pick m := r {
	Error =>
		pstring(d, o, m.ename);
	Attach =>
		pstring(d, o, m.version);
	Put =>
		p16(d, o, m.fd);	o += BIT16SZ;
		p32(d, o, m.count);	o += BIT32SZ;
		pqid(d, o, m.qid);	o += QID;
		p32(d, o, m.mtime);
	Get =>
		p16(d, o, m.fd);	o += BIT16SZ;
		p16(d, o, m.mode);	o += BIT16SZ;
		p64(d, o, m.offset);	o += BIT64SZ;
		o = packdir(d, o, m.dir);
		p32(d, o, len m.data); 	o += BIT32SZ;
		d[o:] = m.data;	o += len m.data;
	Flush or Clunk or Remove =>
	Inval =>
		o = pstring(d, o, m.paths);
	* =>
		fprint(stderr, "nop: pack: bad tag: %d", tagof r);
	}
	return d;
}

Rmsg.unpack(f: array of byte): (int, ref Rmsg)
{
	# not enough data for a message is not considered
	# an error. Perhaps more data has to be read. We just
	# return nil.
	if(len f < HDR)
		return (0, nil);
	size := g32(f, 0);	o := BIT32SZ;
	if(len f != size){
		if(len f < size)
			return (0, nil);
		f = f[0:size];
	}
	mtype := int f[o];	o++;
	if(mtype >= Tmax || (mtype&1) != 0 || mtype <= 0){
		werrstr(sprint("bad mtype %d", mtype));
		fprint(stderr, "nop: unpack: %r\n");
		return (-1, nil);
	}
	tag := g16(f, o);	o += BIT16SZ;
	if(o != HDR){
		werrstr("bug: o != HDR");
		fprint(stderr, "nop: unpack: %r\n");
		return (-1, nil);
	}
	case mtype {
	Rerror =>
		if(len f < o + BIT32SZ){
			werrstr("short Rerror msg");
			fprint(stderr, "nop: unpack: %r\n");
			return (-1, nil);
		}
		(ename, o1) := gstring(f, o);
		return (o1, ref Rmsg.Error(tag, ename));
	Rattach =>
		if(len f < o + BIT32SZ){
			werrstr("short Rattach msg");
			fprint(stderr, "nop: unpack: %r\n");
			return (-1, nil);
		}
		(version, o1) := gstring(f, o);
		return (o1, ref Rmsg.Attach(tag, version));
	Rput =>
		if(len f < o + BIT16SZ + BIT32SZ + QID + BIT32SZ){
			werrstr("short rput");
			fprint(stderr, "nop: unpack: %r\n");
			return (-1, nil);
		}
		fd := g16(f, o);	o += BIT16SZ;
		count := g32(f, o);	o += BIT32SZ;
		qid := gqid(f, o);	o += QID;
		mtime := g32(f, o);	o += BIT32SZ;
		return (o, ref Rmsg.Put(tag, fd, count, qid, mtime));
	Rget =>
		if(len f < o + BIT16SZ + BIT16SZ + BIT64SZ + BIT16SZ){
			werrstr("short rget");
			fprint(stderr, "nop: unpack: %r\n");
			return (-1, nil);
		}
		fd := g16(f, o);	o += BIT16SZ;
		mode := g16(f, o);	o += BIT16SZ;
		offset := g64(f, o);	o += BIT64SZ;
		(o1, dir) := unpackdir(f, o); o = o1;
		if(len f < o + BIT32SZ){
			werrstr("short rget msg");
			fprint(stderr, "nop: unpack: %r\n");
			return (-1, nil);
		}
		count := g32(f, o);	o+= BIT32SZ;
		if(len f < o + count){
			werrstr("short rget data");
			fprint(stderr, "nop: unpack: %r\n");
			return (-1, nil);
		}
		data := f[o:o+count]; o+= count;
		return (o, ref Rmsg.Get(tag, fd, mode, offset, dir, data));
	Rflush =>
		return (o, ref Rmsg.Flush(tag));
	Rclunk =>
		return (o, ref Rmsg.Clunk(tag));
	Rremove =>
		return (o, ref Rmsg.Remove(tag));
	Rinval =>
		paths: string;
		if(len f < o + BIT32SZ){
			werrstr("short rinval");
			fprint(stderr, "nop: unpack: %r\n");
			return (-1, nil);
		}
		(paths, o) = gstring(f, o);
		return (o, ref Rmsg.Inval(tag, paths));
	* =>
		werrstr(sprint("bad type %d\n", mtype));
		fprint(stderr, "nop: unpack: %r\n");
	}
	return (-1, nil);
}

rmsgname := array[] of {
	tagof Rmsg.Error => "error",
	tagof Rmsg.Attach => "attach",
	tagof Rmsg.Flush => "flush",
	tagof Rmsg.Put => "put",
	tagof Rmsg.Get => "get",
	tagof Rmsg.Clunk => "clunk",
	tagof Rmsg.Remove => "remove",
	tagof Rmsg.Inval => "inval",
};

Rmsg.text(r: self ref Rmsg): string
{
	if(r == nil)
		return "nil";
	s := sprint("R%s %ud", rmsgname[tagof r], r.tag);
	pick m:= r {
	Error =>
		return s + sprint(" \"%s\"", m.ename);
	Attach =>
		return s + sprint(" \"%s\"", m.version);
	Put =>
		s += sprint("  fd=%d %d  %s %d", m.fd,
			m.count, qid2text(m.qid), m.mtime);
		return s ;
	Get =>
		s += sprint(" fd=%d %s", m.fd,
			mode2text(m.mode));
		n := len m.data;
		s += sprint(" %bd %ud", m.offset, n);
		if(n > 0)
			s += " \"" + dtxt(string m.data) + "\"";
		if(m.dir != nil)
			s += "\n\t" + dir2text(m.dir);
		return s ;
	Clunk =>
		return s;
	Flush =>
		return s;
	Remove =>
		return s;
	Inval =>
		s += sprint(" \"%s\"", m.paths);
		return s;
	* =>
		return s + " ILLEGAL";
	}
}

Rmsg.bread(b: ref Blk): ref Rmsg
{
	bl := b.blen();
	if(bl < BIT32SZ)
		return nil;
	sz := g32(b.data, b.rp);
	if(bl < sz)
		return nil;
	mb := b.get(sz);
	(nil, m) := Rmsg.unpack(mb);
	return m;
}

dir2text(d: ref Dir): string
{
	if(d == nil)
		return "nulldir";

	return sprint("[\"%s\" \"%s\" \"%s\" %s 8r%uo %d %d %bd]",
		d.name, d.uid, d.gid, qid2text(d.qid), d.mode,
		d.atime, d.mtime, d.length);
}

qid2text(q: Qid): string
{
	path := int q.path;
	flags := "";
	if(path&DMDIR)
		flags[len flags] = 'd';
	if(path&DMAPPEND)
		flags[len flags] = 'a';
	if(path&DMEXCL)
		flags[len flags] = 'x';
	if(path&DMAUTH)
		flags[len flags] = '$';
	if(path&DMTMP)
		flags[len flags] = 't';
	if(flags != "")
		flags[len flags] = ':';
	bpath := big path & big ~(DMDIR|DMAPPEND|DMEXCL|DMAUTH|DMTMP);
	tflags := "";
	if(q.qtype&QTDIR)
		tflags[len tflags] = 'd';
	else
		tflags[len tflags] = 'f';
	if(q.qtype&QTAPPEND)
		tflags[len tflags] = 'a';
	if(q.qtype&QTEXCL)
		tflags[len tflags] = 't';
	if(q.qtype&QTAUTH)
		tflags[len tflags] = '$';
	if(q.qtype&QTTMP)
		tflags[len tflags] = 't';
	if(q.qtype&QTCACHE)
		tflags[len tflags] = 'c';
	qtype := q.qtype & ~(QTDIR|QTAPPEND|QTEXCL|QTAUTH|QTTMP|QTCACHE);
	if(qtype != 0)
		tflags += sprint(":16r%ux", q.qtype);
	return sprint("%s16r%ubx:%d:%s", flags, bpath, q.vers, tflags);
}

modec(m: int, f: int, c: int): int
{
	if(m&f)
		return c;
	else
		return '-';
}

mode2text(m: int) : string
{
	s := "";
	s[len s] = modec(m,  OCREATE, 'c');
	s[len s] = modec(m,  OEOF, 'e');
	s[len s] = modec(m,  OREMOVEC, 'd');
	case(m&OMODE){
	ONONE =>
		s += "--";
	OREAD =>
		s += "r-";
	OWRITE =>
		s += "-w";
	ORDWR =>
		s += "rw";
	}
	return s;
}

