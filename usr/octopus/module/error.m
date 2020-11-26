Error: module {
	PATH: con "/dis/o/error.dis";

	init:	fn(s: Sys);
	kill:	fn (pid: int, msg: string): int;
	error:	 fn(e: string);
	panic: 	fn(e: string);
	checkload: fn[T](x: T, p: string): T;


	stderr: ref Sys->FD;

};
