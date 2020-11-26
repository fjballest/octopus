CopyLib: module
{
	PATH: con "/dis/o/copylib.dis";
	copy_local: fn(src, dst: string, srcoff, dstoff, nofbytes: big): (string, big);
	copy_p2p: fn(src, dst: string, srcoff, dstoff, nofbytes: big): (string, big);
	trace_p2p: fn(on: int);
};


