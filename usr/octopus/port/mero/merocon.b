# Connections to o/live
# event handling

implement Merocon;
include "sys.m";
	sys: Sys;
	sprint, open, FD, OWRITE, write, OREAD, fprint: import sys;
include "daytime.m";
	daytime: Daytime;
	now: import daytime;
include "styx.m";
	Tmsg, Rmsg: import Styx;
include "styxservers.m";
	styxs: Styxservers;
	Styxserver: import styxs;
include "dat.m";
	dat: Dat;
	vgen, srv, mnt, debug, appl, slash: import dat;
include "string.m";
	str: String;
	splitl, take, drop: import str;
include "names.m";
	names: Names;
	dirname: import names;
include "error.m";
	err: Error;
	kill, checkload, error, panic, stderr: import err;
include "mpanel.m";
	Panel, Repl, Qdir, Trepl: import Panels;
include "merotree.m";
	merotree: Merotree;
	pheldupd, pwalk, pchanges: import merotree;
include "tbl.m";
include "lists.m";
	lists: Lists;
	append, reverse, concat: import lists;
include "blks.m";
	blks: Blks;
	Blk: import blks;
include "merop.m";
	merop: Merop;
	Msg: import merop;
include "merocon.m";

# To hold events, we send the event process the pid of the ones to hold/release.
# Events matching the held pid are kept until the pid is released or the hold is
# timed out. That process finally posts the events either to the o/ports service
# for the application or to the olive file we serve.
# Internally, we use Msg adts to keep the event data, most of them are Msg.Ctl
# events. 
# When we have to reply to o/live Tread requests for events we build the particular
# event to be sent to o/live. 

# It would be better not to post the held events in the first place, but that's quite
# difficult to get right. This is more inefficient but also a lot easier.

Held: adt {
	p:	ref Panel;		# p.pid is held
	cnt:	int;		# nb. of nested hold reqs.
	evs:	list of ref Event;
	time:	int;		# to rlse held for too long
	vers:	int;		# vgen as of hold.
};

# The interface to the event process, keeping events on hold.
evc:	chan of ref Event;	# events to be posted
holdc:	chan of ref Panel;	# pids/panels on hold
rlsec:	chan of ref Panel;	# pids/panels no longer on hold

# The interface to the o/live connection process.

newc:	chan of (int, chan of ref Con);		# create a con. for a fid
closec:	chan of ref Con;			# destroy a connection
lookupc:	chan of (int, chan of ref Con);		# lookup by fid 
readc:	chan of (ref Con, ref Tmsg.Read, chan of int);
oliveevc:	chan of (list of ref Event, chan of int);	# events read by user
writec:	chan of (ref Con, ref Tmsg.Write);	# ctls written by user
ctlc:	chan of (ref Con, chan of (ref Panel, ref Repl, string, array of byte));

flushc:	chan of (int, chan of int);
dumpc:	chan of int;

# To block the caller while an event is being processed
# so that only one request at a time is being handled by the fs
# and we do not require locking.
syncc:	chan of int;

init(d: Dat)
{
	dat = d;
	sys = dat->sys;
	err = dat->err;
	str = dat->str;
	merop = dat->merop;
	blks = dat->blks;
	styxs = dat->styxs;
	daytime = dat->daytime;
	names = dat->names;
	lists = dat->lists;
	merotree = dat->merotree;
	evc = chan[10] of ref Event;
	holdc = chan of ref Panel;
	rlsec = chan of ref Panel;
	newc = chan of (int, chan of ref Con);
	closec = chan[5] of ref Con;
	lookupc =  chan of (int, chan of ref Con);
	readc = chan of (ref Con, ref Tmsg.Read, chan of int);
	oliveevc = chan[10] of (list of ref Event, chan of int);
	writec = chan of (ref Con, ref Tmsg.Write);
	ctlc = chan of (ref Con, chan of (ref Panel, ref Repl, string, array of byte));
	flushc = chan of (int, chan of int);
	dumpc = chan of int;

	syncc = chan of int;
}

start(): int
{
	efd := open("/mnt/ports/post", OWRITE);
	if(efd == nil){
		fprint(stderr, "o/mero: fatal: ports/post: %r\n");
		return -1;
	}
	spawn conproc();
	spawn eventproc(efd);
	return 0;
}

post(pid: int, p: ref Panels->Panel, r: ref Panels->Repl, ev: string)
{
	m := ref Msg.Ctl(r.path, ev);
	evc <-= ref Event(pid, p, r, m);
	<-syncc;
}

hold(p: ref Panels->Panel)
{
	holdc <-= p;
	<-syncc;
}

rlse(p: ref Panels->Panel)
{
	rlsec <-= p;
	<-syncc;
}

deliver(fd: ref FD, evs: list of ref Event)
{
	revs, aevs: list of ref Event;
	for(; evs != nil; evs = tl evs){
		e := hd evs;
		if(debug)
			fprint(stderr, "o/mero: event pid %d tree %d %s\n",
				e.pid, e.r.tree, e.m.text());
		if(e.r.tree == Trepl)
			revs = e::revs;
		else
			aevs = e::aevs;
	}
	if(revs != nil){
		rc := chan of int;
		oliveevc <-= (reverse(revs), rc);
		<-rc;
	}
	if(aevs != nil)
		for(evs = reverse(aevs); evs != nil; evs = tl evs){
			e := hd evs;
			s := sprint("o/mero: %s %d", e.m.path, e.p.aid);
			pick m := e.m {
			Update =>
				error("o/mero: updates to appl");
			Ctl =>
				s += " " + m.ctl + "\n";
			}
			data := array of byte s;
			if(write(fd, data, len data) != len data)
				error("o/mero: post: short write");
		}
}

dumpel(s: string, l: list of ref Event)
{
	fprint(stderr, "%s:\n", s);
	if(l == nil)
		fprint(stderr, "\tnil\n");
	for(; l != nil; l = tl l){
		e := hd l;
		fprint(stderr, "\tpid=%d %s\n", e.pid, e.m.text());
	}
}

pack(l: list of ref Event): list of ref Event
{
	# for each element in l, remove events that refer to suffixes if
	# both events are the same. This coallesces multiple update
	# and close events.
	if(debug>2) dumpel("pack", l);
	evs := array[len l] of ref Event;
	for(i := 0; l != nil; l = tl l)
		evs[i++] = hd l;
	for(i = 0; i < len evs; i++)
		if(evs[i].m != nil)
		for(j := 0; j < len evs; j++)
			if(i != j && evs[j].m != nil)
			if(names->isprefix(evs[i].m.path, evs[j].m.path))
			pick mi := evs[i].m {
			Ctl =>
				pick mj := evs[j].m {
				Ctl =>
					if(mi.ctl == mj.ctl)
						evs[j].m = nil;
				}
			}
	nl: list of ref Event;
	for(i = 0; i < len evs; i++)
		if(evs[i].m != nil)
			nl = evs[i]::nl;
	if(debug>2) dumpel("packed", nl);
	return nl;
}

# BUG(?): if we declare held as a local of
# event proc, it seems to become nil after going back to the alt.
held: list of ref Held;

# Processes events, hold, and release requests
# and calls deliver() to post them.
eventproc(fd: ref FD)
{
	for(;;) alt {
	p := <-holdc =>
		pid := p.pid;
		if(debug)
			fprint(stderr, "o/mero: pid %d held\n", pid);
		for(l := held; l != nil; l = tl l){
			h := hd l;
			if(h.p.pid == pid){
				h.cnt++;
				break;
			}
		}
		if(l == nil)
			held = ref Held(p, 1, nil, now(), vgen)::held;
		syncc <-= 0;
	p := <-rlsec =>
		# When a pid is released we must see which panels
		# have changed in the subtree for the event's panel
		# since the pid was held, and update their overs
		# to force updates for them. Otherwise, if an ancestor
		# with a newer overs has been updated due to changes
		# in an unrelated panel, the updates will be ignored
		# as their overs is less than that of the connection.
		pid := p.pid;
		if(debug)
			fprint(stderr, "o/mero: pid %d rlse\n", pid);
		nl: list of ref Held;
		t := now();
		evs: list of ref Event;
		for(; held != nil; held = tl held){
			h := hd held;
			if((h.p.pid == pid && --h.cnt <=0) || t - h.time > 10){
				h.cnt = 0;
				h.evs = pack(h.evs);
				if(h.evs != nil){
					evs = concat(evs, h.evs);
					h.evs = nil;
				}
				if(p != nil){
					pheldupd(p, h.vers);
					p = nil;
				}
			} else
				nl = h::nl;
		}
		held = nl;
		if(evs != nil)
			deliver(fd, evs);
		syncc <-= 0;
	e := <- evc =>
		for(l := held; l != nil; l = tl l){
			h := hd l;
			if(h.p.pid == e.pid){
				h.evs = e::h.evs;
				break;
			}
		}
		if(l == nil)
			deliver(fd, list of {e});
		syncc <-= 0;
	}
}

dump()
{
	dumpc <-= 0;
}

Con.new(fid: int): ref Con
{
	rc := chan of ref Con;
	newc <-= (fid, rc);
	return <-rc;
}

Con.lookup(fid: int): ref Con
{
	rc := chan of ref Con;
	lookupc <-= (fid, rc);
	return <-rc;
}

Con.close(c: self ref Con)
{
	closec <-= c;
}

Con.read(c: self ref Con, m: ref Tmsg.Read)
{
	rc := chan of int;
	readc <-= (c, m, rc);
	<-rc;
}

Con.flush(tag: int)
{
	rc := chan of int;
	flushc <-= (tag, rc);
	<-rc;
}

Con.write(c: self ref Con, m: ref Tmsg.Write)
{
	writec <-= (c, m);
}

Con.ctl(c: self ref Con): (ref Panels->Panel, ref Panels->Repl, string, array of byte)
{
	rc := chan of (ref Panel, ref Repl, string, array of byte);
	ctlc <-= (c, rc);
	return <-rc;
}

Con.text(c: self ref Con): string
{
	if(c == nil)
		return "null con";
	s := sprint("con fid %d ver %d %s", c.fid, c.vers, c.top);
	s += sprint(" evs %d blen %d", len c.evs, c.rblk.blen());
	if(c.req != nil)
		s += sprint(" rtag %d", c.req.tag);
	return s;
}

# While executing this the main file system proc
# is waiting for conproc to reply; we may use the
# panel tree as we want without locks
fillrblk(c: ref Con)
{
	nvers := c.vers;
	for(; c.evs != nil; c.evs = tl c.evs){
		e := hd c.evs;
		ctl: string;
		pick m := e.m {
		Update =>
			panic("update event in fillrblk");
		Ctl =>
			ctl = m.ctl;
		}
		case ctl {
		"update" =>
			(l, nv) := pchanges(e.p, e.r, c.vers);
			for(; l != nil; l = tl l){
				x := hd l;
				c.rblk.put(x.pack());
			}
			if(nv > nvers && c.top != "/")
				nvers = nv;
		* =>
			c.rblk.put(e.m.pack());
		}			
	}
	c.vers = nvers;
}

fsread(c: ref Con)
{
	cnt := c.req.count;
	fillrblk(c);
	if(cnt > c.rblk.blen())
		cnt = c.rblk.blen();
	if(cnt > 0){
		data := c.rblk.get(cnt);
		srv.reply(ref Rmsg.Read(c.req.tag, data));
		c.req = nil;
	}
}

# processes o/live connection requests and
# o/live events
cons: list of ref Con;
conproc()
{

	for(;;) alt {
	<-dumpc =>
		fprint(stderr, "o/mero cons:\n");
		for(cl := cons; cl != nil; cl = tl cl)
			fprint(stderr, "%s\n", (hd cl).text());

	(fid, rc) := <-newc =>
		c := ref Con(fid, -1, "/", nil, nil, ref Blk(nil, 0, 0), ref Blk(nil, 0, 0));
		for(cl := cons; cl != nil; cl = tl cl)
			if((hd cl).fid == fid)
				panic("dup con fid");
		cons = c::cons;
		if(debug)
			fprint(stderr, "o/mero: new con fid %d\n", fid);
		rc <-= c;

	(fid, rc) := <-lookupc =>
		for(cl := cons; cl != nil; cl = tl cl)
			if((hd cl).fid == fid)
				break;
		if(cl != nil)
			rc <-= hd cl;
		else
			rc <-= nil;

	c := <-closec =>
		if(c == nil)
			return;
		if(debug)
			fprint(stderr, "o/mero: close con fid %d\n", c.fid);
		if(c.req != nil){
			srv.reply(ref Rmsg.Error(c.req.tag, "hangup"));
			c.req = nil;
		}
		nl: list of ref Con;
		for(; cons != nil; cons = tl cons)
			if((hd cons).fid != c.fid)
				nl = (hd cons)::nl;
		cons = nl;
		c.fid = -1;
		c.evs = nil;
		c.rblk = nil;

	(tag, rc) := <-flushc =>
		# Flush an outstanding Tread from o/live
		for(cl := cons; cl != nil; cl = tl cl){
			c := hd cl;
			if(c.req != nil && c.req.tag == tag){
				srv.reply(ref Rmsg.Error(c.req.tag, "flushed"));
				c.req = nil;
				break;
			}
		}
		rc <-= 0;

	(c, m, rc) := <-readc =>
		# Serve a user Tread with events posted here.
		if(c.req != nil){
			fprint(stderr, "o/mero: Con.read: fix o/live\n");
			srv.reply(ref Rmsg.Error(m.tag, "only a con read at a time"));
			srv.reply(ref Rmsg.Error(c.req.tag, "hangup"));
			c.req = nil;
		} else {
			c.req = m;
			fsread(c);
		}
		rc <-= 0;

	(evs, rc) := <-oliveevc =>
		# Post events for user Tread requests
		for(; evs != nil; evs = tl evs){
			e := hd evs;
			for(cl := cons; cl != nil; cl = tl cl){
				c := hd cl;
				mine:= names->isprefix(e.m.path, c.top);
				mine |= names->isprefix(c.top, e.m.path);
				if(!mine)
					pick cm := e.m {
					Ctl => if(cm.ctl == "focus")
						mine = 1;
					}
				if(mine && c.top != "/")
					c.evs = append(c.evs, e);
			}
		}
		for(cl := cons; cl != nil; cl = tl cl){
			c := hd cl;
			if(c.req != nil && c.top != "/")
				fsread(c);
		}
		rc <-= 0;

	(c, m) := <- writec =>
		# keep user writes for ctls done from o/live
		# they are procesed by asking ctlc for a new ctl request.
		c.wblk.put(m.data);
	(c, rc) := <- ctlc =>
		# return next ctl made by o/live or nil
		# the fs request is awaiting our reply, we can use the tree.
		m := Msg.bread(c.wblk);
		if(debug)
			fprint(stderr, "con ctl: %s\n", m.text());
		if(m == nil)
			rc <-= (nil, nil, nil, nil);
		else {
			(p, r) := pwalk(m.path);
			if(p == nil || r == nil)
				rc <-= (nil, nil, "fail", nil);
			else
			pick mm := m {
			Ctl =>
				rc <-= (p, r, mm.ctl, nil);
			Update =>
				rc <-= (p, r, nil, mm.data);
			}
		}
	}
}

