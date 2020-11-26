implement CopyLib;

include "sys.m";
include "string.m";
include "workdir.m";
include "registries.m";
include "copylib.m";

sys: Sys;
str: String;
wdir: Workdir;
regs: Registries;

Registry, Attributes: import regs;

r: ref Registry;
trace := int 0;

SHELLMETA: con "' \t\\$#";

loadSys()
{
	if (sys == nil)
		sys = load Sys Sys->PATH;
}

loadString()
{
	if (str == nil)
		str = load String String->PATH;
}

loadWorkdir()
{
	if (wdir == nil)
		wdir = load Workdir Workdir->PATH;
}

loadRegistries()
{
	if (regs == nil) {
		regs = load Registries Registries->PATH;
		regs->init();
	}
}

dprint(msg: string)
{
	if (trace)
		sys->fprint(sys->fildes(2), "%s\n", msg);
}

#++++++++++++++++++++++ registry stuff ++++++++++++++++++++++++++

regp2paddr(termname: string): (string, string)
{
	loadRegistries();
	if (r == nil) {
		r = Registry.new("/mnt/registry");  ### SL: fixed this for now
		if (r == nil)
			return ((sys->sprint("could not open registry: %r"), nil));
	}

	(svclst, err) := r.find(list of {("oterm", termname)}); ### SL: convention!

	if (err != nil)
		return ((sys->sprint("error searching registry: %s", err), nil));

	if (svclst == nil)
		return (("terminal not found in registry", nil));
	
	p2paddr := (hd svclst).attrs.get("p2paddr"); ### SL: convention!
	if (p2paddr == nil)
		return (("terminal entry does not have a p2paddr attribute", nil));

	return ((nil, p2paddr));
}

#+++++++++++++++++++++++ path resolution +++++++++++++++++++++++++++

### copied from ns.b
any(c: int, t: string): int
{
	for(j := 0; j < len t; j++)
		if(c == t[j])
			return 1;
	return 0;
}

### copied from ns.b
contains(s: string, t: string): int
{
	for(i := 0; i<len s; i++)
		if(any(s[i], t))
			return 1;
	return 0;
}

### copied from ns.b
quoted(s: string): string
{
	if(!contains(s, SHELLMETA))
		return s;
	r := "'";
	for(i := 0; i < len s; i++){
		if(s[i] == '\'')
			r[len r] = '\'';
		r[len r] = s[i];
	}
	r[len r] = '\'';
	return r;
}

### copied from ns.b
netaddr(f: string): string
{
	if(len f < 1 || f[0] != '/')
		return f;
	(nf, flds) := sys->tokenize(f, "/");	# expect /net[.alt]/proto/2/data
	if(nf < 4)
		return f;
	netdir := hd flds;
	if(netdir != "net" && netdir != "net.alt")
		return f;
	proto := hd tl flds;
	d := hd tl tl flds;
	if(hd tl tl tl flds != "data")
		return f;
	fd := sys->open(sys->sprint("/%s/%s/%s/remote", hd flds, proto, d), Sys->OREAD);
	if(fd == nil)
		return f;
	buf := array[256] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return f;
	if(buf[n-1] == byte '\n')
		n--;
	if(netdir != "net")
		proto = "/"+netdir+"/"+proto;
	return sys->sprint("%s!%s", proto, string buf[0:n]);
}

### code body copied from ns.b
getcmdtarget(nsname: string, target: string): (string, string, string, string)
{
	nsfd := sys->open(nsname, Sys->OREAD);
	if (nsfd == nil) {
		sys->fprint(sys->fildes(2), "can't open ns file: %r\n");
		raise "fail:open";
	}
	buf := array[2048] of byte;
	while ((l := sys->read(nsfd, buf, len buf)) > 0) {
		(nstr, lstr) := sys->tokenize(string buf[0:l], " \n");
		if (nstr < 2)
			continue;
		cmd := hd lstr;
		lstr = tl lstr;
		if (cmd == "cd" && lstr != nil) {
			# ns: sys->print("%s %s\n", cmd, quoted(hd lstr));
			continue;
		}

		sflag := "";
		if ((hd lstr)[0] == '-') {
			sflag = hd lstr + " ";
			lstr = tl lstr;
		}
		if (len lstr < 2)
			continue;

		src := hd lstr;
		lstr = tl lstr;
		if(len src >= 3 && (src[0:2] == "#/" || src[0:2] == "#U")) # remove unnecesary #/'s and #U's
			src = src[2:];

		# remove "#." from beginning of destination path
		dest := hd lstr;
		if (dest == "#M") {
			dest = dest[2:];
			if(dest == "")
				dest = "/";
		}

		if (cmd == "mount")
			src = netaddr(src);	# rewrite network files to network address

		# quote arguments if "#" found
		# ns: sys->print("%s %s%s %s\n", cmd, sflag, quoted(src), quoted(dest));
		if (dest == target) 
			return ((cmd, sflag, src, dest)); 
	} 
	if(l < 0) {
		sys->fprint(sys->fildes(2), "error reading ns file: %r\n");
		raise "fail:read";
	}
	return ((nil, nil, nil, nil));
}

getcmd4maxprefix(nsname: string, target: string): (string, string, string, string, string)
{
	path1 := target;
	path2 := "";
	path3 := "";
	while (1) {
		dprint("resolving: " + path1);
		(cmd, opts, src, dst) := getcmdtarget(nsname, path1);
		if (cmd != nil)
			return ((cmd, opts, src, dst, path3));
		(path1, path2) = str->splitr(path1, "/");
		path3 = "/" + path2 + path3;
		if ((path1 == "/") || (path1 == "") || (path1 == nil))
			return ((nil, nil, nil, nil, path3));
		path1 = path1[:len path1 - 1];
	}
}

getmount(path: string): (string, string, string)
{
	pid := sys->pctl(0, nil);
	nsname := sys->sprint("/prog/%d/ns", pid);
	target := path;
	lpath := "";
	while (1) {
		(cmd, opts, src, dst, lpath1) := getcmd4maxprefix(nsname, target);
		lpath = lpath1 + lpath;
		if (cmd == nil)
			return ((nil, nil, lpath));
		else if (cmd == "mount")
			return((src, dst, lpath));
		else if (cmd =="bind")
			target = src;
		else {
			sys->fprint(sys->fildes(2), "unknown command in ns file: %s\n", cmd);
			raise "fail:nscmd";
		}
	}
}

resolve(fname: string): (string, string, string)
{
	path := fname;
	if (fname[0] != '/') {
		loadWorkdir();
		wd := wdir->init();
		if (wd == nil) { 
			sys->fprint(sys->fildes(2), "could not get work dir: %r\n");
			raise "fail:pwd";
		}
		path = wd + "/" + fname;
	} 
		
	(mntaddr, mntpnt, lpath) := getmount(path);

	if (mntaddr == nil)
		return ( (nil, nil, path) );
	else
		return ( (mntaddr, mntpnt, lpath) );
}

#++++++++++++++++++++++ copy device stuff ++++++++++++++++++++++++++

copy_local(src, dst: string, srcoff, dstoff, nofbytes: big): (string, big)
{
	srcfd := sys->open(src, sys->OREAD);
	if (srcfd == nil) 
		return ((sys->sprint("could not open %s: %r", src), big 0));
	
	dstfd := sys->create(dst, sys->OWRITE, 8r777);
	if (dstfd == nil) 
		return ((sys->sprint("could not open %s: %r", dst), big 0));
	
	cnt := big 0; 
	data := array [8192] of byte;
	
	while (1) {
		rcnt := len data;
		if ((nofbytes > big 0) && (big rcnt > nofbytes - cnt)) 
				rcnt = int (nofbytes - cnt); 
		
		n1 := sys->read(srcfd, data, rcnt);
		if (n1 < 0)
			return ((sys->sprint("read error: %r"), cnt));
		
		if (n1 == 0) 
			return ((nil, cnt));
		
		n2 := sys->write(dstfd, data, n1);
		if (n2 != n1)
			return ((sys->sprint("write error: %r"), cnt)); 
		
		cnt = cnt + big n1;
		
		if (cnt == nofbytes)
			return ((nil, cnt));
	}
}

openctl(cpd: string): (string, ref Sys->FD)
{
	ctlfd := sys->open(cpd + "/new", Sys->ORDWR);

	if (ctlfd == nil)
		return ((sys->sprint("error opening control file: %r"), nil));
	
	return ((nil, ctlfd));
}

getcnt(ctlfd: ref Sys->FD): (string, big)
{
	cnt, n: int;
	buf := array [256] of byte; # enough to hold big values as strings
	sys->seek(ctlfd, big 0, Sys->SEEKSTART);

	for (cnt = 0; (n = sys->read(ctlfd, buf[cnt:], len buf - cnt)) > 0; cnt = cnt + n);
	if (n < 0)
		return ((sys->sprint("error reading control file: %r"), big 0));
	
	if (cnt == len buf)
		return ((sys->sprint("buffer length reached: %d", len buf), big 0));
	
	retstr := string buf[0:cnt];
	(bytecnt, rest) := str->tobig(retstr, 10);
	if (rest != nil)
		return ((sys->sprint("invalid value read from control file: %s", retstr), big 0));
	
	return ((nil, bytecnt));
}

getdialaddr(mntaddr, mntpnt: string): (string, string)
{
	(prefix, termname) := str->splitstrr(mntpnt, "/terms/"); ### SL: convention!
	if ((prefix != "/terms/") || (termname == nil) || (str->in('/', termname)))
		return (("not a valid terminal path", nil));

	(err, p2paddr) := regp2paddr(termname);
	if (err == nil) 
		return ((nil, p2paddr));

	return ((sys->sprint("error looking for %s: %s\n", termname, err), nil));
}

copy_p2p(src, dst: string, srcoff, dstoff, nofbytes: big): (string, big)
{
	loadSys();
	loadString();
	loadWorkdir();

	(srcmntaddr, srcmntpnt, srcpath) := resolve(src);
	dprint(sys->sprint("srcmntaddr: %s, srcmntpnt: %s, srcpath: %s", srcmntaddr, srcmntpnt, srcpath));
	if (srcmntpnt == nil) return (("source is local", big 0));
		
	(dstmntaddr, dstmntpnt, dstpath) := resolve(dst);
	dprint(sys->sprint("dstmntaddr: %s, dstmntpnt: %s, dstpath: %s", dstmntaddr, dstmntpnt, dstpath));
	if (dstmntpnt == nil) return (("destination is local", big 0)); 

	(err1, srcdialaddr) := getdialaddr(srcmntaddr, srcmntpnt);
	if (err1 != nil) return (("source dial address not found: " + err1, big 0));
	dprint(sys->sprint("source dial address is: %s", srcdialaddr));

	(err2, ctlfd) := openctl(dstmntpnt + "/cpd");
	if (err2 != nil) return ((err2, big 0));

	cmd := sys->sprint("%s %s %s %s %bd %bd %bd",
	                   srcdialaddr, srcpath, "localhost", dstpath,
                           srcoff, dstoff, nofbytes); 
	buf := array of byte cmd;
	n := sys->write(ctlfd, buf, len buf);
	
	err3 := string nil;
	if (n != len buf) err3 = sys->sprint("%r");

	(err4, cnt) := getcnt(ctlfd); # even if copy failed

	if (err4 == nil) return ((err3, cnt));

	return ((err4, big 0));
}

trace_p2p(on: int) 
{
	trace = on;
}
