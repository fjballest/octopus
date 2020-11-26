implement Opmux;
include "sys.m";
	sys: Sys;
	write, millisec, pctl, fprint, fildes, QTDIR, FD: import sys;
include "op.m";
	op: Op;
	Tmsg, Rmsg, ODATA, OSTAT, OMORE: import op;
include "error.m";
	err: Error;
	stderr, kill: import err;

include "opmux.m";

Opcall: adt {
	req: ref Op->Tmsg;
	repc: chan of ref Op->Rmsg;
};

Stats: adt {
	nput, nget, nremove, nflush, nconc, nrecover: int;

	dump: fn(s: self ref Stats);
};

#
# Tags must be assigned by clients, so that the mux knows
# how to flush a Tag
#

opc : chan of ref Opcall;
oprdprocpid: int;
stats: ref Stats;

init(ofd: ref Sys->FD, o: Op, endc: chan of string)
{
	sys = load Sys Sys->PATH;
	err = load Error Error->PATH;
	err->init(sys);
	op = o;
	stats = ref Stats(0, 0, 0, 0, 0, 0);
	opc = chan of ref Opcall;
	oprc:= chan of ref Rmsg;
	spawn oprdproc(ofd, oprc);
	<-oprc;
	spawn opmuxproc(ofd, opc, oprc, endc);
}

term()
{
	opc <-= nil;
}
recover(ofd: ref FD, oprc: chan of ref Rmsg, reqs: list of ref Opcall): list of ref Opcall
{
	kill(oprdprocpid, "kill");
	spawn oprdproc(ofd, oprc);
	<-oprc;
	l: list of ref Opcall;
	for(; reqs != nil; reqs = tl reqs){
		m := hd reqs;
		tmsg := m.req.pack();
		nw := write(ofd, tmsg, len tmsg);
		if(nw != len tmsg){
			fprint(stderr, "ofs: recover: failed: %s\n", m.req.text());
			m.repc <-= ref Rmsg.Error(m.req.tag, "i/o error");
		} else
			l = m :: l;
	}
	stats.nrecover++;
	return l;
}

Stats.dump(s: self ref Stats)
{
	tot := s.nput + s.nget + s.nremove;
	fprint(stderr,"op:\n");
	fprint(stderr,"\t%s\t%d\n", "put", s.nput);
	fprint(stderr,"\t%s\t%d\n", "get", s.nget);
	fprint(stderr,"\t%s\t%d\n", "remove", s.nremove);
	fprint(stderr, "\t%s\t%d\n", "flush", s.nflush);
	fprint(stderr, "\t%s\t%d\n", "recover", s.nrecover);
	fprint(stderr, "\tconc.\t%d\n", s.nconc);
	fprint(stderr,"\ttotal\t%d\n", tot);
}

oprdproc(ofd: ref FD, oprc: chan of ref Rmsg)
{
	oprdprocpid = pctl(0, nil);
	oprc <-= nil;

	if(debug)
		fprint(stderr, "opmuxproc\n");
	for(;;){
		m := op->Rmsg.read(ofd, 0);
		if(debug){
			if(m == nil)
				fprint(stderr, "oprdproc: eof\n");
		}
		oprc <-= m;
		if(m == nil || tagof(m) == tagof(Rmsg.Readerror))
			break;
	}
	if(debug)
		fprint(stderr, "oprdproc: exit\n");
}

opmuxproc(ofd: ref FD, opcc: chan of ref Opcall, oprc: chan of ref Rmsg, endc: chan of string)
{
	reqs: list of ref Opcall;	# outstanding ones.

	broken := 0;
	for(;;){
		alt {
		m := <- opcc =>
			now := millisec();
			if(debug && reqs != nil)
				rdump(reqs);
			if(m == nil){
				if(debug) fprint(stderr, "opmux: hangup: eof\n");
				abortall(reqs);
				kill(oprdprocpid, "kill");
				endc <-= "hangup: eof";
				exit;
			}
			if(debug)
				fprint(stderr, "\n%d\t<-op- %s\n", now, m.req.text());
			if(broken){
				r := ref Rmsg.Error(m.req.tag, "i/o error");
				if(debug)
					fprint(stderr, "\n%d\t-op-> %s\n", now, r.text());
				m.repc <-= r;
				continue;
			}
			pick x := m.req {
			Put => stats.nput++;
			Get => stats.nget++;
			Remove => stats.nremove++;
			Flush => stats.nflush++;
			}
			tmsg := m.req.pack();
			nw := write(ofd, tmsg, len tmsg);
			reqs = m :: reqs;
			if(len reqs > stats.nconc)
				stats.nconc = len reqs;
			if(nw != len tmsg){
				fprint(stderr, "opmux: hangup: write: %r\n");
				if(recoverfn != nil && (ofd = recoverfn()) != nil){
					reqs = recover(ofd, oprc, reqs);
					continue;
				}
				m.repc <-= ref Rmsg.Error(m.req.tag, "i/o error");
				abortall(reqs);
				kill(oprdprocpid, "kill");
				endc <-= "hangup: write";
				exit;
			}
		rmsg := <- oprc =>
			m: ref Opcall;
			last: int;
			if(rmsg == nil || tagof(rmsg) == tagof(Rmsg.Readerror)){
				fprint(stderr, "opmux: hangup: read\n");
				if(tagof(rmsg) == tagof(Rmsg.Readerror) && debug)
					fprint(stderr, "%s\n", rmsg.text());
				if(recoverfn != nil && (ofd = recoverfn()) != nil){
					reqs = recover(ofd, oprc, reqs);
					continue;
				}
				abortall(reqs);
				kill(oprdprocpid, "kill");
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
				fprint(stderr, "%d\t-op-> %s\n\n", millisec(), rmsg.text());
			m.repc <-= rmsg;
		}
	}
	kill(oprdprocpid, "kill");
}

dump()
{
	stats.dump();
}

rdump(reqs: list of ref Opcall)
{
	stats.dump();
	while(reqs != nil){
		fprint(stderr, "\t- %s\n", (hd reqs).req.text());
		reqs = tl reqs;
	}
}

muxreply(reqs: list of ref Opcall, rmsg: ref Rmsg): (ref Opcall, list of ref Opcall, int)
{
	nreqs : list of ref Opcall;
	call: ref Opcall;
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
				if(req.nmsgs == 0 || --req.nmsgs > 0){
					pick rm := rmsg {
					Get =>
						if((rm.mode&OSTAT) && (rm.stat.qid.qtype&QTDIR) && (req.mode&ODATA))
							req.nmsgs = 0; # dirs accept any number of Rget.
						if(rm.mode&OMORE)
							done = 0;
					}
				}
			}
			if(!done)
				nreqs = m :: nreqs;
		}
	}
	if(call == nil)
		fprint(stderr, "opmux: no request for %s\n", rmsg.text());
	else if(tagof(rmsg) != tagof(Rmsg.Error) && rmsg.mtype() != call.req.mtype()+1){
		fprint(stderr, "opmux: type mismatch:\n");
		fprint(stderr, "\tcall: %s\n\treply:%s\n", rmsg.text(), call.req.text());
	}
	return (call, nreqs, done);
}

abortall(reqs: list of ref Opcall)
{
	if(debug)
		fprint(stderr, "opmux: aborting\n");
	while(reqs != nil){
		m := hd reqs;
		m.repc <-= ref Rmsg.Error(m.req.tag, "i/o error");
		reqs = tl reqs;
	}
}

rpc(t: ref Op->Tmsg) : chan of ref Op->Rmsg
{
	rc := chan[1] of ref Op->Rmsg;
	if(opc == nil)
		fprint(stderr, "opmux: nil opc");
	opc <-= ref Opcall(t, rc);
	return rc;
}

