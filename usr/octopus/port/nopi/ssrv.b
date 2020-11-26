implement Ssrv;

# most of the styx code comes from Inferno's styxservers.b
# that module is not used to exploit what we now when we
# receive styx requests.

include "sys.m";
	sys: Sys;

include "styx.m";
	styx: Styx;
	Tmsg, Rmsg: import styx;

include "ofsstyx.m";

CHANHASHSIZE: con 32;

init(s: Styx, c: Cache)
{
	sys = load Sys Sys->PATH;
	styx = styxmod;
	cache = c;
}

Srv.new(rq: big): ref Srv
{
	tchan := chan of ref Tmsg;
	rchan := chan[5] of ref Rmsg;
	fids := array[CHANHASHSIZE] of list of ref Fid;
	return ref Srv(fids, chan[1] of int, rq, 0, tchan, rchan);
}

Fid.clone(oc: self ref Fid, c: ref Fid): ref Fid
{
	# c.fid not touched, other values copied from c
	c.path = oc.path;
	c.qtype = oc.qtype;
	c.isopen = oc.isopen;
	c.mode = oc.mode;
	c.doffset = oc.doffset;
	c.uname  = oc.uname;
	c.param = oc.param;
	c.ofd = oc.ofd;
	c.cfd = oc.cfd;
	return c;
}

Fid.walk(c: self ref Fid, qid: Sys->Qid)
{
	c.path = qid.path;
	c.qtype = qid.qtype;
	c.ofd = Nop->NOFD;	# safety
	c.cfd = nil;		# safety
}

Fid.open(c: self ref Fid, mode: int, qid: Sys->Qid)
{
	c.isopen = 1;
	c.mode = mode;
	c.doffset = (0, 0);
	c.path = qid.path;
	c.qtype = qid.qtype;
	c.ofd = Nop->NOFD;	# safety
	c.cfd = nil;		# safety
}

Srv.version(srv: self ref Srv, m: ref Tmsg.Attach): ref Rmsg
{
	if(srv.msize <= 0)
		srv.msize = Styx->MAXRPC;
	(msize, version) := compatible(m, srv.msize, Styx->VERSION);
	if(msize < 256)
		return ref Rmsg.Error(m.tag, "message size too small");
	srv.msize = msize;
	return ref Rmsg.Version(m.tag, msize, version);
}

Srv.auth(srv: self ref Srv, m: ref Tmsg.Attach): ref Rmsg
{
	return ref Rmsg.Error(m.tag, "authentication not required");
}

Srv.attach(srv: self ref Srv, m: ref Tmsg.Attach): ref Rmsg
{
	(d, err) := cache->stat(srv.rootpath);
	if(d == nil)
		return ref Rmsg.Error(m.tag, err);
	if((d.qid.qtype & Sys->QTDIR) == 0)
		return ref Rmsg.Error(m.tag, Enotdir);
	c := srv.newfid(m.fid);
	if(c == nil)
		return ref Rmsg.Error(m.tag, Einuse);
	c.uname = m.uname;
	c.param = m.aname;
	c.path = d.qid.path;
	c.qtype = d.qid.qtype;
	return ref Rmsg.Attach(m.tag, d.qid);
}

Srv.stat(srv: self ref Srv, m: ref Tmsg.Stat): ref Rmsg
{
	c := srv.getfid(m.fid);
	if(c == nil)
		return ref Rmsg.Error(m.tag, Ebadfid);
	(d, err) := cache->stat(c.path);
	if(d == nil)
		return ref Rmsg.Error(m.tag, err);
	return ref Rmsg.Stat(m.tag, *d);
}

Srv.walk(srv: self ref Srv, m: ref Tmsg.Walk): ref Rmsg
{
	c := srv.getfid(m.fid);
	if(c == nil)
		return ref Rmsg.Error(m.tag, Ebadfid);
	if(c.isopen)
		return ref Rmsg.Error(m.tag, Eopen);
	if(m.newfid != m.fid){
		nc := srv.newfid(m.newfid);
		if(nc == nil){
			return ref Rmsg.Error(m.tag, Einuse);
		c = c.clone(nc);
	}
	qids := array[len m.names] of Sys->Qid;
	oldpath := c.path;
	oldqtype := c.qtype;

	# we ask the entire path to the cache. If it's there,
	# the walked dirs are cached and later we'll use cached entries.
	# if it's not there, the walks done later would be able to retrieve
	# just the existing prefix (that must be there if something was mounted
	# on it before)
	(nil, err) := cache->walk(c.path, m.names, 1);
	d : ref Sys->Dir;
	for(i := 0; i < len m.names; i++){
		if(err == nil)			
			(d, err) = cache->walk(c.path, m.names[i:i+1], 0);
		if(err == nil){
			if((d.qid.qtype & Sys->QTDIR) == 0)
				err = Enotdir;
			else if(!openok(c.uname, Styx->OEXEC, d.mode, d.uid, d.gid))
				err = Eperm;
		}
		if(err != nil){
			c.path = oldpath;	# restore c
			c.qtype = oldqtype;
			if(m.newfid != m.fid)
				srv.delfid(c);
			if(i == 0)
				return ref Rmsg.Error(m.tag, err);
			else
				return ref Rmsg.Walk(m.tag, qids[0:i]);
		}
		c.walk(d.qid);
		qids[i] = d.qid;
	}
	return ref Rmsg.Walk(m.tag, qids);
}

Srv.open(srv: self ref Srv, m: ref Tmsg.Open): ref Rmsg
{
	c := srv.getfid(m.fid);
	if(c == nil)
		return ref Rmsg.Error(m.tag, Ebadfid);
	if(c.isopen)
		return ref Rmsg.Error(m.tag, Eopen);
	mode := openmode(m.mode);
	if(mode == -1)
		return ref Rmsg.Error(m.tag, Ebadarg);
	(d, err) := cache->open(c.path, c, m.mode);
	if(err != nil)
		return ref Rmsg.Error(m.tag, err);
	mode |= m.mode&ORCLOSE;
	c.open(mode, d.qid);
	return ref Rmsg.Open(m.tag, d.qid, srv.iounit());
}

Srv.create(srv: self ref Srv, m: ref Tmsg.Create): ref Rmsg
{
	c := srv.getfid(m.fid);
	if(c == nil)
		return ref Rmsg.Error(m.tag, Ebadfid);
	if(c.isopen)
		return ref Rmsg.Error(m.tag, Eopen);
	if(m.name == "")
		return ref Rmsg.Error(m.tag, Ename);
	if(m.name == "." || m.name == "..")
		return ref Rmsg.Error(m.tag, Edot);
	mode := openmode(m.mode);
	if(mode == -1)
		return ref Rmsg.Error(m.tag, Ebadarg);
	nd := ref Sys->zerodir;
	nd.name = m.name;
	nd.mode = m.perm;
	(d, err) := cache->create(c.path, nd, m.fid, m.mode);
	if(err != nil)
		return ref Rmsg.Error(m.tag, err);
	c.open(mode, d.qid);
	return ref Rmsg.Create(m.tag, d.qid, srv.iounit());
}

Srv.read(srv: self ref Srv, m: ref Tmsg.Read): ref Rmsg
{
	c := srv.getfid(m.fid);
	if(c == nil)
		return ref Rmsg.Error(m.tag, Ebadfid);
	if(!c.isopen)
		return ref Rmsg.Error(m.tag, Enotopen);
	mode := c.mode & 3;
	if(mode != Sys->OREAD && mode != Sys->ORDWR)
		return ref Rmsg.Error(m.tag, Eaccess);
	if(m.count < 0 || m.count > srv.msize-Styx->IOHDRSZ)
		return ref Rmsg.Error(m.tag, Ecount);
	if(m.offset < big 0)
		return ref Rmsg.Error(m.tag, Eoffset);
	if(m.count == 0)
		return ref Rmsg.Read(m.tag, nil);
	a: array of byte;
	if((c.qtype & Sys->QTDIR) == 0){
		(a, err) = cache->read(c.path, m.fid, m.count, m.offset);
		if(err != nil)
			return ref Rmsg.Error(m.tag, err);
		else
			return ref Rmsg.Read(m.tag, a);
	}

	dirs := cache->children(c.path);
	(offset, index) := c.doffset;
	if(int m.offset != offset){	# rescan from the beginning
		offset = 0;
		index = 0;
	}
	p := 0;
	for(i := index; i < len dirs; i++){
		size := styx->packdirsize(*d[i]);
		if(m.count - size < 0)
			break;
		offset += size;
		index++;
		if(offset < int m.offset)
			continue;
		m.count -= size;
		de := styx->packdir(*d[i]);
		a[p:] = de;
		p += size;
	}
	c.doffset = (offset, index);
	return ref Rmsg.Read(m.tag, a[0:p]);
}

Srv.write(srv: self ref Srv, m: ref Tmsg.Write): ref Rmsg
{
	c := srv.getfid(m.fid);
	if(c == nil)
		return ref Rmsg.Error(m.tag, Ebadfid);
	if(!c.isopen)
		return ref Rmsg.Error(m.tag, Enotopen);
	if(c.qtype & Sys->QTDIR)
		return ref Rmsg.Error(m.tag, Eperm);
	mode := c.mode & 3;
	if(mode != Sys->OWRITE && mode != Sys->ORDWR)
		return ref Rmsg.Error(m.tag, Eaccess);
	if(m.count < 0 || m.count > srv.msize-Styx->IOHDRSZ)
		return ref Rmsg.Error(m.tag, Ecount);
	if(m.offset < big 0)
		return ref Rmsg.Error(m.tag, Eoffset);
	(nw, err) := cache->write(c.path, m.fid, m.data, m.offset);
	if(err != nil)
		return ref Rmsg.Error(m.tag, err);
	else
		return ref Rmsg.Write(m.tag, nw);
}

Srv.clunk(srv: self ref Srv, m: ref Tmsg.Clunk): ref Rmsg
{
	c := srv.getfid(m.fid);
	if(c == nil)
		return ref Rmsg.Error(m.tag, Ebadfid);
	if(c.isopen)
		cache->clunk(c.path, m.fid);
	srv.delfid(c);
	return ref Rmsg.Clunk(m.tag);
}

Srv.remove(srv: self ref Srv, m: ref Tmsg.Remove): ref Rmsg
{
	c := srv.getfid(m.fid);
	if(c == nil)
		return ref Rmsg.Error(m.tag, Ebadfid);
	err: string;
	if(c.path == cache->root())
		err = Eperm;
	else {
		d := cache->parent(c.path);
		if(!openok(c.uname, OWRITE, d.mode, d.uid, d.gid))
			err = Eperm;
	}
	if(err == nil)
		err = cache->remove(c.path);
	if(c.isopen)
		cache->clunk(c.path, m.fid);
	srv.delfid(c);
	if(err != nil)
		return ref Rmsg.Error(m.tag, err);
	else
		return ref Rmsg.Remove(m.tag);
}

Srv.wstat(srv: self ref Srv, m: ref Tmsg.Wstat): ref Rmsg
{
	c := srv.getfid(m.fid);
	if(c == nil)
		return ref Rmsg.Error(m.tag, Ebadfid);
	err := cache->wstat(c.path, ref m.stat);
	if(err != nil)
		return ref Rmsg.Error(m.tag, err);
	else
		return ref Rmsg.Wstat(m.tag);
}

Srv.iounit(srv: self ref Srv): int
{
	n := srv.msize - Styx->IOHDRSZ;
	if(n <= 0)
		return 0;	# unknown
	return n;
}

Srv.getfid(srv: self ref Srv, fid: int): ref Fid
{
	# the list is safe to use without locking
	for(l := srv.fids[fid & (CHANHASHSIZE-1)]; l != nil; l = tl l)
		if((hd l).fid == fid)
			return hd l;
	return nil;
}

Srv.delfid(srv: self ref Srv, c: ref Fid)
{
	slot := c.fid & (CHANHASHSIZE-1);
	nl: list of ref Fid;
	srv.fidlock <-= 1;
	for(l := srv.fids[slot]; l != nil; l = tl l)
		if((hd l).fid != c.fid)
			nl = (hd l) :: nl;
	srv.fids[slot] = nl;
	<-srv.fidlock;
}

Srv.allfids(srv: self ref Srv): list of ref Fid
{
	cl: list of ref Fid;
	srv.fidlock <-= 1;
	for(i := 0; i < len srv.fids; i++)
		for(l := srv.fids[i]; l != nil; l = tl l)
			cl = hd l :: cl;
	<-srv.fidlock;
	return cl;
}

Srv.newfid(srv: self ref Srv, fid: int): ref Fid
{
	srv.fidlock <-= 1;
	if((c := srv.getfid(fid)) != nil){
		<-srv.fidlock;
		return nil;		# illegal: fid in use
	}
	c = ref Fid;
	c.path = big -1;
	c.qtype = 0;
	c.isopen = 0;
	c.mode = 0;
	c.fid = fid;
	c.doffset = (0, 0);
	slot := fid & (CHANHASHSIZE-1);
	srv.fids[slot] = c :: srv.fids[slot];
	<-srv.fidlock;
	return c;
}

openmode(o: int): int
{
	OTRUNC, ORCLOSE, OREAD, ORDWR: import Sys;
	o &= ~(OTRUNC|ORCLOSE);
	if(o > ORDWR)
		return -1;
	return o;
}

access := array[] of {8r400, 8r200, 8r600, 8r100};
openok(uname: string, omode: int, perm: int, fuid: string, fgid: string): int
{
	t := access[omode & 3];
	if(omode & Sys->OTRUNC){
		if(perm & Sys->DMDIR)
			return 0;
		t |= 8r200;
	}
	if(uname == fuid && (t&perm) == t)
		return 1;
	# we try to match group permissions even if we are
	# not known to be in the group. The server will decide later.
	# otherwise, nop would not be able to really use groups.
	if((t&(perm<<3)) == t)
		return 1;
	return (t&(perm<<6)) == t;
}	
