implement Blks;

include "sys.m";
	sys: Sys;
	millisec, sprint, QTFILE, DMDIR, fildes, FD,
	read, Qid, Dir, QTDIR, fprint: import sys;
include "blks.m";

init()
{
	sys = load Sys Sys->PATH;
}

Blk.dump(b: self ref Blk)
{
	if(b == nil)
		fprint(fildes(2), "<nil>\n");
	else {
		s := sprint("blk: rp %d wp %d ep %d",
			b.rp, b.wp, len b.data);
		if(b.data != nil){
			dt := string b.data[b.rp:b.wp];
			s += sprint(" data [%s]", dtxt(dt));
		}
		fprint(fildes(2), "%s\n", s);
	}
}

		
Blk.blen(b: self ref Blk): int
{
	if(b.rp > b.wp || b.wp > len b.data){
		fprint(fildes(2), "bad block"); b.dump();
		raise("bug");
	}
	return b.wp - b.rp;
}

Blk.read(b: self ref Blk, fd: ref FD, max: int): int
{
	if(max == 0)
		max = 1024;
	if(len b.data - b.wp < max)
		b.grow(max);
	nr := read(fd, b.data[b.wp:], len b.data - b.wp);
	if(nr > 0)
		b.wp += nr;
	return nr;
}

Blk.grow(b: self ref Blk, n: int)
{
	# debug flag checked here to be sure
	# we debug how it grows and packs itself.
	if(!debug && n < 1024)
		n = 1024;	
	if(len b.data == 0){
		b.data = array[n] of byte;
	}
	if(b.rp > 512 || (debug && b.rp > 10)){
		b.data[0:] = b.data[b.rp:b.wp];
		b.wp -= b.rp;
		b.rp = 0;
	}
	if(len b.data - b.wp < n){
		ndata := array[b.wp - b.rp + n] of byte;
		ndata[0:] = b.data[b.rp:b.wp];
		b.wp -= b.rp;
		b.rp = 0;
		b.data = ndata;
	}
}

Blk.put(b: self ref Blk, data: array of byte)
{
	if(len b.data - b.wp < len data)
		b.grow(len data);
	b.data[b.wp:] = data[0:];
	b.wp += len data;
}

Blk.get(b: self ref Blk, cnt: int): array of byte
{
	data := b.data[b.rp:b.rp+cnt];
	b.rp += cnt;
	if(b.rp == b.wp)
		b.rp = b.wp = 0;
	return data;
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

pstring(a: array of byte, o: int, s: string): int
{
	if(s == nil){
		p32(a, o, NODATA);
		return o+BIT32SZ;
	}
	sa := array of byte s;	# could do conversion ourselves
	n := len sa;
	p32(a, o, n);
	a[o+BIT32SZ:] = sa;
	return o+BIT32SZ+n;
}

gstring(a: array of byte, o: int): (string, int)
{
	if(o < 0 || o+BIT32SZ > len a)
		return (nil, -1);
	l := g32(a, o);
	o += BIT32SZ;
	if(l == NODATA)
		return (nil, o);
	e := o+l;
	if(e > len a)
		return (nil, -1);
	return (string a[o:e], e);
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

g16(f: array of byte, i: int): int
{
	r := (( int f[i+1]) << 8) | int f[i];
	if(r == int 16rFFFF)
		r = ~0;
	return r;
}


g32(f: array of byte, i: int): int
{
	if(len f < i+4)
		return ~0;
	r := (((((int f[i+3] << 8) | int f[i+2]) << 8) | int f[i+1]) << 8) | int f[i];
	if(r == int 16rFFFFFFFF)
		r = ~0;
	return r;
}

g64(f: array of byte, i: int): big
{
	b0 := (((((int f[i+3] << 8) | int f[i+2]) << 8) | int f[i+1]) << 8) | int f[i];
	b1 := (((((int f[i+7] << 8) | int f[i+6]) << 8) | int f[i+5]) << 8) | int f[i+4];
	return (big b1 << 32) | (big b0 & 16rFFFFFFFF);
}

dtxt(s: string): string
{
	if(s == nil)
		return "<nil>";
	if(len s> 35)
		s = s[0:15] + " ... " + s[len s - 15:];
	ns := "";
	for(i := 0; i < len s; i++)
		if(s[i] == '\n')
			ns += "\\n";
		else
			ns[len ns] = s[i];
	return ns;
}

