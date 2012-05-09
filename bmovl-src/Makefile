# debug flags
# CFLAGS=-Wall -g `sdl-config --cflags `

# opt flags
CFLAGS=-O2 `sdl-config --cflags`

%.o: %.c
	gcc $(CFLAGS) -c $< -o $@

all: bmovl

bmovl: bmovl.o lib.o savesurf.o
	$(CC) -g -o $@ bmovl.o lib.o savesurf.o `sdl-config --libs` -lSDL_image -lSDL_ttf -lSDL_gfx -lpng

clean:
	rm -f bmovl *.o 
