SDL1 = 1
WARNS = -Wno-write-strings -Wno-pointer-arith
ifdef SDL1
WARNS += -DSDL1
endif
# debug flags
# CFLAGS=-Wall -g `sdl-config --cflags ` $(WARNS)

# opt flags
CFLAGS=-O2 `sdl-config --cflags` $(WARNS)

%.o: %.c
	g++ $(CFLAGS) -c $< -o $@

all: bmovl

bmovl: bmovl.o lib.o savesurf.o
ifdef SDL1
	g++ -g -o $@ bmovl.o lib.o savesurf.o `sdl-config --libs` -lSDL_image -lSDL_ttf -lSDL_gfx -lpng
else
	g++ -g -o $@ bmovl.o lib.o savesurf.o `sdl2-config --libs` -lSDL2_image -lSDL2_ttf -lSDL2_gfx -lpng
endif
clean:
	rm -f bmovl *.o
