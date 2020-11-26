# machine dependent voice support
#
Mvoice: module {
	PATH: con "/dis/o/mvoice.dis";

	init:		fn(): string;
	speak:	fn(text: string): string;
};
