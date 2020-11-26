# Sam language taken from acme.
# This file was /appl/acme/edit.b, changed for o/x.

#
#	limbo -I /pc/usr/octopus/module regx.b
#

# Main entry point for sam commands.
# This contains the parser and the main loop.
# Calls to cmdexec() (samcmd.b) to actually execute the commands.

implement Sam;
include "mods.m";
	Inactive, Inserting, Collecting, resetxec, cmdexec: import samcmd;
	elogterm, elogapply: import samlog;
	debug, Tree, Edit, seled, trees, Ename, Esel, Null, Empty: import oxedit;
	msg: import oxex;
	readdev: import io;

init(d: Oxdat)
{
	initmods(d->mods);
	editing = Inactive;
}

linex: con "\n";
wordx: con "\t\n";


# Main tab of Sam commands.
# Editing commands remain like in Sam and Acme.
# File commands have to change, because of the editing model implied by o/mero.
cmdtab = array[] of {
#	  cmdc	text exp addr defcmd	defaddr	count	token	fn
	Cmdt ( '\n',	0, 0, 0,	0,	aDot,	0,	nil,	C_nl ),
	Cmdt ( 'a',	1, 0, 0,	0,	aDot,	0,	nil,	C_a ),
	Cmdt ( 'c',	1, 0, 0,	0,	aDot,	0,	nil,	C_c ),
	Cmdt ( 'd',	0, 0, 0,	0,	aDot,	0,	nil,	C_d ),
	Cmdt ( 'e',	0, 0, 0,	0,	aNo,	0,	wordx,	C_e ),
	Cmdt ( 'f',	0, 0, 0,	0,	aNo,	0,	wordx,	C_f ),
	Cmdt ( 'g',	0, 1, 0,	'p',	aDot,	0,	nil,	C_g ),
	Cmdt ( 'i',	1, 0, 0,	0,	aDot,	0,	nil,	C_i ),
	Cmdt ( 'm',	0, 0, 1,	0,	aDot,	0,	nil,	C_m ),
	Cmdt ( 'n',	0, 0, 0,	0,	aNo,	0,	nil,	C_n ),
	Cmdt ( 'p',	0, 0, 0,	0,	aDot,	0,	nil,	C_p ),
	Cmdt ( 'r',	0, 0, 0,	0,	aDot,	0,	wordx,	C_e ),
	Cmdt ( 's',	0, 1, 0,	0,	aDot,	1,	nil,	C_s ),
	Cmdt ( 't',	0, 0, 1,	0,	aDot,	0,	nil,	C_m ),
	Cmdt ( 'v',	0, 1, 0,	'p',	aDot,	0,	nil,	C_g ),
	Cmdt ( 'w',	0, 0, 0,	0,	aAll,	0,	wordx,	C_w ),
	Cmdt ( 'x',	0, 1, 0,	'p',	aDot,	0,	nil,	C_x ),
	Cmdt ( 'y',	0, 1, 0,	'p',	aDot,	0,	nil,	C_x ),
	Cmdt ( '=',	0, 0, 0,	0,	aDot,	0,	linex,	C_eq ),
	Cmdt ( 'B',	0, 0, 0,	0,	aNo,	0,	linex,	C_B ),
	Cmdt ( 'D',	0, 0, 0,	0,	aNo,	0,	linex,	C_D ),
	Cmdt ( 'X',	0, 1, 0,	'f',	aNo,	0,	nil,	C_X ),
	Cmdt ( 'Y',	0, 1, 0,	'f',	aNo,	0,	nil,	C_X ),
	Cmdt ( 'P',	0, 1, 0,	'f',	aNo,	0,	nil,	C_P ),
	Cmdt ( 'Q',	0, 1, 0,	'f',	aNo,	0,	nil,	C_P ),
	Cmdt ( '<',	0, 0, 0,	0,	aDot,	0,	linex,	C_pipe ),
	Cmdt ( '|',	0, 0, 0,	0,	aDot,	0,	linex,	C_pipe ),
	Cmdt ( '>',	0, 0, 0,	0,	aDot,	0,	linex,	C_pipe ),
	# deliberately unimplemented
	# could perhaps implement '!' to execute the command in the current buffer
	# as if it was executed in o/x by the user. Eg. "X ! Ctl tab 4"
	# Cmdt ( 'b',	0, 0, 0,	0,	aNo,	0,	linex,	C_b ),
	# Cmdt ( 'k',	0, 0, 0,	0,	aDot,	0,	nil,	C_k ),
	# Cmdt ( 'q',	0, 0, 0,	0,	aNo,	0,	nil,	C_q ),
	# Cmdt ( 'u',	0, 0, 0,	0,	aNo,	2,	nil,	C_u ),
	# Cmdt ( '!',	0, 0, 0,	0,	aNo,	0,	linex,	C_plan9 ),
	Cmdt (0,	0, 0, 0,	0,	0,	0,	nil,	-1 )
};

# buffer that keeps the command
cmdstartp: string;
cmdendp: int;
cmdp: int;
editerrc: chan of string;

lastpat := "";
patset: int;

# notify edit completion process
editwaitproc(pid : int, sync: chan of int, cwait: chan of string)
{
	fd : ref Sys->FD;
	n : int;

	sys->pctl(Sys->FORKFD, nil);
	w := sprint("#p/%d/wait", pid);
	fd = sys->open(w, Sys->OREAD);
	if(fd == nil)
		error("fd == nil in editwaitproc");
	sync <-= sys->pctl(0, nil);
	buf := array[Sys->WAITLEN] of byte;
	status := "";
	for(;;){
		if((n = sys->read(fd, buf, len buf))<0)
			error("bad read in editwaitproc");
		status = string buf[0:n];
		cwait <-= status;
	}
}

# main loop: parsecmd and cmdexec for the edit.
# The command is kept at cmdstartp[0:cmdendp],
editthread(nil: chan of string)
{
	cmdp: ref Cmd;

	while((cmdp=parsecmd(0)) != nil){
		seled.getedits();
		if(debug)
			fprint(stderr, "%s: edit cmd %c\n",
				seled.path, cmdp.cmdc);
		if(cmdexec(seled, cmdp) == 0)
			break;
	}
	editerrc <-= nil;
}

puttag(ed: ref Edit)
{
	fname := ed.tag.path+"/data";
	tagtext := readdev(fname, nil);
	if(tagtext == nil)
		return;
	fd := open(fname, OWRITE|OTRUNC);
	if(fd == nil)
		return;
	(nil, rtag) := splitl(tagtext, " \t\n");
	data := array of byte sprint("%s %s", ed.path, rtag);
	if(write(fd, data, len data) != len data)
		error (sprint("o/x: new: write: %r\n"));
	fd = nil;
}

putededits(mtr: ref Tree, ed: ref Edit, dir: string)
{
	if(debug > 1)
		fprint(stderr, "putedits ed %s flag %d elog %c q0 %d q1 %d\n",
			ed.path, ed.edited, ed.elog.typex, ed.q0, ed.q1);
	if(ed.elog != nil)
		if(ed.elog.typex == Null)
			elogterm(ed);
		else if(ed.elog.typex != Empty){
			if(elogapply(ed) < 0){
				m := sprint("sam: %s: %r\n", ed.path);
				msg(mtr, dir, m);
			} else {
				if(ed.edited&Ename)
					puttag(ed);
			}
		}
	if(ed.edited&Esel)
		ed.body.ctl(sprint("sel %d %d\n", ed.q0, ed.q1));
	ed.clredits();
}

putedits(mtr: ref Tree, dir: string)
{
	for(l := trees; l != nil; l = tl l){
		tr := hd l;
		for(eds := tr.eds; eds != nil; eds = tl eds)
			putededits(mtr, hd eds, dir);
	}
}

clredits()
{
	for(l := trees; l != nil; l = tl l){
		tr := hd l;
		for(eds := tr.eds; eds != nil; eds = tl eds){
			ed := hd eds;
			ed.clredits();
			elogterm(ed);
		}
	}
}

# Terminates the process after aborting
editerror(s: string)
{
	clredits();
	editerrc <-= s;
	exit;
}

warnthread(tr: ref Tree, d: string, c: chan of string)
{
	some := 0;

	while((s := <-c) != nil){
		some++;
		msg(tr, d, s);
	}
	if(some)
		msg(tr, d, "\n");
}

# fills the buffer at cmdstartp with the command (\n terminated)
# and starts the edit thread, then awaits for completion.
editcmd(ct: ref Edit, r: string)
{
	if(ct == nil)
		return;
	tr := Tree.find(ct.tid);
	if(len r == 0)
		return;
	if(2*(len r) > BUFSIZE){
		msg(tr, ct.dir, "string too long\n");
		return;
	}
	cwait := chan of string;
	cmdstartp = r;
	if(r[len r - 1] != '\n')
		cmdstartp[len r] = '\n';
	cmdendp = len r;
	cmdp = 0;
	if(ct.body == nil)
		seled = nil;
	else
		seled = ct;
	resetxec();
	if(editerrc == nil){
		editerrc = chan of string;
		lastpat = "";
	}
	warnc = chan of string;
	spawn warnthread(tr, ct.dir, warnc);
	spawn editthread(cwait);
	e := <- editerrc;
	editing = Inactive;
	warnc <-= nil;
	warnc = nil;
	if(e != nil)
		msg(tr, ct.dir,sprint("sam: %s\n", e));

	putedits(tr, ct.dir);
}

#
# Command parsing
#

getch(): int
{
	if(cmdp == cmdendp)
		return -1;
	return cmdstartp[cmdp++];
}

nextc(): int
{
	if(cmdp == cmdendp)
		return -1;
	return cmdstartp[cmdp];
}

ungetch()
{
	if(--cmdp < 0)
		error("ungetch");
}

getnum(signok: int): int
{
	n: int;
	c, sign: int;

	n = 0;
	sign = 1;
	if(signok>1 && nextc()=='-'){
		sign = -1;
		getch();
	}
	if((c=nextc())<'0' || '9'<c)	# no number defaults to 1
		return sign;
	while('0'<=(c=getch()) && c<='9')
		n = n*10 + (c-'0');
	ungetch();
	return sign*n;
}

cmdskipbl(): int
{
	c: int;
	do
		c = getch();
	while(c==' ' || c=='\t');
	if(c >= 0)
		ungetch();
	return c;
}

okdelim(c: int)
{
	if(c=='\\' || ('a'<=c && c<='z')
	|| ('A'<=c && c<='Z') || ('0'<=c && c<='9'))
		editerror(sprint("bad delimiter %c\n", c));
}

atnl()
{
	c: int;

	cmdskipbl();
	c = getch();
	if(c != '\n')
		editerror(sprint("newline expected (saw %c)", c));
}

getrhs(delim: int, cmd: int): string
{
	c: int;

	s := "";
	while((c = getch())>0 && c!=delim && c!='\n'){
		if(c == '\\'){
			if((c=getch()) <= 0)
				error("bad right hand side");
			if(c == '\n'){
				ungetch();
				c='\\';
			}else if(c == 'n')
				c='\n';
			else if(c!=delim && (cmd=='s' || c!='\\'))
				# s does its own
				s[len s] = '\\';
		}
		s[len s] = c;
	}
	ungetch();	# let client read whether delimiter, '\n' or whatever
	return s;
}

collecttoken(end: string): string
{
	c: int;

	s := "";

	while((c=nextc())==' ' || c=='\t')
		s[len s] = getch(); # blanks significant for getname()
	while((c=getch())>0 && strchr(end, c)<0)
		s[len s] = c;
	if(c != '\n')
		atnl();
	return s;
}

collecttext(): string
{
	begline, i, c, delim: int;

	s := "";
	if(cmdskipbl()=='\n'){
		getch();
		i = 0;
		do{
			begline = i;
			while((c = getch())>0 && c!='\n'){
				i++;
				s[len s] = c;
			}
			i++;
			s[len s] = '\n';
			if(c < 0)
				return s;
		}while(s[begline]!='.' || s[begline+1]!='\n');
		s = s[0:len s - 2];
	}else{
		okdelim(delim = getch());
		s = getrhs(delim, 'a');
		if(nextc()==delim)
			getch();
		atnl();
	}
	return s;
}

cmdlookup(c: int): int
{
	i: int;

	for(i=0; cmdtab[i].cmdc; i++)
		if(cmdtab[i].cmdc == c)
			return i;
	return -1;
}

parsecmd(nest: int): ref Cmd
{
	i, c: int;
	cp, ncp: ref Cmd;
	cmd: ref Cmd;

	cmd = ref Cmd;
	cmd.next = cmd.cmd = nil;
	cmd.re = nil;
	cmd.flag = cmd.num = 0;
	cmd.addr = compoundaddr();
	if(cmdskipbl() == -1)
		return nil;
	if((c=getch())==-1)
		return nil;
	cmd.cmdc = c;
	if(cmd.cmdc=='c' && nextc()=='d'){	# sleazy two-character case
		getch();		# the 'd'
		cmd.cmdc='c'|16r100;
	}
	i = cmdlookup(cmd.cmdc);
	if(i >= 0){
		if(cmd.cmdc == '\n'){
			cp = ref Cmd;
			*cp = *cmd;
			return cp;
			# let nl_cmd work it all out
		}
		ct := cmdtab[i];
		if(ct.defaddr==aNo && cmd.addr != nil)
			editerror("command takes no address");
		if(ct.count)
			cmd.num = getnum(ct.count);
		if(ct.regexp){
			# x without pattern -> .*\n, indicated by cmd.re==0
			# X without pattern is all files
			if((ct.cmdc!='x' && ct.cmdc!='X' && ct.cmdc!='P') ||
			   ((c = nextc())!=' ' && c!='\t' && c!='\n')){
				cmdskipbl();
				if((c = getch())=='\n' || c<0)
					editerror("no address");
				okdelim(c);
				cmd.re = getregexp(c);
				if(ct.cmdc == 's'){
					cmd.text = getrhs(c, 's');
					if(nextc() == c){
						getch();
						if(nextc() == 'g')
							cmd.flag = getch();
					}
			
				}
			}
		}
		if(ct.addr && (cmd.mtaddr=simpleaddr())==nil)
			editerror("bad address");
		if(ct.defcmd){
			if(cmdskipbl() == '\n'){
				getch();
				cmd.cmd = ref Cmd;
				cmd.cmd.cmdc = ct.defcmd;
			}else if((cmd.cmd = parsecmd(nest))==nil)
				error("defcmd");
		}else if(ct.text)
			cmd.text = collecttext();
		else if(ct.token != nil)
			cmd.text = collecttoken(ct.token);
		else
			atnl();
	}else
		case(cmd.cmdc){
		'{' =>
			cp = nil;
			do{
				if(cmdskipbl()=='\n')
					getch();
				ncp = parsecmd(nest+1);
				if(cp != nil)
					cp.next = ncp;
				else
					cmd.cmd = ncp;
			}while((cp = ncp) != nil);
			break;
		'}' =>
			atnl();
			if(nest==0)
				editerror("right brace with no left brace");
			return nil;
		'c'|16r100 =>
			editerror("unimplemented command cd");
		* =>
			editerror(sprint("unknown command %c", cmd.cmdc));
		}
	cp = ref Cmd;
	*cp = *cmd;
	return cp;
}

getregexp(delim: int): string
{
	c: int;
	buf := "";
	for(i:=0; ; i++){
		if((c = getch())=='\\'){
			if(nextc()==delim)
				c = getch();
			else if(nextc()=='\\'){
				buf[len buf] = c;
				c = getch();
			}
		}else if(c==delim || c=='\n')
			break;
		if(i >= BUFSIZE)
			editerror("regular expression too long");
		buf[len buf] = c;
	}
	if(c!=delim && c)
		ungetch();
	if(len buf> 0){
		patset = 1;
		lastpat = buf;
	}
	if(len lastpat== 0)
		editerror("no regular expression defined");
	return lastpat;
}

simpleaddr(): ref Addr
{
	addr: Addr;
	ap, nap: ref Addr;

	addr.next = nil;
	addr.left = nil;
	case(cmdskipbl()){
	'#' =>
		addr.typex = getch();
		addr.num = getnum(1);
		break;
	'0' to '9' =>
		addr.num = getnum(1);
		addr.typex='l';
		break;
	'/' or '?' or '"' =>
		addr.re = getregexp(addr.typex = getch());
		break;
	'.' or
	'$' or
	'+' or
	'-' or
	'\'' =>
		addr.typex = getch();
		break;
	* =>
		return nil;
	}
	if((addr.next = simpleaddr()) != nil)
		case(addr.next.typex){
		'.' or
		'$' or
		'\'' =>
			if(addr.typex!='"')
				editerror("bad address syntax");
			break;
		'"' =>
			editerror("bad address syntax");
			break;
		'l' or
		'#' =>
			if(addr.typex=='"')
				break;
			if(addr.typex!='+' && addr.typex!='-'){
				# insert the missing '+'
				nap = ref Addr;
				nap.typex='+';
				nap.next = addr.next;
				addr.next = nap;
			}
			break;
		'/' or
		'?' =>
			if(addr.typex!='+' && addr.typex!='-'){
				# insert the missing '+'
				nap = ref Addr;
				nap.typex='+';
				nap.next = addr.next;
				addr.next = nap;
			}
			break;
		'+' or
		'-' =>
			break;
		* =>
			error("simpleaddr");
		}
	ap = ref Addr;
	*ap = addr;
	return ap;
}

compoundaddr(): ref Addr
{
	addr: Addr;
	ap, next: ref Addr;

	addr.left = simpleaddr();
	if((addr.typex = cmdskipbl())!=',' && addr.typex!=';')
		return addr.left;
	getch();
	next = addr.next = compoundaddr();
	if(next != nil && (next.typex==',' || next.typex==';') && next.left==nil)
		editerror("bad address syntax");
	ap = ref Addr;
	*ap = addr;
	return ap;
}

