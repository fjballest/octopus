implement Livedat;
include "mods.m";

loads()
{
	sys = load Sys Sys->PATH;
	err = load Error Error->PATH;
	err->init(sys);
	mods = ref Mods;
	mods.sys = sys;
	mods.err = err;
	mods.math = checkload(load Math Math->PATH, Math->PATH);
	mods.arg = checkload(load Arg Arg->PATH, Arg->PATH);
	mods.wmcli = checkload(load Wmclient Wmclient->PATH, Wmclient->PATH);
	mods.names = checkload(load Names names->PATH, Names->PATH);
	mods.draw = checkload(load Draw Draw->PATH, Draw->PATH);
	mods.gui = checkload(load Gui Gui->PATH, Gui->PATH);
	mods.readdir = checkload(load Readdir Readdir->PATH, Readdir->PATH);
	mods.menus = checkload(load Menus Menus->PATH, Menus->PATH);
	mods.wpanel = checkload(load Wpanel Wpanel->PATH, Wpanel->PATH);
	mods.wtree = checkload(load Wtree Wtree->PATH, Wtree->PATH);
	mods.layout = checkload(load Layout Layout->PATH, Layout->PATH);
	mods.merop = checkload(load Merop Merop->PATH, Merop->PATH);
	mods.blks = checkload(load Blks Blks->PATH, Blks->PATH);
	mods.io = checkload(load Io Io->PATH, Io->PATH);
	mods.str = checkload(load String String->PATH, String->PATH);
	mods.random = checkload(load Random Random->PATH, Random->PATH);
}
