implement Browsercmd;

include "browsercmd.m";

include "sys.m";
	sys: Sys;
	Dir, pctl, NEWPGRP, DMDIR, open, OREAD, FD, OWRITE, OTRUNC,  ORCLOSE, FORKFD,
	ORDWR, FORKNS, NEWFD, MREPL, MBEFORE, MAFTER, MCREATE, pipe, mount,
	print, fprint, sprint, seek, tokenize, create, write, read, QTDIR, QTFILE, fildes, Qid: import sys;

include "draw.m";

include "error.m";
	err: Error;
	checkload, stderr, panic, kill, error: import err;

include "string.m";
	str: String;
	splitr: import str;

include "env.m";
	env: Env;
	getenv: import env;

include "regex.m";
     	regex: Regex;

BM, OP, HI, PU, CL, ST, RS, RU: 	con iota;

user := "";

BFSMACOSX: con "/usr/octopus/bin/MacOSX/browserfs.scpt";
HIPLISTPATH:	con  "/Library/Safari/History.plist"; # path from user's home in macosx
BOPLISTPATH:	con  "/Library/Safari/Bookmarks.plist"; # path from user's home in macosx
EPOCHMAC : 	con 978307200; 

# Don't try to understand this, keep the faith
# This regexp finds the "obookmarks" subtree if exists
INFERNALREGEXP:	con    "<dict>[\n\r	 ]+" +
		"<key>Children</key>[\n\r	 ]+" +
		"<array>[\n\r	 ]+" +
		"(<dict>[\n\r	 ]+" +
		"<key>URIDictionary</key>[\n\r	 ]+" +
		"<dict>[\n\r	 ]+" +
		"<key>.*</key>[\n\r	 ]+" +
		"<string>.*</string>[\n\r	 ]+" +
		"<key>.*</key>[\n\r	 ]+" +
		"<string>.*</string>[\n\r	 ]+" +
		"</dict>[\n\r	 ]+" +
		"<key>URLString</key>[\n\r	 ]+" +
		"<string>.+</string>[\n\r	 ]+" +
		"<key>WebBookmarkType</key>[\n\r	 ]+" +
		"<string>WebBookmarkTypeLeaf</string>[\n\r	 ]+" +
		"<key>WebBookmarkUUID</key>[\n\r	 ]+" +
		"<string>.*</string>[\n\r	 ]+" +
		"</dict>[\n\r	 ]+" +
		")*</array>[\n\r	 ]+" +
		"<key>Title</key>[\n\r	 ]+" +
		"<string>[Oo]bookmarks</string>[\n\r	 ]+" +
		"<key>WebBookmarkType</key>[\n\r	 ]+" +
		"<string>WebBookmarkTypeList</string>[\n\r	 ]+" +
		"<key>WebBookmarkUUID</key>[\n\r	 ]+" +
		"<string>.*</string>[\n\r	 ]+" +
		"</dict>";

# to find the tree if it's empty
NOITEMSREGEXP:	con    "<dict>[\n\r	 ]+" +
		"<key>Title</key>[\n\r	 ]+" +
		"<string>[Oo]bookmarks</string>[\n\r	 ]+" +
		"<key>WebBookmarkType</key>[\n\r	 ]+" +
		"<string>WebBookmarkTypeList</string>[\n\r	 ]+" +
		"<key>WebBookmarkUUID</key>[\n\r	 ]+" +
		"<string>.*</string>[\n\r	 ]+" +
		"</dict>";

# to find the last bookmark folder (to create the "obookmarks" folder)
ENDBOOKREGEXP: con "</array>[\n\r	 ]+" +
		"(<key>Title</key>[\n\r	 ]+" +
		"<string>.*</string>[\n\r	 ]+)?" +
		"<key>WebBookmarkFileVersion</key>[\n\r	 ]+" +
		"<integer>.*</integer>[\n\r	 ]+" +
		"<key>WebBookmarkType</key>[\n\r	 ]+" +
		"<string>WebBookmarkTypeList</string>[\n\r	 ]+" +
		"<key>WebBookmarkUUID</key>[\n\r	 ]+" +
		"<string>.*</string>[\n\r	 ]+" +
		"</dict>[\n\r	 ]+" +
		"</plist>";


init(): string
{
	debug = 0;
	sys = load Sys Sys->PATH;
	if(sys == nil)
		error("cannot load Sys");
	err = load Error Error->PATH;
	if(err == nil)
		error("cannot load Error");
	err->init(sys);
	env = load Env Env->PATH;
	if(env == nil)
		error("cannot load Regex");
	regex = load Regex Regex->PATH;
	if(regex == nil)
		error("cannot load Regex");
	str = load String String->PATH;
	if(str == nil)
		error("cannot load String");
	return nil;
}


# writes a new history file from scratch
puthistory(history: string): int
{	
	if(user == ""){
		user = "";
		user = getenv("user");
	}
	if(user == "")
		error("cannot get $user");
	bstr := tohisplist(history);
	if(bstr == nil){
		if(debug) fprint(fildes(2), "puthistory: can't make xml from data\n"); 
		return -1;
	}
	newfile := "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
				"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\""+
				"\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">" +
				"<plist version=\"1.0\">\n" +
				"<dict>\n" +
				"	<key>WebHistoryDates</key>\n" +
				"	<array>\n" ;
	newfile = newfile + bstr;
	newfile = newfile +"	</array>\n" +
				"	<key>WebHistoryFileVersion</key>\n" +
				"	<integer>1</integer>\n" +
				"</dict>\n" +
				"</plist>\n";
	if(putfile(newfile, "#U*" + "/Users/" + user + HIPLISTPATH) < 0){
		if(debug) fprint(fildes(2), "puthistory: can't write file\n"); 
		return -1;
	}
	return 0;
}


# creates the "obookmarks" folder in the plist 
createobookfolder(in: string): string
{
	(rg, nil) := regex->compile(ENDBOOKREGEXP, 0);
	arr := regex->execute(rg, in);
	if(arr == nil){
		if(debug) fprint(fildes(2), "createobookfolder: regexp not found\n");
		return nil;
	}
	(b, nil) := arr[0];
	newfile := in[0:b-1];
	newfile = newfile + 
			"		<dict>\n" +
			"			<key>Title</key>\n" +
			"			<string>obookmarks</string>\n" +
			"			<key>WebBookmarkType</key>\n" +
			"			<string>WebBookmarkTypeList</string>\n" +
			"			<key>WebBookmarkUUID</key>\n" +
			"			<string>FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF</string>\n" +
			"		</dict>\n";
	newfile = newfile + in[b:];
	return newfile;
}


# replaces *all* bookmarks in the obookmark folder
putbookmarks(bmarks: string): int
{
	if(user == ""){
		user = "";
		user = getenv("user");
	}
	if(user == "")
		error("cannot get $user");
	filestr := plistplain("/Users/" + user + BOPLISTPATH); 
	if(filestr == nil){
		if(debug) fprint(fildes(2), "putbookmarks: can't convert bin to xml\n");
		return -1;
	}
	(rg, errstr) := regex->compile(INFERNALREGEXP, 0);
	if(rg == nil)
		error("cannot compile regexp: " + errstr);
	arr := regex->execute(rg, filestr);
	if(arr == nil){
		(rg2, errstr2) := regex->compile(NOITEMSREGEXP, 0);
		if(rg2 == nil)
			error("cannot compile regexp: " + errstr2);
		arr = regex->execute(rg2, filestr);
		if(arr == nil){
			if(debug) fprint(fildes(2), "putbookmarks: no obookmark folder, trying to create it\n");
			filestr = createobookfolder(filestr);
			if(filestr == nil){
				if(debug) fprint(fildes(2), "putbookmarks: can't create obookmark folder\n");
				return -1;
			}
			arr = regex->execute(rg2, filestr);
			if(arr == nil){
				if(debug) fprint(fildes(2), "putbookmarks: obookmark folder not created\n");
				return -1;
			}	
			if(debug) fprint(fildes(2), "putbookmarks: obookmark folder created\n");
		}
	}
	(b, e) := arr[0];
	bstr := toplist(bmarks);
	if(bstr == nil)
		return -1;
	#replace the whole "obookmarks" subtree 
	newfile := "";
	newfile = filestr[0:b-1];
	newfile = newfile + bstr;
	newfile = newfile + filestr[e:];
	# write back
	if(putfile(newfile,  "#U*" + "/Users/" + user + BOPLISTPATH) < 0){
		if(debug) fprint(fildes(2), "putbookmarks: putfile failed\n");
		return -1;
	}
	return 0;
}	
		

getstatus(): string
{
	(nil, data) := execbrowsercmd(RU,nil);
	# just in case...
	if(data == nil) 
		return "not running";
	return data;
}


restartbrowser(): int
{
	(er, nil) := execbrowsercmd(RS, nil);
	return er;
}


startbrowser(): int
{	
	(er, nil) := execbrowsercmd(ST, nil);
	return er;
}

closebrowser(): int
{	
	(er, nil) := execbrowsercmd(CL, nil);
	return er;
}


openurls(urls: string): int
{
	(n, toks) := tokenize(urls, " \n\t\r");
	if(n < 1) 
		return -1;
	strurls := "";
	for (; toks != nil ; toks = tl toks){
		strurls =  strurls + " '" + hd toks + "' ";
	}
	(er, nil):= execbrowsercmd(PU, strurls);
	return er;
}


getbookmarks():string
{	
	(nil, data) := execbrowsercmd(BM,nil);
	return data;
}


getopen():string
{	
	(nil, data) :=  execbrowsercmd(OP,nil);
	return data;
}


gethistory():string
{	
	(nil, data) := execbrowsercmd(HI,nil);
	return data;
}



# All these commands are executed by an Applescript 
# Cons are used to make the rest of the code independent from the applescript
# script arguments. It's quite redundant, anyway.
execbrowsercmd(cmd: int, args: string): (int, string)
{	
	strcmd: string;
	strcmd = nil;

	case cmd{
		BM =>
			strcmd = "getbookmarks";
		HI =>
			strcmd = "gethistory";
		OP =>
			strcmd = "getopen ";
		PU =>
			if(args == nil)
				error("bug: execbrowsercmd, puturls, args is nil");
			strcmd = "open " +  args;
		CL =>
			strcmd = "close";
		ST =>
			strcmd = "start";
		RS => 
			strcmd = "restart";
		RU =>
			strcmd = "status";
		* => 
			error("bug: execbrowsercmd, unknown command");
	}
	u := getenv("user"); 
	r := getenv("emuroot");
	if (r == nil)
		r = "/Users/" + u + "/Library/Octopus/";
	finalstr := "osascript   " +  r  + BFSMACOSX + "   " + strcmd;
  	if(debug) fprint(fildes(2), "execbrowsercmd: executing '%s\n'", finalstr);
	return execcmd(finalstr);
}


# cmd is a string with the line to execute in the host's shell (includes the arguments)
execcmd(cmd: string) : (int, string)
{	
	cfd := open("#C/cmd/clone", ORDWR);
	if (cfd == nil)
		return (-1,nil);

	nam := array[30] of byte;
	nr := read(cfd, nam, len nam);
	if (nr <= 0)
		return (-1,nil);

	dir := "#C/cmd/" + string nam[0:nr];
	wfd := open(dir + "/wait", OREAD);
	if (wfd == nil)
		return (-1,nil);

	efd := open(dir + "/ctl", OWRITE);
	if (efd == nil)
		return (-1,nil);

	fprint(efd, "exec %s", cmd);
	sts := array[1024] of byte;
	nr = read(wfd, sts, len sts);
	if(nr <= 0)
		return (-1,nil);

	dfd :=  open(dir + "/data", OREAD);
	if(dfd == nil)
		return (-1,nil);

	data := "";
	dbuf := array[1024*4] of byte; 
	while((nr = read(dfd, dbuf, len dbuf)) > 0){
		data = data + (string dbuf[0:nr-1]);
	}
	if(nr < 0)
		return (-1,nil);

	efd = nil;
	dfd = nil;
	wfd = nil;
	cfd = nil;
	return (0, data);
}

# uses the OSX plutil command to convert the plist file to xml
bin2plain(path: string): int
{
	cfd := open("#C/cmd/clone", ORDWR);
	if (cfd == nil)
		return -1;
	nam := array[30] of byte;
	nr := read(cfd, nam, len nam);
	if (nr <= 0)
		return -1;
	dir := "#C/cmd/" + string nam[0:nr];
	wfd := open(dir + "/wait", OREAD);
	if (wfd == nil)
		return -1;
	efd := open(dir + "/ctl", OWRITE);
	if (efd == nil)
		return -1;
	spell := "exec plutil -convert xml1  " + path;
	fprint(efd, "%s\n", spell);
	sts := array[1024] of byte;
	nr = read(wfd, sts, len sts);
	if(nr <= 0)
		return -1;
	dfd :=  open(dir + "/data", OREAD);
	if(dfd == nil)
		return -1;
	dbuf := array[1024*4] of byte; 
	while((nr = read(dfd, dbuf, len dbuf)) > 0){
		#no op, we don't care about its output
	}
	if(nr < 0)
		return -1;

	efd = nil;
	dfd = nil;
	wfd = nil;
	cfd = nil;
	return 0;
}


# tells you if the plist is xml (it's not in  binary format)
isxml(fd: ref FD): int
{
	buf := array [20] of byte;

	seek(fd, big 0 ,Sys->SEEKSTART);
	n := read(fd, buf, 20);
	if(n != 20)
		return 0;
	s1 := string buf[0:19];
	s2 := "<?xml version=\"1.0\"";
	return s1 == s2;
}


# converts the plist if needed, and reads it all
plistplain(pathplist: string): string
{	
	maxlen := 1024*1024*10;
	fd := sys->open("#U*" + pathplist, sys->ORDWR);
	if(fd == nil)	
		error("cannot open  " + "#U*" + pathplist);
	if(isxml(fd) == 0){
		if (bin2plain(pathplist) < 0)
			return nil;
		if(isxml(fd) == 0)
			return nil;
	}
	seek(fd, big 0, Sys->SEEKSTART);
	buff := array[maxlen] of byte; 
	done := 0;
	nr := 0;
	while((nr = read(fd, buff, maxlen - done)) > 0){
		done += nr;
		if(done == maxlen)  # too long!!
			return nil;
	}
	if(nr < 0)
		return nil;
	ret := string buff[0:done];
	fd = nil;
	return ret;
}


# in mac os x, dates are seconds since 1/1/2001 00:00
# we have to add EPOCHMAC (978307200 seconds) to get a Unix date (s since epoch) 
tohisplist(lines: string): string
{
	xml := "";
	(n, l) := tokenize(lines, "\n");
	if(n <= 0)
		return nil;
	for(i := 0 ; i < n ; i++){
		line := hd l;
		l = tl l;
		(nn, toks) :=  tokenize(line, " 	");
		if(nn < 3)
			return nil;
		(time, nil)  :=  str->toint(hd toks, 10);
		time = time - EPOCHMAC;
		toks = tl toks;
		url := hd toks;
		toks = tl toks;
		desc := "";
		for(j := 0 ; j < nn-2 ; j++){
			desc = desc +  hd toks + " ";
			toks = tl toks;
		}
		xml = xml + "		<dict>\n			<key></key>\n" +
			"			<string>" + xmlencode(url) + "</string>\n" +
			"			<key>lastVisitedDate</key>\n" +
			"			<string>"+ string time +"</string>\n" +
			"			<key>title</key>\n			" +
			"<string>" + xmlencode(desc) + "</string>\n			" +
			"<key>visitCount</key>\n			" +
			"<integer>1</integer>\n		</dict>\n";
	
	}
	return xml;
}



# We ignore the WebBookmarkUUID, all obookmarks  have FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF
# This id is used fot ISync
toplist(lines: string): string
{
	xml := "		<dict>\n			<key>Children</key> \n				<array>";

	(n, l) := tokenize(lines, "\n");
	if(n <= 0)
		return nil;
	for(i := 0 ; i < n ; i++){
		line := hd l;
		l = tl l;
		
		(nn, toks) :=  tokenize(line, " 	");
		if(nn < 2)
			return nil;
		url := hd toks;
		toks = tl toks;
		desc := "";
		for(j := 0 ; j < nn-1 ; j++){
			desc = desc +  hd toks + " ";
			toks = tl toks;
		}
		xml = xml + "\n				<dict>\n" +
				"					<key>URIDictionary</key>\n"+
				"					<dict>\n"+
				"						<key></key>\n" +
				"						<string>"  +  xmlencode(url)  +  
				"</string>\n						<key>title</key>\n" +
				"						<string>" +  xmlencode(desc)   +   
				"</string>\n					</dict>\n"  +
				"					<key>URLString</key>\n" +
				"					<string>"  +  xmlencode(url)  + "</string>\n" +
				"					<key>WebBookmarkType</key>\n" +
				"					<string>WebBookmarkTypeLeaf</string>\n" +
				"					<key>WebBookmarkUUID</key>\n" +
				"					<string>FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF</string>\n" +
				"				</dict>\n";
	
	}

	return xml + "			</array>\n			<key>Title</key>\n" +
			"			<string>obookmarks</string>\n			" +
			"<key>WebBookmarkType</key>\n			<string>WebBookmarkTypeList</string>\n" +
			"			<key>WebBookmarkUUID</key>\n			" +
			"<string>FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF</string>\n		</dict>\n";
}


# writes the file back
putfile(data: string,  path: string): int
{
	fd := open(path, OWRITE|OTRUNC);
	if(fd == nil){
		if(debug) fprint(fildes(2), "putfile: can't open file %s\n", path);
		return -1;
	}
	buf := array of byte data;
	n := write(fd, buf, len buf);
	if(n != len buf){
		if(debug) fprint(fildes(2), "putfile: write failed, n is %d and should be %d\n", n, len buf );
		return  -1;
	}
	fd = nil;
	return 0;
}


# translates runes to xml escape codes: & < > ' "
xmlencode(str: string): string
{
	newstr := "";
	for(i:=0 ; i<len str ; i++){
		case str[i]{
		'&' => 
			newstr = newstr + "&amp;";
		'<' =>
			newstr = newstr + "&lt;";
		'>' =>
			newstr = newstr + "&gt;";
		'"' =>
			newstr = newstr + "&quot;";
		'\''=>
			 newstr = newstr + "&apos;";
		* =>
			newstr[len newstr] = str[i];
		}
	}
	return newstr;
}


