# Sam language taken from acme.
# This file was /appl/acme/ecmd.b, changed for o/x.
#
# Sam commands are implemented here.
# The main loop at edit.b, after parsing, calls
# cmdexec() to do the actual work.
#

implement Samcmd;
include "mods.m";
	elogterm, eloginsert, elogreplace, elogdelete, elogapply: import samlog;
	Addr, Address, BUFSIZE, Cmd: import Sam;
	aNo, aDot, aAll, editerror, cmdlookup, cmdtab, warnc,
	C_nl, C_a, C_b, C_c, C_d, C_B, C_D, C_e, C_f, C_g, C_i, C_k, C_P,
	C_m, C_n, C_p, C_s, C_u, C_w, C_x, C_X, C_pipe, C_eq: 	import sam;
	NRange, Range, Rangeset: import Regx;
	rxcompile, rxexecute, rxbexecute: import regx;
	fsname, Edit, Tree, Etext, seled, trees, Ename, Esel: import oxedit;
	Xcmd, newedit, deledit, putedit, pipein, pipeout, findedit: import oxex;
	cleanname, dirname, rooted: import names;
	readdev: import io;
	screens, rows, cols: import panels;
none: Address;

omero: string;
init(d: Oxdat)
{
	initmods(d->mods);
	omero = getenv("omero");
	if(omero == nil)
		omero = "/mnt/ui";

	none.r.q0 = none.r.q1 = 0;
	none.f = nil;
}

skipbl(r : string) : string
{
	for(i := 0; i < len r && (r[i]==' ' || r[i]=='\t' || r[i]=='\n'); i++)
		;
	if(i == len r)
		return "";
	else
		return r[i:];
}

# executes a sam command (compound or not).
# builds the address and applies the command to it.
cmdexec(t: ref Edit, cp: ref Cmd): int
{
	i: int;
	ap: ref Addr;
	f: ref Edit;
	dot: Address;
	w: ref Panel;
	w = nil;
	if(t != nil)
		w = t.body;
	if(w==nil && (cp.addr==nil || cp.addr.typex!='"') &&
	    strchr("bBnqUXYPQ!", cp.cmdc) < 0&&
	    !(cp.cmdc=='D' && cp.text!=nil))
		editerror("no current panel");
	i = cmdlookup(cp.cmdc);	# will be -1 for '{' 
	f = nil;
	if(t != nil && t.body != nil){
		f = t;
		if(f.buf == nil)		# we may have changed the buffer
			f.getedits();	# in previous cmd execs.
	}
	if(i>=0 && cmdtab[i].defaddr != aNo){
		if((ap=cp.addr)==nil && cp.cmdc!='\n'){
			cp.addr = ap = ref Addr;
			ap.typex = '.';
			if(cmdtab[i].defaddr == aAll)
				ap.typex = '*';
		}else if(ap!=nil && ap.typex=='"' && ap.next==nil && cp.cmdc!='\n'){
			ap.next = ref Addr;
			ap.next.typex = '.';
			if(cmdtab[i].defaddr == aAll)
				ap.next.typex = '*';
		}
		if(cp.addr!=nil){	# may be false for '\n' (only)
			if(f!=nil){
				dot = mkaddr(f);
				addr = cmdaddress(ap, dot, 0);
			}else	# a "
				addr = cmdaddress(ap, none, 0);
			f = addr.f;
			if(f.buf == nil)
				f.getedits();
		}
	}
	case(cp.cmdc){
	'{' =>
		dot = mkaddr(f);
		if(cp.addr != nil)
			dot = cmdaddress(cp.addr, dot, 0);
		for(cp = cp.cmd; cp!=nil; cp = cp.next){
			f.q0 = dot.r.q0;
			f.q1 = dot.r.q1;
			cmdexec(f, cp);
		}
		break;
	* =>
		if(i < 0)
			editerror(sprint("unknown command %c in cmdexec", cp.cmdc));
		i = cmdtabexec(i, f, cp);
		return i;
	}
	return 1;
}

# Executes a command given its cmdtab index
cmdtabexec(i: int, t: ref Edit, cp: ref Cmd): int
{
	case (cmdtab[i].fnc){
		C_nl	=> i = nl_cmd(t, cp);
		C_a 	=> i = a_cmd(t, cp);
		C_c	=> i = c_cmd(t, cp);
		C_d	=> i = d_cmd(t, cp);
		C_e	=> i = e_cmd(t, cp);
		C_f	=> i = f_cmd(t, cp);
		C_g	=> i = g_cmd(t, cp);
		C_i	=> i = i_cmd(t, cp);
		C_m	=> i = m_cmd(t, cp);
		C_n	=> i = n_cmd(t, cp);
		C_p	=> i = p_cmd(t, cp);
		C_s	=> i = s_cmd(t, cp);
		C_w	=> i = w_cmd(t, cp);
		C_x	=> i = x_cmd(t, cp);
		C_eq	=> i = eq_cmd(t, cp);
		C_B	=> i = B_cmd(t, cp);
		C_D	=> i = D_cmd(t, cp);
		C_X	=> i = X_cmd(t, cp);
		C_P	=> i = P_cmd(t, cp);
		C_pipe	=> i = pipe_cmd(t, cp);
		* =>	error("bad case in cmdtabexec");
	}
	return i;
}

Glooping: int;
nest: int;
Enoname := "no file name given";

addr: Address;
menu: ref Edit;
sel: Rangeset;
collection: string;

resetxec()
{
	Glooping = nest = 0;
	collection = nil;
}

mkaddr(f: ref Edit): Address
{
	a: Address;

	a.r.q0 = f.q0;
	a.r.q1 = f.q1;
	a.f = f;
	return a;
}


edittext(f: ref Edit, q: int, r: string): string
{
	case(editing){
	Inactive =>
		return "permission denied";
	Inserting =>
		eloginsert(f, q, r);
		return nil;
	Collecting =>
		collection += r;
		return nil;
	* =>
		return "unknown state in edittext";
	}
}

filelist(t: ref Edit, r: string): list of string
{
	if(len r == 0)
		return nil;
	r = skipbl(r);
	l: list of string;
	if(len r == 0 || r[0] != '<')
		(nil, l) = tokenize(r, " \t\n");
	else {
		# use < command to collect text 
		collection = "";
		runpipe(t, '<', r[1:], Collecting);
		(nil, l) = tokenize(collection, " \t\n");
	}
	return l;
}

a_cmd(t: ref Edit, cp: ref Cmd): int
{
	return append(t, cp, addr.r.q1);
}

B_cmd(t: ref Edit, cp: ref Cmd): int
{
	tr := Tree.find(t.tid);
	l := filelist(t, cp.text);
	if(l == nil)
		editerror(Enoname);
	for(; l != nil; l = tl l){
		path := cmdname(t, hd l);
		newedit(tr, path, 0, 0);
	}
	collection = "";
	return 1;
}

c_cmd(t: ref Edit, cp: ref Cmd): int
{
	elogreplace(t, addr.r.q0, addr.r.q1, cp.text);
	return 1;
}

d_cmd(t: ref Edit, nil: ref Cmd): int
{
	if(addr.r.q1 > addr.r.q0)
		elogdelete(t, addr.r.q0, addr.r.q1);
	return 1;
}

D_cmd(t: ref Edit, cp: ref Cmd): int
{
	listx := filelist(t, cp.text);
	if(listx == nil){
		deledit(t);
		return 1;
	}
	for(; listx != nil; listx = tl listx){
		path := cmdname(t, hd listx);
		w := findedit(t, path);
		deledit(w);
	}
	collection = "";
	return 1;
}

readloader(f: ref Edit, q0: int, r: string): int
{
	if(len r > 0)
		eloginsert(f, q0, r);
	return 0;
}

e_cmd(t: ref Edit , cp: ref Cmd): int
{
	f := t;
	q0 := addr.r.q0;
	q1 := addr.r.q1;
	name := cmdname(f, cp.text);
	if(name == nil)
		editerror(Enoname);
	samename := name == t.path;
	if(cp.cmdc == 'e'){
		if(tagof t != tagof ref Edit.File)
			editerror("not a file panel");
		if(t.dirty)
			editerror(sprint("%s: unsaved changes", t.path));
		q0 = 0;
		q1 = t.buf.blen();
	}
	if(cp.cmdc == 'e' && !samename)
		for(trl := trees; trl != nil; trl = tl trl)
		for(eds := (hd trl).eds; eds != nil; eds = tl eds)
			if((hd eds).path == name)
				editerror(sprint("%s already loaded", name));
	fd := sys->open(fsname(name), Sys->OREAD);
	if(fd == nil)
		editerror(sprint("can't open %s: %r", name));
	(ok, d) := sys->fstat(fd);
	if(ok >=0 && (d.mode&Sys->DMDIR))
		editerror(sprint("%s is a directory", name));
	buf := string readfile(fd);
	fd = nil;
	if(buf == nil)
		warnc <-= sprint("%s: read: %r\n", name);
	for(i := 0; i < len buf; i++)
		if(buf[i] == 0 || buf[i] == 1)
			editerror(sprint("%s: binary file", name));
	if(q1 > q0 && len buf > 0)
		elogreplace(t, q0, q1, buf);
	else {
		if(q1 > q0)
			elogdelete(f, q0, q1);
		if(len buf > 0)
			eloginsert(t, q1, buf);
	}
	if(cp.cmdc == 'e' && !samename){
		t.path = name;
		(ok, d) = stat(fsname(name));
		if(ok >= 0 && d.qid.qtype&QTDIR)
			t.dir = name;
		else
			t.dir = dirname(name);
		t.edited |= Ename;
	}
	if(cp.cmdc == 'e' && samename && t.dirty)
		if(t.dirty){
			t.dirty = 0;
			t.body.ctl("clean");
		}
	return 1;
}

f_cmd(t: ref Edit, cp: ref Cmd): int
{
	name := cmdname(t, cp.text);
	if(name != t.path){
		if(tagof t != tagof ref Edit.File)
			editerror("not a file panel");
		for(trl := trees; trl != nil; trl = tl trl)
		for(eds := (hd trl).eds; eds != nil; eds = tl eds)
			if((hd eds).path == name)
				editerror(sprint("%s already loaded", name));
	}
	t.path = name;
	(ok, d) := stat(fsname(name));
	if(ok >= 0 && d.qid.qtype&QTDIR)
		t.dir = name;
	else
		t.dir = dirname(name);
	t.edited |= Ename;
	warnc <-= filename(t);
	return 1;
}

g_cmd(t: ref Edit, cp: ref Cmd): int
{
	ok: int;
	if(t != addr.f){
		error("internal error: g_cmd f!=addr.f\n");
		return 0;
	}
	if(rxcompile(cp.re) == 0)
		editerror(sprint("bad regexp '%s' in g command",cp.re));
	(ok, sel) = rxexecute(t.buf, nil, addr.r.q0, addr.r.q1);
	if(ok ^ cp.cmdc=='v'){
		t.q0 = addr.r.q0;
		t.q1 = addr.r.q1;
		return cmdexec(t, cp.cmd);
	}
	return 1;
}

i_cmd(t: ref Edit, cp: ref Cmd): int
{
	return append(t, cp, addr.r.q0);
}

copy(f: ref Edit, addr2: Address)
{
	n := addr.r.q1 - addr.r.q0;
	s := f.buf.gets(addr.r.q0, n);
	eloginsert(addr2.f, addr2.r.q1, s);
}

move(f: ref Edit, addr2: Address)
{
	if(addr.f!=addr2.f || addr.r.q1<=addr2.r.q0){
		elogdelete(f, addr.r.q0, addr.r.q1);
		copy(f, addr2);
	}else if(addr.r.q0 >= addr2.r.q1){
		copy(f, addr2);
		elogdelete(f, addr.r.q0, addr.r.q1);
	}else
		error("move overlaps itself");
}

m_cmd(t: ref Edit, cp: ref Cmd): int
{
	dot := mkaddr(t);
	addr2 := cmdaddress(cp.mtaddr, dot, 0);
	if(cp.cmdc == 'm')
		move(t, addr2);
	else
		copy(t, addr2);
	return 1;
}

n_cmd(nil: ref Edit, nil: ref Cmd): int
{
	s := "";
	for(trl := trees; trl != nil; trl = tl trl)
		for(eds := (hd trl).eds; eds != nil; eds = tl eds)
			s += filename(hd eds);
	if(s != "")
		warnc <-= s;
	return 1;
}

p_cmd(t: ref Edit, nil: ref Cmd): int
{
	return pdisplay(t);
}

s_cmd(t: ref Edit, cp: ref Cmd): int
{
	n := cp.num;
	op:= -1;
	if(rxcompile(cp.re) == 0)
		editerror("bad regexp in s command");
	nrp := 0;
	rp: array of Rangeset;
	rp = nil;
	delta := 0;
	didsub := 0;
	ok := 0;
	for(p1 := addr.r.q0; p1<=addr.r.q1; ){
		(ok, sel) = rxexecute(t.buf, nil, p1, addr.r.q1);
		if(!ok)
			break;
		if(sel[0].q0 == sel[0].q1){	# empty match?
			if(sel[0].q0 == op){
				p1++;
				continue;
			}
			p1 = sel[0].q1+1;
		}else
			p1 = sel[0].q1;
		op = sel[0].q1;
		if(--n>0)
			continue;
		nrp++;
		orp := rp;
		rp = array[nrp] of Rangeset;
		rp[0: ] = orp[0:nrp-1];
		rp[nrp-1] = copysel(sel);
		orp = nil;
	}
	buf := "";
	c: int;
	for(m:=0; m<nrp; m++){
		buf = "";
		sel = rp[m];
		for(i := 0; i<len cp.text; i++)
			if((c = cp.text[i])=='\\' && i < len cp.text -1){
				c = cp.text[++i];
				if('1'<=c && c<='9') {
					j := c-'0';
					if(sel[j].q1-sel[j].q0>BUFSIZE){
						editerror("replacement string too long");
						return 0;
					}
					buf += t.buf.gets(sel[j].q0, sel[j].q1-sel[j].q0);
				}else
				 	buf[len buf] = c;
			}else if(c!='&')
				buf[len buf] = c;
			else{
				if(sel[0].q1-sel[0].q0>BUFSIZE){
					editerror("right hand side too long in substitution");
					return 0;
				}
				buf += t.buf.gets(sel[0].q0, sel[0].q1-sel[0].q0);
			}
		elogreplace(t, sel[0].q0, sel[0].q1, buf);
		delta -= sel[0].q1-sel[0].q0;
		delta += len buf;
		didsub = 1;
		if(!cp.flag)
			break;
	}
	if(!didsub && nest==0)
		editerror("no substitution");
	t.edited |= Esel;
	t.q0 = addr.r.q0;
	t.q1 = addr.r.q1+delta;
	return 1;
}

w_cmd(t: ref Edit, cp: ref Cmd): int
{
	r := cmdname(t, cp.text);
	if(r == nil)
		r = t.path;
	putedit(t, r);
	return 1;
}

x_cmd(t: ref Edit, cp: ref Cmd): int
{
	if(cp.re!=nil)
		looper(t, cp, cp.cmdc=='x');
	else
		linelooper(t, cp);
	return 1;
}

X_cmd(nil: ref Edit, cp: ref Cmd): int
{
	filelooper(cp, cp.cmdc=='X');
	return 1;
}

runpipe(t: ref Edit, cmd: int, cr: string, state: int)
{
	r := skipbl(cr);
	if(len r == 0)
		editerror("no command specified for >");
	if(state == Inserting){
		t.q0 = addr.r.q0;
		t.q1 = addr.r.q1;
	}
	dir := ".";
	file := "";
	if(t != nil){
		dir = t.dir;
		file = t.path;
	}
	if(dir == ".")
		dir = nil;
	editing = state;

	ifd, ofd: ref FD;
	ifd = ofd = nil;
	oc: chan of string;
	oc = nil;
	if(cmd == '>' || cmd == '|'){
		if(t.q1 > t.q0){
			s := t.buf.gets(t.q0, t.q1-t.q0);
			ifd = pipein(s);
		}
	}
	if(cmd== '<' || cmd == '|')
		(ofd, oc) = pipeout();
	onhost  := oxedit->fsdir != "";
	Xcmd.new(cr, file, dir, ifd, ofd, t.tid, onhost);
	ifd = ofd = nil;
	out := "";
	if(oc != nil)
		out = <-oc;
	if(state == Collecting)
		collection += out;
	else if(cmd == '<' || cmd=='|')
		if(t.q1 > t.q0)
			if(len out > 0)
				elogreplace(t, t.q0, t.q1, out);
			else
				elogdelete(t, t.q0, t.q1);
		else if(len out > 0)
			eloginsert(t, t.q0, out);
	t.edited |= Etext|Esel;
	editing = Inactive;
}

pipe_cmd(t: ref Edit, cp: ref Cmd): int
{
	runpipe(t, cp.cmdc, cp.text, Inserting);
	return 1;
}

nlcount(t: ref Edit, q0: int, q1: int): int
{
	nl := 0;
	l := t.buf.blen();
	for(i := q0; i < q1 && i < l; i++)
		if(t.buf.getc(i) == '\n')
			nl++;
	return nl;
}

printposn(t: ref Edit, charsonly: int)
{
	s := t.path + ":";
	if(!charsonly){
		l1 := 1+nlcount(t, 0, addr.r.q0);
		l2 := l1+nlcount(t, addr.r.q0, addr.r.q1);
		# check if addr ends with '\n' 
		if(addr.r.q1>0 && addr.r.q1>addr.r.q0 && t.buf.getc(addr.r.q1-1)=='\n')
			--l2;
		s += sprint("%ud", l1);
		if(l2 != l1)
			s += sprint(",%ud", l2);
		warnc <-= s + "\n";
		return;
	}
	s += sprint("#%d", addr.r.q0);
	if(addr.r.q1 != addr.r.q0)
		s += sprint(",#%d", addr.r.q1);
	warnc <-= s + "\n";
}

eq_cmd(t: ref Edit, cp: ref Cmd): int
{
	charsonly := 0;
	case(len cp.text){
	0 =>
		break;
	1 =>
		if(cp.text[0] == '#'){
			charsonly = 1;
			break;
		}
	* =>
		charsonly = 1;
		editerror("newline expected");
	}
	printposn(t, charsonly);
	return 1;
}

nl_cmd(t: ref Edit, cp: ref Cmd): int
{
	if(cp.addr == nil){
		# First put it on newline boundaries
		a := mkaddr(t);
		addr = lineaddr(0, a, -1);
		a = lineaddr(0, a, 1);
		addr.r.q1 = a.r.q1;
		if(addr.r.q0==t.q0 && addr.r.q1==t.q1){
			a = mkaddr(t);
			addr = lineaddr(1, a, 1);
		}
	}
	t.q0 = addr.r.q0;
	t.q1 = addr.r.q1;
	t.edited |= Esel;
	return 1;
}

append(f: ref Edit, cp: ref Cmd, p: int): int
{
	if(len cp.text > 0)
		eloginsert(f, p, cp.text);
	return 1;
}

pdisplay(f: ref Edit): int
{
	p1 := addr.r.q0;
	p2 := addr.r.q1;
	if(p2 > f.buf.blen())
		p2 = f.buf.blen();
	if(p1 < p2)
		warnc <-= f.buf.gets(p1, p2 - p1);
	f.q0 = addr.r.q0;
	f.q1 = addr.r.q1;
	f.edited |= Esel;
	return 1;
}

filename(f: ref Edit): string
{
	dirt := cur := ' ';
	if(f.dirty)
		dirt = '\'';
	if(seled == f)
		cur = '.';
	return sprint("%c+%c %s\n", dirt, cur, f.path);
}

loopcmd(f: ref Edit, cp: ref Cmd, rp: array of Range)
{
	for(i:=0; i<len rp; i++){
		f.q0 = rp[i].q0;
		f.q1 = rp[i].q1;
		cmdexec(f, cp);
	}
}

looper(f: ref Edit, cp: ref Cmd, xy: int)
{
	p, op, nrp, ok: int;
	r, tr: Range;
	rp: array of  Range;

	r = addr.r;
	if(xy)
		op = -1;
	else
		op = r.q0;
	nest++;
	if(rxcompile(cp.re) == 0)
		editerror(sprint("bad regexp in '%c' command", cp.cmdc));
	nrp = 0;
	rp = nil;
	for(p = r.q0; p<=r.q1; ){
		(ok, sel) = rxexecute(f.buf, nil, p, r.q1);
		if(!ok){ # no match, but y should still run
			if(xy || op>r.q1)
				break;
			tr.q0 = op;
			tr.q1 = r.q1;
			p = r.q1+1;	# exit next loop
		}else{
			if(sel[0].q0==sel[0].q1){	# empty match?
				if(sel[0].q0==op){
					p++;
					continue;
				}
				p = sel[0].q1+1;
			}else
				p = sel[0].q1;
			if(xy)
				tr = sel[0];
			else{
				tr.q0 = op;
				tr.q1 = sel[0].q0;
			}
		}
		op = sel[0].q1;
		nrp++;
		orp := rp;
		rp = array[nrp] of Range;
		rp[0: ] = orp[0: nrp-1];
		rp[nrp-1] = tr;
		orp = nil;
	}
	loopcmd(f, cp.cmd, rp);
	rp = nil;
	--nest;
}

linelooper(f: ref Edit, cp: ref Cmd)
{
	nrp, p: int;
	r, linesel: Range;
	a, a3: Address;
	rp: array of Range;

	nest++;
	nrp = 0;
	rp = nil;
	r = addr.r;
	a3.f = f;
	a3.r.q0 = a3.r.q1 = r.q0;
	a = lineaddr(0, a3, 1);
	linesel = a.r;
	for(p = r.q0; p<r.q1; p = a3.r.q1){
		a3.r.q0 = a3.r.q1;
		if(p!=r.q0 || linesel.q1==p){
			a = lineaddr(1, a3, 1);
			linesel = a.r;
		}
		if(linesel.q0 >= r.q1)
			break;
		if(linesel.q1 >= r.q1)
			linesel.q1 = r.q1;
		if(linesel.q1 > linesel.q0)
			if(linesel.q0>=a3.r.q1 && linesel.q1>a3.r.q1){
				a3.r = linesel;
				nrp++;
				orp := rp;
				rp = array[nrp] of Range;
				rp[0: ] = orp[0: nrp-1];
				rp[nrp-1] = linesel;
				orp = nil;
				continue;
			}
		break;
	}
	loopcmd(f, cp.cmd, rp);
	rp = nil;
	--nest;
}

panelctl(p: string, ctl: string): int
{
	fname := p + "/ctl";
	fd := open(fname, OWRITE);
	if(fd == nil)
		return -1;
	return fprint(fd, "%s", ctl);
}

dirpanels(path: string): list of string
{
	fd := open(omero + path, OREAD);
	if(fd == nil)
		return nil;
	(dirs, n) := readdir->readall(fd, Readdir->NAME|Readdir->DESCENDING);
	if(n <= 0)
		return nil;
	l: list of string;
	for(i := 0; i < n; i++)
		if(dirs[i].qid.qtype&QTDIR)
			l = path+"/"+dirs[i].name::l;
	return l;
}

concat(l1, l2: list of string): list of string
{
	if(l1 == nil)
		return l2;
	if(l2 == nil)
		return l1;
	return hd l1::concat(tl l1, l2);
}

panellist(): list of string
{
	l := dirpanels("/appl");
	for(scrs := screens(); scrs != nil; scrs = tl scrs){
		# BUG: should recur and find appl (not layout) panels
		cols := concat(rows(hd scrs), cols(hd scrs));
		for(; cols != nil; cols = tl cols){
fprint(stderr, "col %s\n", hd cols);
			l = concat(l, dirpanels(hd cols));
		}
	}
	return l;
}

panelmatch(f: string, r: string): int
{
	if(rxcompile(r) == 0)
		editerror("bad regexp in panel match");
	(match, nil) := rxexecute(nil, f, 0, len f);
	return match;
}

matchpanels(re: string, PQ: int): list of string
{
	edl: list of string;
	for(pl := panellist(); pl != nil; pl = tl pl)
		if(re == nil || panelmatch(hd pl, re) == PQ)
			edl = hd pl::edl;
	return edl;
}

cmdpanel(): string
{
	path := readdev("/mnt/snarf/sel", nil);
	if(path == nil)
		editerror("no current edit");
	(p, nil) := splitstrl(path, "/col:ox.");
	(p, nil) = splitstrl(p, "/col:tree.");
	(nil, p) = splitstrr(p, omero );
	return p;
}

panellooper(cp: ref Cmd, PQ: int)
{
	if(Glooping++)
		editerror(sprint("can't nest %c command", "QP"[PQ]));
	nest++;

	for(edl := matchpanels(cp.re, PQ); edl != nil; edl = tl edl)
		case cp.cmd.cmdc {
		'f' =>
			warnc <-= hd edl + "\n";
		'D'=>
			panelctl(omero  + hd edl, "exec Close");
		'e' =>
			p := cmdpanel();
			if(cp.cmd.text != nil)
				p = cp.cmd.text;
			if(panelctl(omero + hd edl, "copyto " + p ) < 0)
			  editerror(sprint("%s: copyto %s: %r", hd edl, p));
		* =>
			editerror(sprint("bad cmd in '%c' command", "QP"[PQ]));
		}
	--Glooping;
	--nest;
}

P_cmd(nil: ref Edit, cp: ref Cmd): int
{
	panellooper(cp, cp.cmdc=='P');
	return 1;
}

matchfiles(re: string, XY: int): list of ref Edit
{
	edl: list of ref Edit;
	edl = nil;
	for(trl := trees; trl != nil; trl = tl trl)
		for(eds := (hd trl).eds; eds != nil; eds = tl eds)
			if(re == nil || filematch(hd eds, re) == XY){
				edl = hd eds::edl;
			}
	return edl;
}

filelooper(cp: ref Cmd, XY: int)
{
	if(Glooping++)
		editerror(sprint("can't nest %c command", "YX"[XY]));
	nest++;

	for(edl := matchfiles(cp.re, XY); edl != nil; edl = tl edl)
		cmdexec(hd edl, cp.cmd);

	--Glooping;
	--nest;
}

nextmatch(f: ref Edit, r: string, p: int, sign: int)
{
	ok: int;

	if(rxcompile(r) == 0)
		editerror("bad regexp in command address");
	if(sign >= 0){
		(ok, sel) = rxexecute(f.buf, nil, p, 16r7FFFFFFF);
		if(!ok)
			editerror("no match for regexp");
		if(sel[0].q0==sel[0].q1 && sel[0].q0==p){
			if(++p>f.buf.blen())
				p = 0;
			(ok, sel) = rxexecute(f.buf, nil, p, 16r7FFFFFFF);
			if(!ok)
				editerror("address");
		}
	}else{
		(ok, sel) = rxbexecute(f.buf, p);
		if(!ok)
			editerror("no match for regexp");
		if(sel[0].q0==sel[0].q1 && sel[0].q1==p){
			if(--p<0)
				p = f.buf.blen();
			(ok, sel) = rxbexecute(f.buf, p);
			if(!ok)
				editerror("address");
		}
	}
}

cmdaddress(ap: ref Addr, a: Address, sign: int): Address
{
	f := a.f;
	a1, a2: Address;

	do{
		case(ap.typex){
		'l' or
		'#' =>
			if(ap.typex == '#')
				a = charaddr(ap.num, a, sign);
			else
				a = lineaddr(ap.num, a, sign);
			break;

		'.' =>
			a = mkaddr(f);
			break;

		'$' =>
			a.r.q0 = a.r.q1 = f.buf.blen();
			break;

		'\'' =>
editerror("can't handle '");
#			a.r = f.mark;
			break;

		'?' =>
			sign = -sign;
			if(sign == 0)
				sign = -1;
			if(sign >= 0)
				v := a.r.q1;
			else
				v = a.r.q0;
			nextmatch(f, ap.re, v, sign);
			a.r = sel[0];
			break;

		'/' =>
			if(sign >= 0)
				v := a.r.q1;
			else
				v = a.r.q0;
			nextmatch(f, ap.re, v, sign);
			a.r = sel[0];
			break;

		'"' =>
			eds := matchfiles(ap.re, 0);
			if(eds == nil)
				editerror("no file matches");
			f = hd eds;
			a = mkaddr(f);
			break;

		'*' =>
			a.r.q0 = 0;
			a.r.q1 = f.buf.blen();
			return a;

		',' or
		';' =>
			if(ap.left!=nil)
				a1 = cmdaddress(ap.left, a, 0);
			else{
				a1.f = a.f;
				a1.r.q0 = a1.r.q1 = 0;
			}
			if(ap.typex == ';'){
				f = a1.f;
				a = a1;
				f.q0 = a1.r.q0;
				f.q1 = a1.r.q1;
			}
			if(ap.next!=nil)
				a2 = cmdaddress(ap.next, a, 0);
			else{
				a2.f = a.f;
				a2.r.q0 = a2.r.q1 = f.buf.blen();
			}
			if(a1.f != a2.f)
				editerror("addresses in different files");
			a.f = a1.f;
			a.r.q0 = a1.r.q0;
			a.r.q1 = a2.r.q1;
			if(a.r.q1 < a.r.q0)
				editerror("addresses out of order");
			return a;

		'+' or
		'-' =>
			sign = 1;
			if(ap.typex == '-')
				sign = -1;
			if(ap.next==nil || ap.next.typex=='+' || ap.next.typex=='-')
				a = lineaddr(1, a, sign);
			break;
		* =>
			error("cmdaddress");
			return a;
		}
	}while((ap = ap.next)!=nil);	# assign =
	return a;
}

filematch(f: ref Edit, r: string): int
{
	if(rxcompile(r) == 0)
		editerror("bad regexp in file match");
	buf := filename(f);
	(match, nil) := rxexecute(nil, buf, 0, len buf);
	return match;
}

charaddr(l: int, addr: Address, sign: int): Address
{
	if(sign == 0)
		addr.r.q0 = addr.r.q1 = l;
	else if(sign < 0)
		addr.r.q1 = addr.r.q0 -= l;
	else if(sign > 0)
		addr.r.q0 = addr.r.q1 += l;
	if(addr.r.q0<0 || addr.r.q1>addr.f.buf.blen())
		editerror("address out of range");
	return addr;
}

lineaddr(l: int, addr: Address, sign: int): Address
{
	n: int;
	c: int;
	f := addr.f;
	a: Address;
	p: int;

	a.f = f;
	if(sign >= 0){
		bl := f.buf.blen();
		if(l == 0){
			if(sign==0 || addr.r.q1==0){
				a.r.q0 = a.r.q1 = 0;
				return a;
			}
			a.r.q0 = addr.r.q1;
			p = addr.r.q1-1;
		}else{
			if(sign==0 || addr.r.q1==0){
				p = 0;
				n = 1;
			}else{
				p = addr.r.q1-1;
				n = f.buf.getc(p++)=='\n';
			}
			while(n < l){
				if(p >= bl)
					editerror("address out of range");
				if(f.buf.getc(p++) == '\n')
					n++;
			}
			a.r.q0 = p;
		}
		while(p < bl && f.buf.getc(p++)!='\n')
			;
		a.r.q1 = p;
	}else{
		p = addr.r.q0;
		if(l == 0)
			a.r.q1 = addr.r.q0;
		else{
			for(n = 0; n<l; ){	# always runs once
				if(p == 0){
					if(++n != l)
						editerror("address out of range");
				}else{
					c = f.buf.getc(p-1);
					if(c != '\n' || ++n != l)
						p--;
				}
			}
			a.r.q1 = p;
			if(p > 0)
				p--;
		}
		while(p > 0 && f.buf.getc(p-1)!='\n')	# lines start after a newline
			p--;
		a.r.q0 = p;
	}
	return a;
}

cmdname(f: ref Edit, str: string): string
{
	r := string nil;
	if(len str == 0){
		# no name; use existing
		return f.path;
	}
	str = skipbl(str);
	if(len str > 0){
		if(str[0] == '/')
			r = str;
		else
			r = cleanname(rooted(f.dir, str));
	}
	return r;
}

copysel(rs: Rangeset): Rangeset
{
	nrs := array[NRange] of Range;
	for(i := 0; i < NRange; i++)
		nrs[i] = rs[i];
	return nrs;
}
