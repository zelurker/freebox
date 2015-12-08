while (<>) {
	s/\\\//\//g;
	s/%(..)/chr(hex($1))/ge;
	s/generate_204/videoplayback/g;
	s/\\u(....)/chr(hex($1))/ge;
	print;
}

