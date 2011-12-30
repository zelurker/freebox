
#include <SDL/SDL.h>
#include <SDL/SDL_ttf.h>
#include <unistd.h>
#include <sys/time.h>
#include <sys/types.h>

#define DEBUG 0

int get_bg(SDL_Surface *sf) { return SDL_MapRGB(sf->format,0x20,0x20,0x70);}
int get_fg(SDL_Surface *sf) { return SDL_MapRGB(sf->format,0xff,0xff,0xff);}

SDL_Surface *create_surface(int w, int h)
{
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
	SDL_Surface *sf = SDL_CreateRGBSurface(SDL_SWSURFACE,w,
			h,32,rmask,gmask,bmask,amask);
	int bg = get_bg(sf);
	int fg = get_fg(sf);
	SDL_FillRect(sf,NULL,fg);
	SDL_Rect r; r.x = r.y = 1; r.w = sf->w - 2; r.h = sf->h-2;
	SDL_FillRect(sf,&r,bg);
	return sf;
}

static int write_select(int fifo, void *buff, int len)
{
	int ret = 0;
	while (len > 0) {
		int bout = write(fifo,buff,len);
		len -= bout;
		ret += bout;
		buff += bout;
		if (len)
			printf("write_select: bout = %d fifo %d\n",bout,fifo);
		if (bout < 0)
		    break; // fifo closed probably
	}

	return ret;
}

SDL_Surface *sdl_screen;
static int desktop_w,desktop_h,desktop_bpp;

static void get_video_info() {
  const SDL_VideoInfo *inf = SDL_GetVideoInfo();
  desktop_w = inf->current_w;
  desktop_h = inf->current_h;
  desktop_bpp = inf->vfmt->BitsPerPixel;
}

static void init_video() {
    if ( SDL_Init( SDL_INIT_VIDEO) < 0 ) {
	fprintf(stderr, "Couldn't initialize SDL: %s\n",SDL_GetError());
	exit(2);
    }
    get_video_info();
    sdl_screen = SDL_SetVideoMode(640,480, /* desktop_w,desktop_h, */
	    desktop_bpp,SDL_SWSURFACE| SDL_ANYFORMAT /* |SDL_FULLSCREEN */);
}

void
blit(int fifo, SDL_Surface *bmp, int xpos, int ypos, int alpha, int clear)
{
    if (!fifo) {
	if (!sdl_screen) {
	    init_video();
	}
	SDL_Rect r;
	r.x = xpos; r.y = ypos;
	if (xpos + bmp->w > sdl_screen->w)
	    r.x = sdl_screen->w - bmp->w;
	if (ypos + bmp->h > sdl_screen->h)
	    r.y = sdl_screen->h - bmp->h;
	if (bmp->w > sdl_screen->w || bmp->h > sdl_screen->h) {
	    printf("blit too big for the screen !\n");
	    return;
	}
	printf("blit to %d,%d size %d %d\n",xpos,ypos,bmp->w,bmp->h);
	SDL_BlitSurface(bmp,NULL,sdl_screen,&r);
	SDL_UpdateRect(sdl_screen,r.x,r.y,bmp->w,bmp->h);
    } else {
	char str[100];
	int  nbytes;
	unsigned char *bitmap = bmp->pixels;
	int width = bmp->w;
	int height = bmp->h;
	
	sprintf(str, "RGBA32 %d %d %d %d %d %d\n",
	        width, height, xpos, ypos, alpha, clear);
	
	if(DEBUG) printf("Sending %s", str);

	write_select(fifo, str, strlen(str));
	nbytes = write_select(fifo, bitmap, width*height*4);

	if(DEBUG) printf("Sent %d bytes of bitmap data...\n", nbytes);
    }
}

void send_command(int fifo,char *cmd) {
    if (fifo)
	write_select(fifo,cmd,strlen(cmd));
    else
	printf("commande ignor�e (fifo=0) : %s\n",cmd);
}

void get_size(TTF_Font *font, char *text, int *w, int *h, int maxw) {
	/* Version de TTF_SizeText qui s'adapte aux retours charriots */
	*w = 0; *h = 0;
	char *beg = text, *s,old;
	int pos = 0;
	int myw,myh;
	do {
		s = strchr(beg,'\n');
		if (s) *s = 0;

		char *white;
		do { // cut on whites
			white = NULL;
			do {
				TTF_SizeText(font,beg,&myw,&myh);
				if (myw > maxw) {
					if (myw/3 > maxw)
						pos = strlen(beg)/2;
					else
						pos = strlen(beg)-1;
					old = beg[pos];
					beg[pos] = 0;
					if (white)
						*white = ' ';
					white = strrchr(beg,' ');
					beg[pos] = old;
					if (white)
						*white = 0;
				}
			} while (myw > maxw && white);
			if (myw > *w) *w = myw;
			*h += myh;
			if (white) {
				*white = ' ';
				beg = white+1;
			}
		} while (white);

		if (s) {
			*s = '\n';
			beg = s+1;
		}
	} while (s);
}

static char *next;

char *get_next_string() { return next; }

int put_string(SDL_Surface *sf, TTF_Font *font, int x, int y,
		char *text, int color, int maxy)
{
	/* G�re les retours charriots dans la chaine, renvoie la hauteur totale */
	/* maxy is the maximum y value beside the pictures, after this the text
	 * goes back on the left */
	int maxw = sf->w-x-8;
	int h = 0;
	int maxh = sf->h-8;
	char *beg = text,*s;
	int fin = 0;
	next = NULL;
	do {
		s = strchr(beg,'\n');
		if (s) *s = 0;
		if (*beg) {

			char *white,old;
			int myw,myh,pos;;
			do { // cut on whites
				if (y > maxy && x > 18) {
					// We just got below the pictures, use the space then !
					x = 18;
					maxw = sf->w-x-8;
				}

				white = NULL;
				do {
					TTF_SizeText(font,beg,&myw,&myh);
					if (myw > maxw) {
						if (myw/3 > maxw)
							pos = strlen(beg)/2;
						else
							pos = strlen(beg)-1;
						old = beg[pos];
						beg[pos] = 0;
						if (white)
							*white = ' ';
						white = strrchr(beg,' ');
						beg[pos] = old;
						if (white)
							*white = 0;
					}
				} while (myw > maxw && white); 

				// we have a substring that can be displayed here...
				SDL_Rect dest;
				dest.x = x; dest.y = y;
				SDL_Color *col = (SDL_Color*)&color; // dirty hack !
				SDL_Surface *tf = TTF_RenderText_Solid(font,beg,*col);
				if (y + tf->h <= maxh)
					SDL_BlitSurface(tf,NULL,sf,&dest);
				else {
					fin = 1;
					next = beg;
				}
				h += tf->h;
				y += tf->h;
				SDL_FreeSurface(tf);

				if (white) {
					*white = ' ';
					beg = white+1;
				}
				if (fin) break;
			} while (white);

		} else {
			h += 12;
			y += 12;
		}
		if (s) {
			*s = '\n';
			beg = s+1;
		}
		if (fin) break;
	} while (s && *beg);
	return h;
}

int myfgets(char *buff, int size, FILE *f) {
	char *s = fgets(buff,size,f);
	if (!s) return 0;
	int len = strlen(buff);
	while (len > 0 && ((unsigned char)(buff[len-1])) < 32)
		buff[--len] = 0;
	return len;
}
