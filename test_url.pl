while (<>) {
	s/\\\//\//g;
	s/generate_204/videoplayback/g;
	s/\\u(....)/chr(hex($1))/ge;
	while (s/%(..)/chr(hex($1))/ge) {}
	print;
}

