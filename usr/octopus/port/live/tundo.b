#
# Edits is a list of edits for undo/redo and also to know what to sync to o/mero.
#
# Look for /n/dump/2008/0701/usr/octopus/port/live/tundo.b:/^xedit
# if distributed cooperative editing is ever neeeded. At that point we did abandon
# it in favor of centralized cooperative editing.
#
# Edits.pos points always to the "current" edit.
# If the current edit is not closed, further edits are added if feasible by modifying
# the current edit (inserting even more past the current insert, etc.)
# If the current edit is closed, further edits are added just past it (a newly open edit).
# Events synced have the flag synced set to true.
# Events past the current edit were undone. Their synced flag reports if they have been
# seen by o/mero (not yet undone in o/mero) or not.
# If, when adding a new edit (not combined with the current)
# there are edits pending to be synced, the module reports failure.
# The caller is expected to sync the changes and try again.
# But note that undos are pending to be synced when they *have* the synced flag
# (o/mero did see them, but we have yet to undo that).
#
# The history looks like any of the following.
# 1. With some undos not yet undone in o/mero:
#
# 	closed	synced	ins blah
# 	closed	synced	ins y
# ->	closed	synced	del x	(current)
#	closed	synced	ins z
#			del a
#
# 2. With some undos already undone in o/mero and a redo
# 
# 	closed	synced	ins blah
# 	closed		ins y
# ->	closed		del x	(current) 
#	closed		ins z
#			del a
#
# 3. Without undos:
#
# 	closed	synced	ins blah
# 	closed	synced	ins y
# ->			del x	(current) 
#

implement Tundo;
include "sys.m";
	sys: Sys;
	fprint, sprint: import sys;
include "error.m";
	err: Error;
	checkload, stderr, panic, kill, error: import err;
include "string.m";
include "tblks.m";
	tblks: Tblks;
	fixposins, fixposdel: import tblks;
include "lists.m";
	lists: Lists;
	concat: import lists;
include "tundo.m";

debug := 2;

init(sysm: Sys, e: Error, l: Lists, t: Tblks, dbg: int)
{
	sys = sysm;
	err = e;
	tblks = t;
	lists = l;
	debug = dbg;
}

Edit.name(edit: self ref Edit): string
{
	pick edp := edit {
	Ins =>
		return "ins";
	Del =>
		return "del";
	}
	return nil;
}

inverse(ed: ref Edit): ref Edit
{
	pick edp := ed {
	Ins =>
		return ref Edit.Del(1, 1, edp.bundle, edp.pos, edp.s);
	Del =>
		return ref Edit.Ins(1, 1, edp.bundle, edp.pos, edp.s);
	}
	return nil;
}

nulledit(ed: ref Edit): int
{
	return len ed.s == 0;
}


Edits.new(): ref Edits
{
	ed0 := ref Edit.Del(1, 1, ~0, 0, "");	# fake null del at pos 0 (marker).
	edits := ref Edits;
	edits.e = array[1] of ref Edit;
	edits.e[0] = ed0;
	edits.pos = edits.cpos = 0;
	edits.gen++;
	return edits;
}

grow(edits: ref Edits, n: int)
{
	ne := array[len edits.e+n] of ref Edit;
	ne[0:] = edits.e;
	for(i := len edits.e; i < len ne; i++)
		ne[i] = nil;
	edits.e = ne;
}

# reports changes needed to sync o/mero with us.
# updates their synced flags accordingly if sync != 0
changes(edits: ref Edits, sync: int): list of ref Edit
{
	nl : list of ref Edit;

	# old/current edits not yet synced
	for(i := 1; i <= edits.pos && edits.e[i] != nil; i++){
		if(!nulledit(edits.e[i]) && !edits.e[i].synced)
			nl = concat(nl, list of {edits.e[i]});
		if(sync)
			edits.e[i].synced = edits.e[i].closed = 1;
	}

	# undos not undone in o/mero in reverse order
	for(i = edits.pos+1; i < len edits.e && edits.e[i] != nil; i++){
		if(!nulledit(edits.e[i]) && edits.e[i].synced)
			nl = inverse(edits.e[i])::nl;
		if(sync){
			edits.e[i].synced = 0;
			edits.e[i].closed = 1;
		}
	}
	return nl;
}

revl(l: list of ref Edit): list of ref Edit
{
	nl: list of ref Edit;
	for(; l != nil; l = tl l)
		nl = hd l::nl;
	return nl;
}

# This returns all the changes required (synced or not) to undo an edit.
Edits.undo(edits: self ref Edits): list of ref Edit
{
	if(edits.pos == 0)		# null 0th edit is always kept
		return nil;		# to avoid special cases.
	if(edits.e[edits.pos] == nil)
		panic("edits undo bug");
	edits.e[edits.pos].closed = 1;
	l := list of {inverse(edits.e[edits.pos])};
	for(edits.pos--; edits.pos > 0; edits.pos--)
		if(edits.e[edits.pos].bundle != edits.e[edits.pos+1].bundle)
			break;
		else if(!nulledit(edits.e[edits.pos]))
			l = inverse(edits.e[edits.pos])::l;
	return revl(l);
}

Edits.redo(edits: self ref Edits): list of ref Edit
{
	if(edits.pos+1 >= len edits.e || edits.e[edits.pos+1] == nil)
		return nil;
	l := list of {edits.e[++edits.pos]};
	while(edits.pos+1 < len edits.e && edits.e[edits.pos+1] != nil)
		if(edits.e[edits.pos].bundle != edits.e[edits.pos+1].bundle)
			break;
		else
			l = edits.e[++edits.pos]::l;
	return revl(l);
}

# About to add more edits. Ensure edits.e[edits.pos] is ok to ins/del.
# After mkpos, edits.pos is either not closed or it is a null entry.
# Further undone edits are pruned, to keep just a single edit history.
# If there are pending syncs, we report failure to let the caller sync and retry.
Edits.mkpos(edits: self ref Edits): int
{
	npos := edits.pos;
	if(edits.e[npos] != nil && edits.e[npos].closed)
		npos++;

	if(!edits.e[npos-1].synced)
		return -1;	
	for(i := npos; i < len edits.e && edits.e[i] != nil; i++)
		if(edits.e[i].synced)
			return -1;

	for(i = npos; i < len edits.e && edits.e[i] != nil; i++)
		if(edits.e[i].closed || i > npos)
			edits.e[i] = nil;
	if(npos >= len edits.e)
		grow(edits, 3);
	edits.pos = npos;
	return 0;
}

Edits.ins(edits: self ref Edits, s: string, pos: int): int
{
	if(len s == 0){
		fprint(stderr, "edits: ins: null string\n");
		return 0;
	}
	if(edits.mkpos() < 0)
		return -1;
	if(edits.e[edits.pos] == nil)			# can't fail later
		edits.e[edits.pos] = ref Edit.Ins(0, 0, edits.gen++, pos, "");
	pick edp := edits.e[edits.pos] {
	Ins =>
		if(pos < edp.pos || pos > edp.pos + len edp.s){
			edits.e[edits.pos].closed = 1;
			return -1;
		}
		l := len edp.s;
		pos -= edp.pos;
		if(len s == 1 && pos == l)
			edp.s[l] = s[0];
		else {
			ns := edp.s[0:pos] + s;
			if(pos < l)
				ns += edp.s[pos:];
			edp.s = ns;
		}
	Del =>
		# not frequent; don't bother.
		edits.e[edits.pos].closed = 1;
		return -1;
	}
	return 0;
}

Edits.del(edits: self ref Edits, s: string, pos: int): int
{
	if(len s == 0){
		fprint(stderr, "edits: del: null string\n");
		return 0;
	}
	if(edits.mkpos() < 0)
		return -1;
	if(edits.e[edits.pos] == nil)			# can't fail later
		edits.e[edits.pos] = ref Edit.Del(0, 0, edits.gen++, pos, "");
	pick edp := edits.e[edits.pos] {
	Ins =>
		epos := pos + len s;
		if(pos < edp.pos || epos > edp.pos + len edp.s){
			edits.e[edits.pos].closed = 1;
			return -1;
		}
		pos -= edp.pos;
		epos-= edp.pos;
		ns := edp.s[0:pos];
		if(epos < len edp.s)
			ns += edp.s[epos:];
		edp.s = ns;
	Del =>
		if(pos + len s == edp.pos){
			edp.pos = pos;
			edp.s = s + edp.s;
		} else if(pos == edp.pos + len edp.s)
			edp.s += s;
		else {
			edits.e[edits.pos].closed = 1;
			return -1;
		}
	}
	return 0;
}

Edits.sync(edits: self ref Edits): list of ref Edit
{
	return changes(edits, 0);
}

Edits.synced(edits: self ref Edits)
{
	changes(edits, 1);
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

Edit.text(e: self ref Edit): string
{
	if(e == nil)
		return "<nil>";
	s := "  ";
	if(e.synced)
		s[0] = 's';
	if(e.closed)
		s[1] = 'c';
	s += sprint("%s pos %d\t'%s'", e.name(), e.pos, dtxt(e.s));
	return s;
}

Edits.dump(edits: self ref Edits)
{
	fprint(stderr, "%d edits (pos %d cpos %d)\n", len edits.e, edits.pos, edits.cpos);
	for(i := 0; i < len edits.e && edits.e[i] != nil; i++){
		e := edits.e[i];
		s := "   ";
		if(i == edits.pos)
			s = " ->";
		if(i == edits.cpos)
			s[0] = 'f';
		s = sprint("[%02d] %s\t%s", i, s, e.text());
		fprint(stderr, "%s\n", s);
	}
	fprint(stderr, "\n");
}

dumpedits(s: string, l: list of ref Edit)
{
	fprint(stderr,"%s:\n", s);
	for(; l != nil; l = tl l)
		fprint(stderr, "\t%s\n", (hd l).text());
}
