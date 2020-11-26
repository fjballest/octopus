# Sam language and implementation taken from acme.
# This file was /appl/acme/elog.b, changed for o/x.
# Changed (read: broken for long files) to use a list of Elog entries
# because we keep edit logs in memory.

implement Samlog;
include "mods.m";
	Edit, Tree, Elog, Empty, Null, Elogbuf, Insert, Replace, Delete,
	debug, Etext, seled, trees, Esel: import oxedit;
	warnc: import sam;
	msg: import oxex;

init(d: Oxdat)
{
	initmods(d->mods);
}

Wsequence := "warning: changes out of sequence\n";
warned := 0;

#
# Log of changes made by editing commands.  Three reasons for this:
# 1) We want addresses in commands to apply to old file, not file-in-change.
# 2) It's difficult to track changes correctly as things move, e.g. ,x m$
# 3) This gives an opportunity to optimize by merging adjacent changes.
# It's a little bit like the Undo/Redo log in Files, but Point 3) argues for a
# separate implementation.  To do this well, we use Replace as well as
# Insert and Delete
#

#
# Minstring shouldn't be very big or we will do lots of I/O for small changes.
# Maxstring just places a limit.
#
Minstring: con 16;	# distance beneath which we merge changes
Maxstring: con 4*1024;	# maximum length of change we will merge into one

eloginit(f: ref Edit)
{
	if(f.elog == nil)
		f.elog = ref Elog(Empty, 0, 0, "");
	if(f.elog.typex != Empty)
		return;
	f.edited = 0;
	f.elog.typex = Null;
	nullelog: ref Elog;
	nullelog = nil;
	f.elogbuf = Elogbuf.new();
	f.elog.r = "";
}

elogreset(f: ref Edit)
{
	f.elog.typex = Null;
	f.elog.nd = 0;
	f.elog.r = "";
}

elogterm(f: ref Edit)
{
	f.elogbuf = nil;
	f.elog = nil;
	warned = 0;
}

elogflush(f: ref Edit)
{
	case(f.elog.typex){
	Null =>
		break;
	Insert or
	Replace or
	Delete =>
		f.elogbuf.push(f.elog);
		break;
	* =>
		error(sprint("unknown elog type 0x%ux\n", f.elog.typex));
	}
	elogreset(f);
}

elogreplace(f: ref Edit, q0: int, q1: int, r: string)
{
	gap: int;

	if(q0==q1 && len r==0)
		return;
	eloginit(f);
	if(f.elog.typex!=Null && q0<f.elog.q0){
		if(warned++ == 0)
			warnc <-= Wsequence;
		elogflush(f);
	}
	# try to merge with previous
	gap = q0 - (f.elog.q0+f.elog.nd);	# gap between previous and this
	if(f.elog.typex==Replace && len f.elog.r+gap+len r<Maxstring){
		if(gap < Minstring){
			if(gap > 0)
				f.elog.r += f.buf.gets(f.elog.q0+f.elog.nd, gap);
			f.elog.nd += gap + q1-q0;
			f.elog.r += r;
			return;
		}
	}
	elogflush(f);
	f.elog.typex = Replace;
	f.elog.q0 = q0;
	f.elog.nd = q1-q0;
	f.elog.r = r;
}

eloginsert(f: ref Edit, q0: int, r: string)
{
	if(len r == 0)
		return;
	eloginit(f);
	if(f.elog.typex!=Null && q0<f.elog.q0){
		if(warned++ == 0)
			warnc <-= Wsequence;
		elogflush(f);
	}
	# try to merge with previous
	if(f.elog.typex==Insert && q0==f.elog.q0 && len f.elog.r+len r<Maxstring){
		f.elog.r += r;
		return;
	}
	if(len r > 0){
		elogflush(f);
		f.elog.typex = Insert;
		f.elog.q0 = q0;
		f.elog.r = r;
	}
}

elogdelete(f: ref Edit, q0: int, q1: int)
{
	if(q0 == q1)
		return;
	eloginit(f);
	if(f.elog.typex!=Null && q0<f.elog.q0+f.elog.nd){
		if(warned++ == 0)
			warnc <-= Wsequence;
		elogflush(f);
	}
	#  try to merge with previous
	if(f.elog.typex==Delete && f.elog.q0+f.elog.nd==q0){
		f.elog.nd += q1-q0;
		return;
	}
	elogflush(f);
	f.elog.typex = Delete;
	f.elog.q0 = q0;
	f.elog.nd = q1-q0;
}

escape(s: string): string
{
	for(i := 0; i < len s; i++)
		if(s[i] == '\n')
			s[i] = 1;
	return s;
}

elogapply(f: ref Edit): int
{
	if(f.elog == nil || f.elogbuf == nil){
		if(f.edited&Esel){
			f.body.ctl(sprint("sel %d %d\n", f.q0, f.q1));
			f.edited &= ~Esel;
		}
		return 0;
	}
	elogflush(f);
	s := "";
	vers := f.vers;
	while( (b := f.elogbuf.pop()) != nil){
		if(f.buf == nil)
			fprint(stderr, "nil buf\n");
		case(b.typex){
		* =>
			fprint(stderr, "o/x: elogapply: bad b.typex %c\n", b.typex);
			break;
		Replace =>
			f.buf.del(b.nd, b.q0);
			es := sprint("del 0 %d %d %d", vers, b.q0, b.nd);
			s += escape(es) + "\n";
			f.buf.ins(b.r, b.q0);
			es = sprint("ins 0 %d %d %s", vers, b.q0, b.r);
			s += escape(es) + "\n";
			f.q0 = b.q0;
			f.q1 = b.q0 + len b.r;
			f.edited |= Etext|Esel;
			break;
		Delete =>
			f.buf.del(b.nd, b.q0);
			es := sprint("del 0 %d %d %d", vers, b.q0, b.nd);
			s += escape(es) + "\n";
			f.q0 = b.q0;
			f.q1 = b.q0;
			f.edited |= Etext|Esel;
			break;
		Insert =>
			f.buf.ins(b.r, b.q0);
			es := sprint("ins 0 %d %d %s", vers, b.q0, b.r);
			s += escape(es) + "\n";
			f.q0 = b.q0;
			f.q1 = b.q0 + len b.r;
			f.edited |= Etext|Esel;
			break;
		}
	}
	elogterm(f);
	rc := 0;
	if(f.edited&Etext){
		s = sprint("edstart %d\n", vers) + s;
		s += sprint("edend %d %d\n", 0, vers);
		vers++;
		rc = f.body.ctl(s);
		f.edited &= ~Etext;
		if(tagof(f) == tagof(ref Edit.File))
			f.body.ctl("dirty\n");
	}
	if(rc >= 0)
		f.vers = vers;
	if(f.edited&Esel){
		f.body.ctl(sprint("sel %d %d\n", f.q0, f.q1));
		f.edited &= ~Esel;
	}
	return rc;
}

