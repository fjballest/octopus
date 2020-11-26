implement Merop; 
include "sys.m";
	sys: Sys;
	millisec, sprint, QTFILE, DMDIR, fildes, Qid, Dir, QTDIR, fprint: import sys;
include "blks.m";
	blks: Blks;
	Blk, utflen, pstring, gstring, p32, g32, dtxt: import blks;
include "merop.m";

init(s: Sys, b: Blks)
{
	sys = s;
	blks = b;
}

Msg.bread(b: ref Blk): ref Msg
{
	bl := b.blen();
	if(bl < BIT32SZ)
		return nil;
	sz := g32(b.data, b.rp);
	if(bl < sz)
		return nil; # not enough data
	mb := b.get(sz);
	(nil, m) := Msg.unpack(mb);
	return m;
}

tag2type := array[] of {
	tagof Msg.Update => Tupdate,
	tagof Msg.Ctl => Tctl,
};

Msg.mtype(t: self ref Msg): int
{
	return tag2type[tagof t];
}

Msg.name(t: self ref Msg): string
{
	pick m := t {
	Update =>
		return "update";
	Ctl =>
		return m.ctl;
	}
}

Msg.packedsize(t: self ref Msg): int
{
	mtype := tag2type[tagof t];
	if(mtype <= 0)
		return 0;
	ml := HDRSZ;
	ml += BIT32SZ + utflen(t.path);
	pick m := t {
	Update =>
		ml += BIT32SZ;	# vers
		if(m.ctls != nil)
			ml += BIT32SZ + utflen(m.ctls);
		else
			ml += BIT32SZ;
		ml += BIT32SZ;
		if(m.data != nil)
			ml += len m.data;
		if(m.edits != nil)
			ml += BIT32SZ + utflen(m.edits);
		else
			ml += BIT32SZ;
	Ctl =>
		ml += BIT32SZ + utflen(m.ctl);
	}
	return ml;
}

Msg.pack(t: self ref Msg): array of byte
{
	if(t == nil)
		return nil;
	ds := t.packedsize();
	if(ds <= 0)
		return nil;
	d := array[ds] of byte;
	p32(d, 0, ds);
	d[4] = byte tag2type[tagof t];
	o := pstring(d, 5, t.path);
	pick m := t {
	Update =>
		o = p32(d, o, m.vers);
		o = pstring(d, o, m.ctls);
		if(m.data == nil)
			o = p32(d, o, NODATA);
		else {
			o = p32(d, o, len m.data);
			d[o:] = m.data;
			o += len m.data;
		}
		o = pstring(d, o, m.edits);
	Ctl =>
		o = pstring(d, o, m.ctl);
	* =>
		fprint(fildes(2), "Merop: pack: bad tag: %d", tagof t);
	}
	return d;
}

Msg.unpack(f: array of byte): (int, ref Msg)
{
	if(len f < HDRSZ + BIT32SZ)
		return (0, nil);
	size := g32(f, 0);
	if(len f != size){
		if(len f < size)
			return (0, nil);	# need more data
		f = f[0:size];		# trim to exact length
	}
	mtype := int f[4];
	if(mtype >= Tmax || mtype <= 0){
		if(debug)
			fprint(fildes(2), "Merop: unpack: bad mtype %d", mtype);
		return (-1, nil);
	}
	(path, o) := gstring(f, 5);
	if(path == nil){
		if(debug)
			fprint(fildes(2), "Merop: unpack: null path\n");
		return (0, nil);
	}
	case mtype {
	Tupdate =>
		r := ref Msg.Update(path, 0, nil, nil, nil);
		r.vers = g32(f, o); o+= BIT32SZ;
		(r.ctls, o) = gstring(f, o);
		n := g32(f, o); o+= BIT32SZ;
		if(n != NODATA){
			r.data = f[o:o+n];
			o+= n;
		}
		(r.edits, o) = gstring(f, o);
		return (o, r);
	Tctl =>
		r := ref Msg.Ctl(path, nil);
		(r.ctl, o) = gstring(f, o);
		return (o, r);
	* =>
		fprint(fildes(2), "Merop: unpack: bad type: %d", mtype);
	}
	return (-1, nil);
}

msgname := array[] of {
	tagof Msg.Update => "update",
	tagof Msg.Ctl => "ctl",
};

Msg.text(t: self ref Msg): string
{
	if(t == nil)
		return "nil";
	s := sprint("T%s \"%s\"", msgname[tagof t], t.path);
	pick m:= t {
	Update =>
		s += sprint(" %ud [%s] [%s] [%s]", m.vers,
			dtxt(m.ctls), dtxt(string m.data), dtxt(m.edits));
	Ctl =>
		s += sprint(" %s", m.ctl);
	}
	return s;
}
