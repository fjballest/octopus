include "sys.m";
	sys: Sys;
	Dir, NEWPGRP, DMDIR, open, OTRUNC, OREAD, FD, OWRITE, ORCLOSE, FORKFD,
	ORDWR, FORKNS, NEWFD, MREPL, MBEFORE, MAFTER, MCREATE, pipe, mount, 
	seek, stat, werrstr,
	fprint, write, sprint, tokenize, bind, create, pwrite, read, QTDIR, QTFILE, fildes, Qid: import sys;
include "draw.m";
	draw: Draw;
	Point, Display, Font, Rect, Pointer, Image: import draw;
include "tk.m";
include "string.m";
	str: String;
	drop, splitl: import str;
include "math.m";
	math: Math;
include "wmclient.m";
	wmcli: Wmclient;
	Window: import wmcli;
include "readdir.m";
	readdir: Readdir;
include "keyboard.m";
include "keyring.m";
include "security.m";
	random:	Random;
include "error.m";
	err: Error;
	checkload, stderr, panic, kill, error: import err;
include "io.m";
	io: Io;
	readfile: import io;
include "names.m";
	names: Names;
	isprefix: import names;
include "menus.m";
	menus: Menus;
include "livedat.m";
	dat: Livedat;
include "gui.m";
	gui: Gui;
include "wpanel.m";
	wpanel: Wpanel;
include "wtree.m";
	wtree: Wtree;
include "arg.m";
	arg: Arg;
include "layout.m";
	layoutm: Layout;
include "blks.m";
	blks: Blks;
include "../mero/merop.m";
	merop: Merop;

initmods()
{
	sys = mods.sys;
	err = mods.err;
	math = mods.math;
	arg = mods.arg;
	wmcli = mods.wmcli;
	names = mods.names;
	draw = mods.draw;
	gui = mods.gui;
	readdir = mods.readdir;
	io = mods.io;
	menus = mods.menus;
	wpanel = mods.wpanel;
	wtree = mods.wtree;
	layoutm = mods.layout;
	random = mods.random;
	merop = mods.merop;
	blks = mods.blks;
	str = mods.str;
}
