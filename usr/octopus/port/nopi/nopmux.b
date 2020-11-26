implement Nopmux;
#
# Nop multiplexor for the import program
#
include "sys.m";
	sys: Sys;
	fprint, OREAD, open, pwrite, pread, remove, sprint,
	pctl, millisec, DMDIR, write, nulldir, tokenize, fildes,
	QTDIR, FD, read, create, OWRITE, ORDWR, Dir, Qid: import sys;
include "error.m";
	err: Error;
	stderr, panic: import err;
include "nop.m";
	nop: Nop;

Nopcall: adt {
	req: ref Tmsg;
	repc: chan of ref Rmsg;
};

opc : chan of ref Nopcall;

init(msys: Sys, merr: Error, mnop: Nop, ofd: ref FD)
{
	sys = msys;
	err = merr;
	nop = mnop;
	opc = chan of ref Nopcall;
	oprc:= chan of ref Rmsg;
	spawn noprdproc(ofd, oprc);
	spawn nopmuxproc(ofd, opc, oprc, endc);
}

noprdproc(ofd: ref FD, oprc: chan of ref Rmsg)
{
	oprdprocpid = pctl(0, nil);

	if(debug)
		fprint(stderr, "nopmuxproc\n");
	for(;;){
		m := Rmsg.read(ofd, 0);
		if(debug){
			if(m == nil)
				fprint(stderr, "noprdproc: eof\n");
		}
		oprc <-= m;
		if(m == nil)
			break;
	}
	if(debug)
		fprint(stderr, "noprdproc: exit\n");
}

nopmuxproc(ofd: ref FD, opcc: chan of ref Nopcall, oprc: chan of ref Rmsg, endc: chan of string)
{
	reqs: list of ref Nopcall;	# outstanding ones.

	broken := 0;
	for(;;) alt {
	m := <- opcc =>
		now := millisec();
		if(debug && reqs != nil)
			rdump(reqs);
		if(m == nil){
			if(debug) fprint(stderr, "nopmux:  eof\n");
			abortall(reqs);
			kill(noprdprocpid, "kill");
			endc <-= "hangup: eof";
			exit;
		}
		if(debug)
		fprint(stderr, "\n%d\t<-nop- %s\n", now, m.req.text());
		if(broken){
			r := ref Rmsg.Error(m.req.tag, "i/o error");
			if(debug)
			fprint(stderr, "\n%d\t-nop-> %s\n",
				now, r.text());
			m.repc <-= r;
			continue;
		}
		tmsg := m.req.pack();
		nw := write(ofd, tmsg, len tmsg);
		reqs = m :: reqs;
		if(len reqs > stats.nconc)
			stats.nconc = len reqs;
		if(nw != len tmsg){
			fprint(stderr, "nopmux: write: %r\n");
			m.repc <-= ref Rmsg.Error(m.req.tag, "i/o error");
			abortall(reqs);
			kill(noprdprocpid, "kill");
			endc <-= "hangup: write";
			exit;
		}
	rmsg := <- oprc =>
		m: ref Nopcall;
		last: int;
		if(rmsg == nil){
			fprint(stderr, "nopmux: hangup: read\n");
			abortall(reqs);
			kill(noprdprocpid, "kill");
			endc <-= "hangup: read";
			broken = 1;
			exit;
		}
		(m, reqs, last) = muxreply(reqs, rmsg);
		if(m == nil || m.repc == nil){
			fprint(stderr, "nil reply o no reply chan\n");
			continue;
		}
		if(debug)
		fprint(stderr, "%d\t-nop-> %s\n\n",
			millisec(), rmsg.text());
		m.repc <-= rmsg;
	}
	kill(noprdprocpid, "kill");
}

muxreply(reqs: list of ref Nopcall, rmsg: ref Rmsg): (ref Nopcall, list of ref Nopcall, int)
{
	nreqs : list of ref Nopcall;
	call: ref Nopcall;
	done := 1;
	flushed := ~0;
	pick fmsg := rmsg {
	Flush =>
		for(l := reqs; l != nil && flushed == 0; l = tl l){
			m := hd l;
			if(m.req.tag == rmsg.tag)
			pick freq := m.req {
			Flush =>
				flushed = freq.oldtag;
			}
		}
	}
	for(; reqs != nil; reqs = tl reqs){
		m := hd reqs;
		if(m.req.tag == flushed){
			m.repc <-= ref Rmsg.Error(m.req.tag, "flushed");
		} else if(m.req.tag != rmsg.tag)
			nreqs = m :: nreqs;
		else {
			call = m;
			pick req := m.req {
			Get =>
				req.nmsgs = XXX;
				done =  XXX;
			}
			if(!done)
				nreqs = m::nreqs;
		}
	}
	if(call == nil)
		fprint(stderr, "nopmux: no request for %s\n", rmsg.text());
	else if(tagof(rmsg) != tagof(Rmsg.Error) && rmsg.mtype() != call.req.mtype()+1){
		fprint(stderr, "nopmux: type mismatch:\n");
		fprint(stderr, "\tcall: %s\n\treply:%s\n", rmsg.text(), call.req.text());
	}
	return (call, nreqs, done);
}

rdump(reqs: list of ref Nopcall)
{
	stats.dump();
	while(reqs != nil){
		fprint(stderr, "\t- %s\n", (hd reqs).req.text());
		reqs = tl reqs;
	}
}

abortall(reqs: list of ref Nopcall)
{
	if(debug)
		fprint(stderr, "nopmux: aborting\n");
	while(reqs != nil){
		m := hd reqs;
		m.repc <-= ref Rmsg.Error(m.req.tag, "i/o error");
		reqs = tl reqs;
	}
}

rpc(t: ref Tmsg) : chan of ref Rmsg
{
	rc := chan[1] of ref Rmsg;
	if(opc == nil)
		fprint(stderr, "nopmux: nil opc");
	opc <-= ref Nopcall(t, rc);
	return rc;
}

get(path: string, ofd, mode, cnt: int, off: big): (int, ref Sys->Dir, array of byte, string)
{
}


put(path:string,ofd,mode: int,d: ref Dir,a: array of byte,off: big,async: int): (int, ref Dir, string)
{
}

clunk(ofd: int)
{
	async;
}

remove(path: string, async: int): string
{
}

