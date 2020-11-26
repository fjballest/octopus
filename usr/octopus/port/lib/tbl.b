#
# Polimorphic table from styxpersist.b to include in other programs
#

implement Tbl;

include "tbl.m";


Table[T].new(nslots: int, nilval: T): ref Table[T]
{
	if(nslots == 0)
		nslots = 13;
	return ref Table[T](array[nslots] of list of (int, T), nilval);
}

Table[T].add(t: self ref Table[T], id: int, x: T): int
{
	slot := id % len t.items;
	for(q := t.items[slot]; q != nil; q = tl q)
		if((hd q).t0 == id)
			return -1;
	t.items[slot] = (id, x) :: t.items[slot];
	return 1;
}

Table[T].del(t: self ref Table[T], id: int): T
{
	slot := id % len t.items;
	
	p: list of (int, T);
	r := t.nilval;
	for(q := t.items[slot]; q != nil; q = tl q){
		if((hd q).t0 == id){
			p = joinip(p, tl q);
			r = (hd q).t1;
			break;
		}
		p = hd q :: p;
	}
	t.items[slot] = p;
	return r;
}

Table[T].find(t: self ref Table[T], id: int): T
{
	for(p := t.items[id % len t.items]; p != nil; p = tl p)
		if((hd p).t0 == id)
			return (hd p).t1;
	return t.nilval;
}

# join x to y, leaving result in arbitrary order.
joinip[T](x, y: list of (int, T)): list of (int, T)
{
	if(len x > len y)
		(x, y) = (y, x);
	for(; x != nil; x = tl x)
		y = hd x :: y;
	return y;
}
