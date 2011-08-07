/* Small program to test the features of vf_bmovl */

#include <unistd.h>
#include <fcntl.h>
#include <SDL/SDL.h>
#include <SDL/SDL_image.h>
#include <SDL/SDL_ttf.h>

#define DEBUG 0

static void
blit(int fifo, unsigned char *bitmap, int width, int height,
     int xpos, int ypos, int alpha, int clear)
{
	char str[100];
	int  nbytes;
	
	sprintf(str, "RGBA32 %d %d %d %d %d %d\n",
	        width, height, xpos, ypos, alpha, clear);
	
	if(DEBUG) printf("Sending %s", str);

	write(fifo, str, strlen(str));
	nbytes = write(fifo, bitmap, width*height*4);

	if(DEBUG) printf("Sent %d bytes of bitmap data...\n", nbytes);
}

static void
set_alpha(int fifo, int width, int height, int xpos, int ypos, int alpha) {
	char str[100];

	sprintf(str, "ALPHA %d %d %d %d %d\n",
	        width, height, xpos, ypos, alpha);
	
	if(DEBUG) printf("Sending %s", str);

	write(fifo, str, strlen(str));
}

static void
paint(unsigned char* bitmap, int size, int red, int green, int blue, int alpha) {

	int i;

	for(i=0; i < size; i+=4) {
		bitmap[i+0] = red;
		bitmap[i+1] = green;
		bitmap[i+2] = blue;
		bitmap[i+3] = alpha;
	}
}

static void send_command(int fifo,char *cmd) {
	write(fifo,cmd,strlen(cmd));
}

static void reformat_string(char *str, int len) {
	if (strlen(str) > len) {
		char *t = str;
		while (strlen(t) > len) {
			char old = t[len]; t[len] = 0;
			char *s = strrchr(t,' ');
			t[len] = old;
			if (s) *s = '\n'; else break;
			t = s+1;
		}
	}
}

static void get_size(TTF_Font *font, char *text, int *w, int *h) {
	/* Version de TTF_SizeText qui s'adapte aux retours charriots */
	*w = 0; *h = 0;
	char *beg = text, *s;
	int myw,myh;
	do {
		s = strchr(beg,'\n');
		if (s) *s = 0;
		TTF_SizeText(font,beg,&myw,&myh);
		if (myw > *w) *w = myw;
		*h += myh;
		if (s) {
			*s = '\n';
			beg = s+1;
		}
	} while (s);
}

static int put_string(SDL_Surface *sf, TTF_Font *font, int x, int y,
		char *text, int color)
{
	/* Gère les retours charriots dans la chaine, renvoie la hauteur totale */
	int h = 0;
	char *beg = text,*s;
	do {
		s = strchr(beg,'\n');
		if (s) *s = 0;
		if (*beg) {
			SDL_Rect dest;
			dest.x = x; dest.y = y;
			SDL_Color *col = (SDL_Color*)&color; // dirty hack !
			SDL_Surface *tf = TTF_RenderText_Solid(font,beg,*col);
			SDL_BlitSurface(tf,NULL,sf,&dest);
			h += tf->h;
			y += tf->h;
			SDL_FreeSurface(tf);
		} else {
			h += 12;
			y += 12;
		}
		if (s) {
			*s = '\n';
			beg = s+1;
		}
	} while (s && *beg);
	return h;
}

static int myfgets(char *buff, int size, FILE *f) {
  fgets(buff,size,f);
  int len = strlen(buff);
  while (len > 0 && buff[len-1] < 32)
    buff[--len] = 0;
  return len;
}

int main(int argc, char **argv) {

	int fifo=-1;
	int width=0, height=0, xpos=0, ypos=0, alpha=0, clear=0;
	int i;

	
	/*
	if(argc<3) {
		printf("Usage: %s <bmovl fifo> <width> <height> <font size>\n", argv[0]);
		printf("width and height are w/h of MPlayer's screen!\n");
		exit(10);
	}
	*/

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
	printf("after img_load chan from %s:%x pic %s:%x\n",channel,chan,picture,pic);
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
	if (w) myx = 16+w; else myx = 8;
	int wtext=0,htext=0;
	TTF_SizeText(font,"abcdefghij",&w,&h);
	int maxl = (width-myx-8)*10/w;
	printf("maxl = %d myx %d\n",maxl,myx);
	reformat_string(title,maxl);
	buff[0] = 0;
	int len = 0;
	// Carrier returns are included, a loop is mandatory then
	while (!feof(stdin) && len < 2047) {
		myfgets(&buff[len],2048-len,stdin);
		len = strlen(buff);
	}
	desc = strdup(buff);
	reformat_string(desc,maxl);
	printf("time : %s\ntitle : %s\ndesc : %s\n...\n",heure,title,desc);

	TTF_SetFontStyle(font,TTF_STYLE_BOLD);
	TTF_SizeText(font,heure,&w,&h);
	htext += h;
	wtext = w;
	get_size(font,title,&w,&h);
	htext += h;
	if (w > wtext) wtext = w;
	TTF_SetFontStyle(font,TTF_STYLE_NORMAL);
	htext += 12;
	get_size(font,desc,&w,&h);
	htext += h;
	if (w > wtext) wtext = w;
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

	w = (width >= 720 ? 720 : width);
	h = 0;
	if (pic) h = 8+pic->h;
	if (chan) h += 8+chan->h;
	if (h > htext) htext = h;
	h = (htext + 16 < height ? htext + 16 : height);

	SDL_Surface *sf = SDL_CreateRGBSurface(SDL_SWSURFACE,w,
			h,32,rmask,gmask,bmask,amask);
	int bg = SDL_MapRGB(sf->format,0x20,0x20,0x70);
	int fg = SDL_MapRGB(sf->format,0xff,0xff,0xff);
	SDL_FillRect(sf,NULL,fg);
	SDL_Rect r; r.x = r.y = 1; r.w = sf->w - 2; r.h = sf->h-2;
	SDL_FillRect(sf,&r,bg);
	r.x = 8;
	r.y = 8;
	if (chan) {
		SDL_BlitSurface(chan,NULL,sf,&r);
		r.y += chan->h+8;
		SDL_FreeSurface(chan);
	}
	if (pic) {
		SDL_BlitSurface(pic,NULL,sf,&r);
		SDL_FreeSurface(pic);
	}

	// Ok, finalement on affiche les chaines (heure, titre, desc)
	int x = myx;
	int y = 8;
	printf("output x : %d\n",x);
	TTF_SetFontStyle(font,TTF_STYLE_BOLD);
	y += put_string(sf,font,x,y,heure,fg);
	y += put_string(sf,font,x,y,title,fg);
	y += 12;
	TTF_SetFontStyle(font,TTF_STYLE_NORMAL);
	y += put_string(sf,font,x,y,desc,fg);
	
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
}
