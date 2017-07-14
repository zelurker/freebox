WARNS = -Wno-write-strings -Wno-pointer-arith -DSDL1
# debug flags
# CFLAGS=-Wall -g `sdl-config --cflags ` $(WARNS)

# opt flags
CFLAGS=-O2 `sdl-config --cflags` $(WARNS)

%.o: %.c
	g++ $(CFLAGS) -c $< -o $@

all: bmovl

bmovl: bmovl.o lib.o savesurf.o
	g++ -g -o $@ bmovl.o lib.o savesurf.o `sdl-config --libs` -lSDL_image -lSDL_ttf -lSDL_gfx -lpng

clean:
	rm -f bmovl *.o
