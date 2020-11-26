implement Oxdat;
include "mods.m";

loadmods(s: Sys, e: Error)
{
	sys = mods.sys = s;
	err = mods.err = e;
	mods.daytime = checkload(load Daytime Daytime->PATH, Daytime->PATH);
	mods.env = checkload(load Env Env->PATH, Env->PATH);
	mods.io = checkload(load Io Io->PATH, Io->PATH);
	mods.names = checkload(load Names Names->PATH, Names->PATH);
	mods.oxedit = checkload(load Oxedit Oxedit->PATH, Oxedit->PATH);
	mods.oxex = checkload(load Oxex Oxex->PATH, Oxex->PATH);
	mods.oxload = checkload(load Oxload Oxload->PATH, Oxload->PATH);
	mods.panels = checkload(load Panels Panels->PATH, Panels->PATH);
	mods.readdir = checkload(load Readdir Readdir->PATH, Readdir->PATH);
	mods.regx = checkload(load Regx Regx->PATH, Regx->PATH);
	mods.sam = checkload(load Sam Sam->PATH, Sam->PATH);
	mods.samcmd = checkload(load Samcmd Samcmd->PATH, Samcmd->PATH);
	mods.samlog = checkload(load Samlog Samlog->PATH, Samlog->PATH);
	mods.sh = checkload(load Sh Sh->PATH, Sh->PATH);
	mods.str = checkload(load String String->PATH, String->PATH);
	mods.tblks = checkload(load Tblks Tblks->PATH, Tblks->PATH);
	mods.workdir = checkload(load Workdir Workdir->PATH, Workdir->PATH);
	mods.os = checkload(load Os Os->PATH, Os->PATH);
}
