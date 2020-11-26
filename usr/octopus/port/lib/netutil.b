implement Netutil;

include "sys.m";
	sys: Sys;
	FD: import Sys;
	stat, sprint, werrstr: import sys;
include "security.m";
	auth: Auth;
include "keyring.m";
	kring: Keyring;
include "env.m";
	env: Env;
	getenv: import env;
include "netutil.m";

netmkaddr(addr, net, svc: string): string
{
	if(sys == nil)
		sys = load Sys Sys->PATH;

	if(net == nil)
		net = "net";
	(n, nil) := sys->tokenize(addr, "!");
	if(n <= 1){
		if(svc== nil)
			return sys->sprint("%s!%s", net, addr);
		return sys->sprint("%s!%s!%s", net, addr, svc);
	}
	if(svc == nil || n > 2)
		return addr;
	return sys->sprint("%s!%s", addr, svc);
}

authfd(fd: ref FD, role: int, alg, kfile, addr: string): (ref FD, string)
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
	if(auth == nil){
		auth = load Auth Auth->PATH;
		auth = load Auth Auth->PATH;
		kring = load Keyring Keyring->PATH;
		env = load Env Env->PATH;
		if(auth == nil || kring == nil || env == nil)
			return(nil, nil);
	}
	home := getenv("home");
	if(home == nil)
		return (nil, nil);
	kdir := home + "/keyring";
	if(addr == nil)
		addr = "default";
	if(kfile == nil){
		kfile = kdir + "/" + addr;
		(e, nil) := stat(kfile);
		if(e < 0)
			kfile = kdir + "/" + "default";
	} else if(kfile[0] != '/')
			kfile = kdir + "/" + kfile;
	ai := kring->readauthinfo(kfile);
	if(ai == nil){
		werrstr(sprint("%s: %r", kfile));
		return (nil, nil);
	}
	e := auth->init();
	if(e != nil){
		werrstr(e);
		return (nil, nil);
	}
	if(alg == nil)
		alg = "rc4";
	if(role == Client)
		(fd, e) = auth->client(alg, ai, fd);
	else {
		algs := list of {alg, "rc4_40", "rc4_128", "rc4_256", 
				"des_56_cbc", "des_56_ecb", "ideacbc",
				"ideaecb", "md4", "md5", "sha" };
		(fd, e) = auth->server(algs, ai, fd, 0);
	}
	if(fd == nil)
		werrstr("auth failed: " + e);
	return(fd, e);
}
