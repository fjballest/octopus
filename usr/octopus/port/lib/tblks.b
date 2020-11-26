#
# Text blocks owptext.b

implement Tblks;
include "sys.m";
	sys: Sys;
	fprint, fildes: import sys;
include "string.m";
	str: String;
	prefix: import str;
include "error.m";
	err: Error;
	checkload, stderr, panic, kill, error: import err;
include "tblks.m";

debug := 0;

init(sysm: Sys, strm: String, e: Error, dbg: int)
{
	sys = sysm;
	str = strm;
	err = e;
	debug = dbg;
}

Str.findr(s: self ref Str, pos: int, c: int, lim: int): int
{
	for(i := pos; i >= 0 && i < len s.s; i--)
		if(s.s[i] == c || --lim == 0)
			return i;
	return -1;
}

Str.find(s: self ref Str, pos: int, c:int, lim: int): int
{
	for(; pos < len s.s; pos++){
		if(s.s[pos] == c || --lim == 0)
			return pos;
	}
	return -1;
}

fixpos(pos: int, n: int): int
{
	if(pos < 0)
		return 0;
	else if(pos > n)
		return n;
	else
		return pos;
}

fixposins(pos, inspos, n: int): int
{
	if(inspos < pos)
		pos += n;
	return pos;
}

fixposdel(pos, delpos, n: int): int
{
	if(delpos < pos){
		if(delpos + n > pos)
			n = pos - delpos;
		pos -= n;
	}
	return pos;
}

Tblk.blen(blks: self ref Tblk): int
{
	l := 0;
	for(i := 0; i < len blks.b && blks.b[i] != nil; i++)
		l += len blks.b[i].s;
	return l;
}


Tblk.new(s: string): ref Tblk
{
	b0 := ref Str(s);
	return ref Tblk(array[] of { b0 });
}

Tblk.pack(blks: self ref Tblk): ref Str
{
	for(i := 1; i < len blks.b && blks.b[i] != nil; i++){
		blks.b[0].s += blks.b[i].s;
		blks.b[i] = nil;
	}
	return blks.b[0];
}

Tblk.seek(blks: self ref Tblk, off: int): (int, int)
{
	for(i := 0; i < len blks.b && blks.b[i] != nil; i++){
		nr := len blks.b[i].s;
		if(nr == 0)
			continue;
		if(off <= nr)
			break;
		off -= nr;
	}
	return (i, off);
}

Tblk.getc(blks: self ref Tblk, pos: int): int
{
	
	for(i:= 0; i < len blks.b && blks.b[i] != nil; i++){
		if(pos < len blks.b[i].s)
			return blks.b[i].s[pos];
		pos -= len blks.b[i].s;
	}
	return -1;
}

Tblk.gets(blks: self ref Tblk, pos: int, nr: int): string
{
	s := blks.pack();
	if(pos > len s.s)
		pos = len s.s;
	if(pos + nr > len s.s)
		nr = len s.s - pos;
	if(nr == 0)
		return "";
	else
		return s.s[pos:pos+nr];
}

Tblk.ins(blks: self ref Tblk, t: string, pos: int)
{
	if(debug)
		fprint(stderr, "Tblk.ins: '%s' %d\n", dtxt(t), pos);
	s: ref Str;
	nr := 0;
	for(i := 0; i < len blks.b && blks.b[i] != nil; i++){
		s = blks.b[i];
		nr = len s.s;
		if(pos <= nr)
			break;
		if(nr == 0)
			continue;
		pos -= nr;
	}
	if(pos == nr && len t == 1){
		s.s[pos] = t[0];
		return;
	}
	ns := ref Str(t);
	nb: array of ref Str;
	if(i == len blks.b){
		nb = array[len blks.b + 1] of ref Str;
		nb[i] = blks.b[i];
		nb[0:] = blks.b[0:i];
		blks.b = nb;
	} else if (blks.b[i] == nil)
		blks.b[i] = ns;
	else {
		nb = array[len blks.b + 2] of ref Str;
		ns2 := ref Str(blks.b[i].s[pos:]);
		blks.b[i].s = blks.b[i].s[0:pos];
		nb[i] = blks.b[i];
		nb[i+1] = ns;
		nb[i+2] = ns2;
		if(i + 1 < len blks.b)
			nb[i+3:] = blks.b[i+1:];
		nb[0:] = blks.b[0:i];
		blks.b = nb;
	}
}

Tblk.del(blks: self ref Tblk, n: int, pos: int): string
{
	if(n <= 0)
		return "";
	s: ref Str;
	nr: int;
	for(i := 0; i < len blks.b && blks.b[i] != nil; i++){
		s = blks.b[i];
		nr = len s.s;
		if(nr == 0)
			continue;
		if(pos <= nr)
			break;
		pos -= nr;
	}
	t := "";
	while(i < len blks.b && blks.b[i] != nil && n > 0) {
		s = blks.b[i];
		nr = len s.s;
		edel := pos + n;
		if(edel > nr)
			edel = nr;
		ndel := edel - pos;
		if(ndel > 0)
			t += s.s[pos:edel];
		if(nr - edel > 0)
			s.s = s.s[0:pos] + s.s[edel:];
		else
			s.s = s.s[0:pos];
		n -= ndel;
		pos = 0;
		i++;
	}
	return t;
}

strchr(s : string, c : int) : int
{
	for(i := 0; i < len s; i++)
		if(s[i] == c)
			return i;
	return -1;
} 

strstr(s1, s2: string): int
{
	for(i := 0; i < len s1; i++)
		if(prefix(s2, s1[i:]))
			return i;
	return -1;
}

dtxt(s: string): string
{
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

Tblk.dump(blks: self ref Tblk)
{
	if(blks == nil || blks.b == nil)
		return;
	fprint(stderr, "%d blks\n", len blks.b);
	for(i := 0; i < len blks.b && blks.b[i] != nil; i++)
		fprint(stderr, "\tblk[%d]: %d '%s'\n", i, len blks.b[i].s, dtxt(blks.b[i].s));
}

