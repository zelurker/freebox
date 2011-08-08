/* Small program to test the features of vf_bmovl */

#include <unistd.h>
#include <fcntl.h>
#include <SDL/SDL.h>
#include <SDL/SDL_ttf.h>
#include <SDL/SDL_image.h>
#include "lib.h"

int main(int argc, char **argv) {

	int fifo=-1;
	int width=0, height=0;
	int i;

	if(argc<4) {
		printf("Usage: %s <bmovl fifo> <width> <height> <font size>\n", argv[0]);
		printf("width and height are w/h of MPlayer's screen!\n");
		exit(10);
	}

	int fsize = atoi(argv[4]);
	TTF_Init();
	TTF_Font *font = TTF_OpenFont("Vera.ttf",fsize);
	if (!font) font = TTF_OpenFont("/usr/share/fonts/truetype/ttf-bitstream-vera/Vera.ttf",12);
	if (!font) {
		printf("Could not load Vera.ttf, come back with it !\n");
		return -1;
	}

	char *channel,*picture,*heure, *title, *desc,buff[2048];
	SDL_Surface *chan = NULL,*pic = NULL;
	myfgets(buff,2048,stdin);
	channel = strdup(buff);
	myfgets(buff,2048,stdin);
	picture = strdup(buff);
	if (*channel) chan = IMG_Load(channel);
	if (*picture) pic = IMG_Load(picture);
	myfgets(buff,2048,stdin);
	heure = strdup(buff);
	myfgets(buff,2048,stdin);
	title = strdup(buff);

	/* Determine max length of text */
	width = atoi(argv[2]);
	height = atoi(argv[3]);
	if (chan && chan->w >= width/2) {
		printf("channel too wide, dropping it\n");
		SDL_FreeSurface(chan);
		chan = NULL;
	}
	if (pic && pic->w >= width/2) {
		SDL_FreeSurface(pic);
		pic = NULL;
	}

	int myx,w=0,h;
	if (chan) w = chan->w;
	if (pic && pic->w>w) w = pic->w;
	if (w) myx = 26+w; else myx = 18;
	int wtext=0,htext=0;
	buff[0] = 0;
	int len = 0;
	// Carrier returns are included, a loop is mandatory then
	while (!feof(stdin) && len < 2047) {
		fgets(&buff[len],2048-len,stdin); // we keep the eol here
		while (buff[len]) len++;
	}
	while (buff[len-1] < 32) buff[--len] = 0; // remove the last one though
	desc = strdup(buff);
	printf("time : %s\ntitle : %s\ndesc : %s\n...\n",heure,title,desc);

	TTF_SetFontStyle(font,TTF_STYLE_BOLD);
	get_size(font,heure,&w,&h,width-32); // 1st string : all the width (top)
	htext += h;
	wtext = w;
	int himg = h;
	int maxw = 0;
	if (pic) maxw = pic->w;
	if (chan && chan->w>maxw) maxw = chan->w;
	if (maxw) maxw = width-maxw-24;
	else
		maxw = width - 32;

	get_size(font,title,&w,&h,maxw);
	htext += h;
	if (w > wtext) wtext = w;
	TTF_SetFontStyle(font,TTF_STYLE_NORMAL);
	htext += 12;
	get_size(font,desc,&w,&h,maxw);
	htext += h;
	if (w > wtext) wtext = w;
	if (h > height-16) h = height-16;

	printf("text total width %d height %d\n",wtext,htext);

	Uint32 rmask, gmask, bmask, amask;

	/* SDL interprets each pixel as a 32-bit number, so our masks must depend
	 *         on the endianness (byte order) of the machine */
#if SDL_BYTEORDER == SDL_BIG_ENDIAN
	rmask = 0xff000000;
	gmask = 0x00ff0000;
	bmask = 0x0000ff00;
	amask = 0x000000ff;
#else
	rmask = 0x000000ff;
	gmask = 0x0000ff00;
	bmask = 0x00ff0000;
	amask = 0xff000000;
#endif

	if (pic) himg += 8+pic->h;
	if (chan) himg += 8+chan->h;
	if (himg > htext) htext = himg;
	h = (htext + 16+12 < height-16 ? htext + 16+12 : height-16);

	SDL_Surface *sf = SDL_CreateRGBSurface(SDL_SWSURFACE,width,
			h,32,rmask,gmask,bmask,amask);
	printf("bitmap %d x %d\n",sf->w,sf->h);
	int bg = SDL_MapRGB(sf->format,0x20,0x20,0x70);
	int fg = SDL_MapRGB(sf->format,0xff,0xff,0xff);
	SDL_FillRect(sf,NULL,fg);
	SDL_Rect r; r.x = r.y = 1; r.w = sf->w - 2; r.h = sf->h-2;
	SDL_FillRect(sf,&r,bg);

	// Ok, finalement on affiche les chaines (heure, titre, desc)
	int x = myx;
	int y = 8;
	printf("output x : %d\n",x);
	TTF_SetFontStyle(font,TTF_STYLE_BOLD);
	y += put_string(sf,font,18,y,heure,fg,width-32,0,width,h-8);
	r.x = 18;
	r.y = y;
	if (chan) {
		SDL_BlitSurface(chan,NULL,sf,&r);
		r.y += chan->h+8;
		SDL_FreeSurface(chan);
	}
	if (pic) {
		SDL_BlitSurface(pic,NULL,sf,&r);
		r.y += pic->h+8;
		SDL_FreeSurface(pic);
	}
	y += put_string(sf,font,x,y,title,fg,width-x-18,r.y,width,h-8);
	y += 12;
	TTF_SetFontStyle(font,TTF_STYLE_NORMAL);
	y += put_string(sf,font,x,y,desc,fg,width-x-18,r.y,width,h-8);

	fifo = open( argv[1], O_RDWR );
	if(!fifo) {
		fprintf(stderr, "Error opening FIFO %s!\n", argv[1]);
		exit(10);
	}

	/*
	   image = IMG_Load(argv[2]);
	   if(!image) {
	   fprintf(stderr, "Couldn't load image %s!\n", argv[2]);
	   exit(10);
	   }

	   printf("Loaded image %s: width=%d, height=%d\n", argv[2], image->w, image->h);
	   */

	// Display
	send_command(fifo,"SHOW\n");
	x = (width-sf->w) / 2;
	y = height - sf->h - 8;
	blit(fifo, sf->pixels, sf->w, sf->h, x, y, 0, 1);
	sleep(10);

	// Fade in sf
	for(i=0; i >= -255; i-=5)
		set_alpha(fifo, sf->w, sf->h,
				x, y, i);

	// Clean up
	SDL_FreeSurface(sf);
	send_command(fifo,"HIDE\n");
	close(fifo);
	return 0;
}
