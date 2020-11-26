implement Op;

#
# A little bit dirty. But it was easier to follow (and borrow) the code
# in styx.b than it was writing this from scratch.
#

# BUG: must change the protocol. Both Tput and Tget must accept either paths or fds
# a Tput/Tget with an invalid fd must use the path and reopen the file, reporting a new fd
# back to the client. Old fds must be closed.

include "sys.m";
sys: Sys;
	fprint, fildes, print, nulldir, sprint , Qid: import sys;
include "draw.m";
include "io.m";
	io: Io;
	readn: import io;
include "op.m";

STR: con BIT16SZ;		# string length
TAG: con BIT16SZ;
QID: con BIT8SZ+BIT32SZ+BIT64SZ;
LEN: con BIT16SZ;		# stat and qid array lengths
COUNT: con BIT32SZ;
OFFSET: con BIT64SZ;
H: con BIT32SZ+BIT8SZ+BIT16SZ;	# minimum header length: size[4] type tag[2]

init()
{
	sys = load Sys Sys->PATH;
	io = load Io Io->PATH;
	if(io == nil)
		fprint(fildes(2), "op: can't load %s: %r\n", Io->PATH);
}

utflen(s: string): int
{
	# the domain is 16-bit unicode only, which is all that Inferno now implements
	n := l := len s;
	for(i:=0; i<l; i++)
		if((c := s[i]) > 16r7F){
			n++;
			if(c > 16r7FF)
				n++;
		}
	return n;
}

packdirsize(d: Sys->Dir): int
{
	return STATFIXLEN+utflen(d.name)+utflen(d.uid)+utflen(d.gid)+utflen(d.muid);
}

packdir(f: Sys->Dir): array of byte
{
	ds := packdirsize(f);
	a := array[ds] of byte;
	# size[2]
	a[0] = byte (ds-LEN);
	a[1] = byte ((ds-LEN)>>8);
	# type[2]
	a[2] = byte f.dtype;
	a[3] = byte (f.dtype>>8);
	# dev[4]
	a[4] = byte f.dev;
	a[5] = byte (f.dev>>8);
	a[6] = byte (f.dev>>16);
	a[7] = byte (f.dev>>24);
	# qid.type[1]
	# qid.vers[4]
	# qid.path[8]
	pqid(a, 8, f.qid);
	# mode[4]
	a[21] = byte f.mode;
	a[22] = byte (f.mode>>8);
	a[23] = byte (f.mode>>16);
	a[24] = byte (f.mode>>24);
	# atime[4]
	a[25] = byte f.atime;
	a[26] = byte (f.atime>>8);
	a[27] = byte (f.atime>>16);
	a[28] = byte (f.atime>>24);
	# mtime[4]
	a[29] = byte f.mtime;
	a[30] = byte (f.mtime>>8);
	a[31] = byte (f.mtime>>16);
	a[32] = byte (f.mtime>>24);
	# length[8]
	p64(a, 33, big f.length);
	# name[s]
	i := pstring(a, 33+BIT64SZ, f.name);
	i = pstring(a, i, f.uid);
	i = pstring(a, i, f.gid);
	i = pstring(a, i, f.muid);
	if(i != len a)
		raise "assertion: Styx->packdir: bad count";	# can't happen unless packedsize is wrong
	return a;
}

pqid(a: array of byte, o: int, q: Sys->Qid): int
{
	a[o] = byte q.qtype;
	v := q.vers;
	a[o+1] = byte v;
	a[o+2] = byte (v>>8);
	a[o+3] = byte (v>>16);
	a[o+4] = byte (v>>24);
	v = int q.path;
	a[o+5] = byte v;
	a[o+6] = byte (v>>8);
	a[o+7] = byte (v>>16);
	a[o+8] = byte (v>>24);
	v = int (q.path >> 32);
	a[o+9] = byte v;
	a[o+10] = byte (v>>8);
	a[o+11] = byte (v>>16);
	a[o+12] = byte (v>>24);
	return o+QID;
}

pstring(a: array of byte, o: int, s: string): int
{
	sa := array of byte s;	# could do conversion ourselves
	n := len sa;
	a[o] = byte n;
	a[o+1] = byte (n>>8);
	a[o+2:] = sa;
	return o+LEN+n;
}

p16(a: array of byte, o: int, v: int): int
{
	a[o] = byte v;
	a[o+1] = byte (v>>8);
	return o+BIT16SZ;
}

p32(a: array of byte, o: int, v: int): int
{
	a[o] = byte v;
	a[o+1] = byte (v>>8);
	a[o+2] = byte (v>>16);
	a[o+3] = byte (v>>24);
	return o+BIT32SZ;
}

p64(a: array of byte, o: int, b: big): int
{
	i := int b;
	a[o] = byte i;
	a[o+1] = byte (i>>8);
	a[o+2] = byte (i>>16);
	a[o+3] = byte (i>>24);
	i = int (b>>32);
	a[o+4] = byte i;
	a[o+5] = byte (i>>8);
	a[o+6] = byte (i>>16);
	a[o+7] = byte (i>>24);
	return o+BIT64SZ;
}

unpackdir(a: array of byte): (int, Sys->Dir)
{
	dir: Sys->Dir;

	if(len a < STATFIXLEN)
		return (0, dir);
	# size[2]
	sz := ((int a[1] << 8) | int a[0])+LEN;	# bytes this packed dir should occupy
	if(len a < sz)
		return (0, dir);
	# type[2]
	dir.dtype = (int a[3]<<8) | int a[2];
	# dev[4]
	dir.dev = (((((int a[7] << 8) | int a[6]) << 8) | int a[5]) << 8) | int a[4];
	# qid.type[1]
	# qid.vers[4]
	# qid.path[8]
	dir.qid = gqid(a, 8);
	# mode[4]
	dir.mode = (((((int a[24] << 8) | int a[23]) << 8) | int a[22]) << 8) | int a[21];
	# atime[4]
	dir.atime = (((((int a[28] << 8) | int a[27]) << 8) | int a[26]) << 8) | int a[25];
	# mtime[4]
	dir.mtime = (((((int a[32] << 8) | int a[31]) << 8) | int a[30]) << 8) | int a[29];
	# length[8]
	v0 := (((((int a[36] << 8) | int a[35]) << 8) | int a[34]) << 8) | int a[33];
	v1 := (((((int a[40] << 8) | int a[39]) << 8) | int a[38]) << 8) | int a[37];
	dir.length = (big v1 << 32) | (big v0 & 16rFFFFFFFF);
	# name[s], uid[s], gid[s], muid[s]
	i: int;
	(dir.name, i) = gstring(a, 41);
	(dir.uid, i) = gstring(a, i);
	(dir.gid, i) = gstring(a, i);
	(dir.muid, i) = gstring(a, i);
	if(i != sz)
		return (0, dir);
	return (i, dir);
}

gqid(f: array of byte, i: int): Sys->Qid
{
	qtype := int f[i];
	vers := (((((int f[i+4] << 8) | int f[i+3]) << 8) | int f[i+2]) << 8) | int f[i+1];
	i += BIT8SZ+BIT32SZ;
	path0 := (((((int f[i+3] << 8) | int f[i+2]) << 8) | int f[i+1]) << 8) | int f[i];
	i += BIT32SZ;
	path1 := (((((int f[i+3] << 8) | int f[i+2]) << 8) | int f[i+1]) << 8) | int f[i];
	path := (big path1 << 32) | (big path0 & 16rFFFFFFFF);
	return (path, vers, qtype);
}

g32(f: array of byte, i: int): int
{
	r := (((((int f[i+3] << 8) | int f[i+2]) << 8) | int f[i+1]) << 8) | int f[i];
	if(r == int 16rFFFFFFFF)
		r = ~0;
	return r;
}

g16(f: array of byte, i: int): int
{
	r := (( int f[i+1]) << 8) | int f[i];
	if(r == int 16rFFFF)
		r = ~0;
	return r;
}

g64(f: array of byte, i: int): big
{
	b0 := (((((int f[i+3] << 8) | int f[i+2]) << 8) | int f[i+1]) << 8) | int f[i];
	b1 := (((((int f[i+7] << 8) | int f[i+6]) << 8) | int f[i+5]) << 8) | int f[i+4];
	return (big b1 << 32) | (big b0 & 16rFFFFFFFF);
}

gstring(a: array of byte, o: int): (string, int)
{
	if(o < 0 || o+STR > len a)
		return (nil, -1);
	l := (int a[o+1] << 8) | int a[o];
	o += STR;
	e := o+l;
	if(e > len a)
		return (nil, -1);
	return (string a[o:e], e);
}

ttag2type := array[] of {
	tagof Tmsg.Readerror => 0,
	tagof Tmsg.Attach => Tattach,
	tagof Tmsg.Flush => Tflush,
	tagof Tmsg.Put => Tput,
	tagof Tmsg.Get => Tget,
	tagof Tmsg.Remove => Tremove};

Tmsg.mtype(t: self ref Tmsg): int
{
	return ttag2type[tagof t];
}

Tmsg.packedsize(t: self ref Tmsg): int
{
	mtype := ttag2type[tagof t];
	if(mtype <= 0)
		return 0;
	ml := H;
	pick m := t {
	Attach =>
		ml += STR + utflen(m.uname);
		ml += STR + utflen(m.path);
	Flush =>
		ml += TAG;
	Put =>
		ml += STR + utflen(m.path);
		ml += BIT16SZ;
		ml += BIT16SZ;
		if(m.mode & OSTAT)
			ml += packdirsize(m.stat);
		ml += OFFSET;
		ml += COUNT;
		ml += len m.data;
	Get =>
		ml += STR + utflen(m.path);
		ml += BIT16SZ;
		ml += BIT16SZ;
		ml += BIT16SZ;
		ml += OFFSET;
		ml += COUNT;
	Remove =>
		ml += STR + utflen(m.path);
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
	d[0] = byte ds;
	d[1] = byte (ds>>8);
	d[2] = byte (ds>>16);
	d[3] = byte (ds>>24);
	d[4] = byte ttag2type[tagof t];
	d[5] = byte t.tag;
	d[6] = byte (t.tag >> 8);
	pick m := t {
	Attach =>
		o := pstring(d, H, m.uname);
		pstring(d, o, m.path);
	Flush =>
		v := m.oldtag;
		d[H] = byte v;
		d[H+1] = byte (v>>8);
	Put =>
		o := pstring(d, H, m.path);
		p16(d, o, m.fd); o += BIT16SZ;
		p16(d, o, m.mode); o += BIT16SZ;
		if(m.mode&OSTAT){
			stat := packdir(m.stat);
			n := len stat;
			d[o:] = stat;
			o += n;
		}
		p64(d, o, m.offset); o += OFFSET;
		p32(d, o, len m.data); o += COUNT;
		d[o:] = m.data;
	Get =>
		o := pstring(d, H, m.path);
		p16(d, o, m.fd); o += BIT16SZ;
		p16(d, o, m.mode); o += BIT16SZ;
		p16(d, o, m.nmsgs); o += BIT16SZ;
		p64(d, o, m.offset); o += OFFSET;
		p32(d, o, m.count); o += COUNT;
	Remove =>
		pstring(d, H, m.path);
	* =>
		fprint(fildes(2), "op: pack: bad tag: %d", tagof t);
	}
	return d;
}

Tmsg.unpack(f: array of byte): (int, ref Tmsg)
{
	if(len f < H)
		return (0, nil);
	size := (int f[1] << 8) | int f[0];
	size |= ((int f[3] << 8) | int f[2]) << 16;
	if(len f != size){
		if(len f < size)
			return (0, nil);	# need more data
		f = f[0:size];		# trim to exact length
	}
	mtype := int f[4];
	if(mtype >= Tmax || (mtype&1) == 0 || mtype <= 0){
		fprint(fildes(2), "upack: bad mtype %d\n", mtype);
		return (-1, nil);
	}
	tag := (int f[6] << 8) | int f[5];

	case mtype {
	* =>
		fprint(fildes(2), "op: unpack: bad type %d\n", mtype);
	Tattach =>
		(uname, o1) := gstring(f, H);
		(path, o2) := gstring(f, o1);
		return (o2, ref Tmsg.Attach(tag, uname, path));
	Tflush =>
		oldtag := (int f[H+1] << 8) | int f[H];
		return (H+TAG, ref Tmsg.Flush(tag, oldtag));
	Tput =>
		stat : Sys->Dir;
		(path, o) := gstring(f, H); 
		fd := g16(f, o); o+= BIT16SZ;
		mode := g16(f, o); o+= BIT16SZ;
		if(mode&OSTAT){
			o1 : int;
			(o1, stat) = unpackdir(f[o:]); o += o1;
		}
		offset := g64(f, o); o+= OFFSET;
		count := g32(f, o); o+= COUNT;
		data := f[o:o+count]; o+= count;
		return (o, ref Tmsg.Put(tag, path, fd, mode, stat, offset, data));
	Tget =>
		(path, o) := gstring(f, H); 
		fd := g16(f, o); o += BIT16SZ;
		mode := g16(f, o); o+= BIT16SZ;
		nmsgs := g16(f, o); o+= BIT16SZ;
		offset := g64(f, o); o+= OFFSET;
		count := g32(f, o); o+= COUNT;
		return (o, ref Tmsg.Get(tag, path, fd, mode, nmsgs, offset, count));
	Tremove =>
		(path, o1) := gstring(f, H);
		return (o1, ref Tmsg.Remove(tag, path));
	}
	return (-1, nil);		# illegal
}

tmsgname := array[] of {
	tagof Tmsg.Readerror => "READERROR",
	tagof Tmsg.Attach => "attach",
	tagof Tmsg.Flush => "flush",
	tagof Tmsg.Put => "put",
	tagof Tmsg.Get => "get",
	tagof Tmsg.Remove => "remove",};

Tmsg.text(t: self ref Tmsg): string
{
	if(t == nil)
		return "nil";
	s := sys->sprint("T%s %ud", tmsgname[tagof t], t.tag);
	pick m:= t {
	* =>
		return s + " ILLEGAL";
	Readerror =>
		return s + sys->sprint(" \"%s\"", m.error);
	Attach =>
		return s + sys->sprint(" \"%s\" \"%s\"", m.uname, m.path);
	Flush =>
		return s + sys->sprint(" %ud", m.oldtag);
	Put =>
		s += sys->sprint("\"%s\" fd=%d %s", m.path, m.fd, mode2text(m.mode));
		if(m.mode&OSTAT)
			s += sys->sprint(" %s",  dir2text(m.stat));
		n := len m.data;
		s += sys->sprint("  o=%bd  c=%ud", m.offset, n);
		if(n > 0){
			x := "";
			if(n > 10) {
				x= "..."; n = 10;
			}
			s += sys->sprint(" \"%s%s\"", string m.data[0:n], x);
		}
		return s ;
	Get =>
		s += sys->sprint(" \"%s\" fd=%d %s", m.path, m.fd, mode2text(m.mode));
		s += sys->sprint("  n=%d o=%bd  c=%ud", m.nmsgs, m.offset, m.count);
		return s ;
	Remove =>
		return s + sys->sprint(" \"%s\"", m.path);
	}
}

Tmsg.read(fd: ref Sys->FD, msglim: int): ref Tmsg
{
	(msg, err) := readmsg(fd, msglim);
	if(err != nil)
		return ref Tmsg.Readerror(0, err);
	if(msg == nil)
		return nil;
	(nil, m) := Tmsg.unpack(msg);
	if(m == nil)
		return ref Tmsg.Readerror(0, "bad Op T-message");
	return m;
}

rtag2type := array[] of {
	tagof Rmsg.Readerror=> 0,
	tagof Rmsg.Error	=> Rerror,
	tagof Rmsg.Attach	=> Rattach,
	tagof Rmsg.Flush	=> Rflush,
	tagof Rmsg.Put	=> Rput,
	tagof Rmsg.Get	=> Rget,
	tagof Rmsg.Remove	=> Rremove,};

Rmsg.mtype(r: self ref Rmsg): int
{
	return rtag2type[tagof r];
}

Rmsg.packedsize(r: self ref Rmsg): int
{
	mtype := rtag2type[tagof r];
	if(mtype <= 0)
		return 0;
	ml := H;
	pick m := r {
	Error =>
		ml += STR + utflen(m.ename);
	Attach or Flush =>
	Put =>
		ml += BIT16SZ;
		ml += COUNT;
		ml += QID;
		ml += BIT32SZ;
	Get =>
		ml += BIT16SZ;
		ml += BIT16SZ;
		if(m.mode&OSTAT)
			ml += packdirsize(m.stat);
		ml += BIT32SZ;
		ml += len m.data;
	Remove =>
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
	d[0] = byte ps;
	d[1] = byte (ps>>8);
	d[2] = byte (ps>>16);
	d[3] = byte (ps>>24);
	d[4] = byte rtag2type[tagof r];
	d[5] = byte r.tag;
	d[6] = byte (r.tag >> 8);
	o := H;
	pick m := r {
	Error =>
		pstring(d, o, m.ename);
	Attach or Flush =>
	Put =>
		p16(d, o, m.fd); o += BIT16SZ;
		p32(d, o, m.count); o += COUNT;
		pqid(d, o, m.qid); o += QID;
		p32(d, o, m.mtime);
	Get =>
		p16(d, o, m.fd); o += BIT16SZ;
		p16(d, o, m.mode); o += BIT16SZ;
		if(m.mode&OSTAT){
			stat := packdir(m.stat);
			n := len stat;
			d[o:] = stat;
			o += n;
		}
		p32(d, o, len m.data); o += COUNT;
		d[o:] = m.data;
	Remove =>
	* =>
		fprint(fildes(2), "op: pack: bad tag: %d", tagof r);
	}
	return d;
}

Rmsg.unpack(f: array of byte): (int, ref Rmsg)
{
	if(len f < H)
		return (0, nil);
	size := (int f[1] << 8) | int f[0];
	size |= ((int f[3] << 8) | int f[2]) << 16;
	if(len f != size){
		if(len f < size)
			return (0, nil);	# need more data
		f = f[0:size];		# trim to exact length
	}
	mtype := int f[4];
	if(mtype >= Tmax || (mtype&1) != 0 || mtype <= 0){
		fprint(fildes(2), "upack: bad mtype %d\n", mtype);
		return (-1, nil);
	}
	tag := (int f[6] << 8) | int f[5];

	case mtype {
	* =>
		fprint(fildes(2), "op: unpack: bad type %d\n", mtype);
	Rerror =>
		if(len f < H + STR)
			return (H, ref Rmsg.Readerror(-1, "short Rerror msg"));
		(ename, o1) := gstring(f, H);
		return (o1, ref Rmsg.Error(tag, ename));
	Rattach =>
		return (H, ref Rmsg.Attach(tag));
	Rflush =>
		return (H, ref Rmsg.Flush(tag));
	Rput =>
		if(len f < H + BIT16SZ + COUNT + QID + BIT32SZ)
			return (H, ref Rmsg.Readerror(-1, "short Rput msg"));
		o := H;
		fd := g16(f, o); o +=  BIT16SZ;
		count := g32(f, o); o += COUNT;
		qid := gqid(f, o); o += QID;
		mtime := g32(f, o); o += BIT32SZ;
		return (o, ref Rmsg.Put(tag, fd, count, qid, mtime));
	Rget =>
		if(len f < H + BIT16SZ + BIT16SZ)
			return (H, ref Rmsg.Readerror(-1, "short Rget msg"));
		o := H;
		stat: Sys->Dir;
		fd := g16(f, o); o += BIT16SZ;
		mode := g16(f, o); o+= BIT16SZ;
		if(mode&OSTAT){
			o1 : int;
			if(len f < o + BIT32SZ)
				return (H, ref Rmsg.Readerror(-1, "short Rget msg"));
			(o1, stat) = unpackdir(f[o:]); o+= o1;
		}
		if(len f < o + COUNT)
			return (H, ref Rmsg.Readerror(-1, "short Rget msg"));
		count := g32(f, o); o+= COUNT;
		if(len f < o + count)
			return (H, ref Rmsg.Readerror(-1, "short Rget msg"));
		data := f[o:o+count]; o+= count;
		return (o, ref Rmsg.Get(tag, fd, mode, stat, data));
	Rremove =>
		return (H, ref Rmsg.Remove(tag));
	}
	return (-1, nil);		# illegal
}

rmsgname := array[] of {
	tagof Rmsg.Readerror => "READERROR",
	tagof Rmsg.Error => "error",
	tagof Rmsg.Attach => "attach",
	tagof Rmsg.Flush => "flush",
	tagof Rmsg.Put => "put",
	tagof Rmsg.Get => "get",
	tagof Rmsg.Remove => "remove",
};

Rmsg.text(r: self ref Rmsg): string
{
	if(r == nil)
		return "nil";
	s := sys->sprint("R%s %ud", rmsgname[tagof r], r.tag);
	pick m:= r {
	* =>
		return s + " ILLEGAL";
	Readerror =>
		return s + sys->sprint(" \"%s\"", m.error);
	Error =>
		return s + sys->sprint(" \"%s\"", m.ename);
	Attach or Flush =>
		return s;
	Put =>
		s += sys->sprint("  fd=%d %d  %s %d", m.fd, m.count, qid2text(m.qid), m.mtime);
		return s ;
	Get =>
		if(m.mode&OSTAT)
			s += sys->sprint(" fd=%d %s  %s", m.fd, mode2text(m.mode), dir2text(m.stat));
		else
			s += sys->sprint(" fd=%d %s", m.fd, mode2text(m.mode));
		n := len m.data;
		s += sys->sprint("  %ud", n);
		if(n > 0){
			x := "";
			if(n > 10) {
				x= "..."; n = 10;
			}
			s += sys->sprint(" \"%s%s\"", string m.data[0:n], x);
		}
		return s ;
	Remove =>
		return s;
	}
}

Rmsg.read(fd: ref Sys->FD, msglim: int): ref Rmsg
{
	(msg, err) := readmsg(fd, msglim);
	if(err != nil)
		return ref Rmsg.Readerror(0, err);
	if(msg == nil)
		return nil;
	(nil, m) := Rmsg.unpack(msg);
	if(m == nil)
		return ref Rmsg.Readerror(0, "bad Op R-message format");
	return m;
}

dir2text(d: Sys->Dir): string
{
	return sys->sprint("[\"%s\" \"%s\" \"%s\" %s 8r%uo %d %d %bd 16r%ux %d]",
		d.name, d.uid, d.gid, qid2text(d.qid), d.mode, d.atime, d.mtime, d.length, d.dtype, d.dev);
}

qid2text(q: Sys->Qid): string
{
	return sys->sprint("(16r%ubx,%d,16r%.2ux)", q.path, q.vers, q.qtype);
}

mode2text(m: int) : string
{
	td := ts := tc := tm := "-";
	if(m&ODATA)
		td = "d";
	if(m&OSTAT)
		ts = "s";
	if(m&OCREATE)
		tc = "c";
	if(m&OMORE)
		tm = "m";
	return td+ts+tc+tm;
}

readmsg(fd: ref Sys->FD, msglim: int): (array of byte, string)
{
	if(msglim <= 0)
		msglim = MAXHDR+MAXDATA;
	sbuf := array[BIT32SZ] of byte;
	if((n := readn(fd, sbuf, BIT32SZ)) != BIT32SZ){
		if(n == 0)
			return (nil, nil);
		return (nil, sys->sprint("%r"));
	}
	ml := (int sbuf[1] << 8) | int sbuf[0];
	ml |= ((int sbuf[3] << 8) | int sbuf[2]) << 16;
	if(ml <= BIT32SZ)
		return (nil, "invalid Op message size");
	if(ml > msglim)
		return (nil, "Op message longer than agreed: " + sprint("%d", ml));
	buf := array[ml] of byte;
	buf[0:] = sbuf;
	if((n = readn(fd, buf[BIT32SZ:], ml-BIT32SZ)) != ml-BIT32SZ){
		if(n == 0)
			return (nil, "Op message truncated");
		return (nil, sys->sprint("%r"));
	}
	return (buf, nil);
}

istmsg(f: array of byte): int
{
	if(len f < H)
		return -1;
	return (int f[BIT32SZ] & 1) != 0;
}
