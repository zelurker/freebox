# debug flags
CLFAGS=-Wall -g `sdl-config --cflags `

# opt flags
# CLFAGS=-O2 `sdl-config --cflags`

%.o: %.c
	gcc $(CFLAGS) -c $< -o $@

bmovl: bmovl.o lib.o
	$(CC) -o $@ bmovl.o lib.o `sdl-config --libs` -lSDL_image -lSDL_ttf 

clean:
	rm -f bmovl lib.o
