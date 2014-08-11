
#include <SDL/SDL.h>
#include <SDL/SDL_ttf.h>
#include <unistd.h>
#include <sys/time.h>
#include <sys/types.h>
#include "lib.h"

#define DEBUG 0

int get_bg(SDL_Surface *sf) { return SDL_MapRGB(sf->format,0x20,0x20,0x70);}
int get_fg(SDL_Surface *sf) { return SDL_MapRGB(sf->format,0xff,0xff,0xff);}
static int utf;

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
	char *lang = getenv("LANG");
	utf = strstr(lang,"UTF") != NULL;
	return sf;
}

static int write_select(int fifo, void *buff, int len)
{
    if (!fifo) return 0;
    int ret = 0;
    int tries = 3;
    while (len > 0) {
	int bout = write(fifo,buff,len);
	if (bout > 0) {
	    len -= bout;
	    ret += bout;
	    buff += bout;
	}
	if (bout < 0) {
	    /* Ca n'arrive qu'en ouverture non blocante, ce qui n'est plus
	     * le cas maintenant */
	    if (tries--) {
		struct timeval tv;
		tv.tv_sec = 0;
		tv.tv_usec = 100000;
		select(0,NULL,NULL,NULL,&tv);
	    } else {
		printf("write_select: toujours bloqué après 3 tentatives\n");
		break;
	    }
	}
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

void init_video() {
    if ( SDL_Init( SDL_INIT_VIDEO) < 0 ) {
	fprintf(stderr, "Couldn't initialize SDL: %s\n",SDL_GetError());
	exit(2);
    }
    get_video_info();
    sdl_screen = SDL_SetVideoMode( desktop_w,desktop_h,
	    desktop_bpp,SDL_SWSURFACE| SDL_ANYFORMAT /* |SDL_FULLSCREEN */ );
    SDL_ShowCursor(SDL_DISABLE);
    FILE *f = fopen("desktop","w");
    if (f) {
	fprintf(f,"%d\n%d\n",desktop_w,desktop_h);
	fclose(f);
    }
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
	if (clear) memset(sdl_screen->pixels,0,sdl_screen->w*sdl_screen->h*
		sdl_screen->format->BytesPerPixel);
	SDL_BlitSurface(bmp,NULL,sdl_screen,&r);
	SDL_UpdateRect(sdl_screen,r.x,r.y,bmp->w,bmp->h);
    } else {
	char str[100];
	int  nbytes;
	unsigned char *bitmap = (unsigned char *)bmp->pixels;
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

int send_command(int fifo,char *cmd) {
    if (!fifo) {
	if (!strncmp(cmd,"CLEAR",5)) {
	    SDL_Rect r;
	    sscanf(cmd+6,"%hd %hd %hd %hd",&r.w,&r.h,&r.x,&r.y);
	    SDL_FillRect(sdl_screen,&r,0);
	    SDL_UpdateRect(sdl_screen,r.x,r.y,r.w,r.h);
	}
	return strlen(cmd);
    }
    return write_select(fifo,cmd,strlen(cmd));
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

int direct_string(SDL_Surface *sf, TTF_Font *font, int x, int y,
	char *text, int color)
{
    // Retourne la hauteur de la chaine affichée ou 0
    SDL_Rect dest;
    int maxh = sf->h-8;
    dest.x = x; dest.y = y;
    SDL_Color *col = (SDL_Color*)&color; // dirty hack !
    SDL_Surface *tf;
    if (utf)
	tf = TTF_RenderUTF8_Solid(font,text,*col);
    else
	tf = TTF_RenderText_Solid(font,text,*col);
    if (!tf) return 0;
    int ret = 0;
    if (y + tf->h <= maxh) {
	SDL_BlitSurface(tf,NULL,sf,&dest);
	ret = tf->h;
    }
    SDL_FreeSurface(tf);
    return ret;
}

int put_string(SDL_Surface *sf, TTF_Font *font, int x, int y,
		char *text, int color, int *indents)
{
    /* Gère les retours charriots dans la chaine, renvoie la hauteur totale */
    int maxw = sf->w-x-4;
    int h = 0;
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
		TTF_SizeText(font,beg,&myw,&myh);
		/* Le test est vraiment tordu, je ne pensais pas que ça serait
		 * à ce point là.
		 * Le problème vient de ce qui se passe quand du texte se
		 * retrouve à cheval sur une indentation.
		 * Si la prochaine indentation décale à gauche, alors il faut
		 * attendre que tout le texte soit dans l'indentation pour
		 * changer.
		 * Si elle décale à droite alors dès que la base du texte
		 * déborde il faut changer. */
		if (indents && *indents &&
			((y+myh-1 >= *indents && indents[1] > x) ||
			 (y >= *indents && indents[1] < x))) {
		    // printf("put_string: y %d > indent %d, x = %d\n",y,*indents,indents[1]);
		    // We just got below the pictures, use the space then !
		    x = indents[1];
		    indents += 2;
		    maxw = sf->w-x-4;
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
		int ht = direct_string(sf,font,x,y,beg,color);
		if (!ht) {
		    fin = 1;
		    next = beg;
		}
		h += ht;
		y += ht;

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

int myfgets(unsigned char *buff, int size, FILE *f) {
	char *s = fgets((char*)buff,size,f);
	if (!s) return 0;
	int len = strlen((char*)buff);
	while (len > 0 && ((unsigned char)(buff[len-1])) < 32)
		buff[--len] = 0;
	return len;
}
