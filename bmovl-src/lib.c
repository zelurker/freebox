#ifdef SDL1
#include <SDL/SDL.h>
#include <SDL/SDL_ttf.h>
#else
#include <SDL2/SDL.h>
#include <SDL2/SDL_ttf.h>
#endif
#include <unistd.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h> // unix domain socket
#include <fcntl.h>
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
	int mpv = access("mpvsocket",R_OK | W_OK);
	/* Gros emmerdement : mplayer & mplayer2 prennent un format rgba32 uniquement
	 * et mpv bgra32 uniquement ! Du coup faut jongler entre les 2 pour l'instant.
	 * Je suppose qu'à terme on ne gardera que mpv mais pour l'instant... on jongle ! */
	if (mpv < 0) {
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
	} else {
	    // mpv version
#if SDL_BYTEORDER == SDL_BIG_ENDIAN
	    rmask = 0x0000ff00;
	    gmask = 0x00ff0000;
	    bmask = 0xff000000;
	    amask = 0x000000ff;
#else
	    rmask = 0x00ff0000;
	    gmask = 0x0000ff00;
	    bmask = 0x000000ff;
	    amask = 0xff000000;
#endif
	}
	SDL_Surface *sf = SDL_CreateRGBSurface(SDL_SWSURFACE,w,
			h,32,rmask,gmask,bmask,amask);
	int bg = get_bg(sf);
	int fg = get_fg(sf);
	SDL_FillRect(sf,NULL,fg);
	SDL_Rect r; r.x = r.y = 1; r.w = sf->w - 2; r.h = sf->h-2;
	SDL_FillRect(sf,&r,bg);
	char *lang = getenv("LANG");
	utf = strcasestr(lang,"UTF") != NULL;
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

int desktop_w,desktop_h,desktop_bpp;
#ifdef SDL1
SDL_Surface *sdl_screen;

static void get_video_info() {
  const SDL_VideoInfo *inf = SDL_GetVideoInfo();
  desktop_w = inf->current_w;
  desktop_h = inf->current_h;
  desktop_bpp = inf->vfmt->BitsPerPixel;
}
#else
SDL_Window *sdl_screen;
SDL_Renderer *renderer;
#endif

void init_video() {
    if ( SDL_Init( SDL_INIT_VIDEO) < 0 ) {
	fprintf(stderr, "Couldn't initialize SDL: %s\n",SDL_GetError());
	exit(2);
    }
#ifdef SDL1
    get_video_info();
    sdl_screen = SDL_SetVideoMode( desktop_w,desktop_h,
	    desktop_bpp,SDL_SWSURFACE| SDL_ANYFORMAT|SDL_NOFRAME /* |SDL_FULLSCREEN */ );
    SDL_EnableUNICODE(1);
    SDL_EnableKeyRepeat(SDL_DEFAULT_REPEAT_DELAY, SDL_DEFAULT_REPEAT_INTERVAL);
#else
    sdl_screen = SDL_CreateWindow("bmovl",
	    SDL_WINDOWPOS_UNDEFINED,
	    SDL_WINDOWPOS_UNDEFINED,
	    0, 0,
	    SDL_WINDOW_FULLSCREEN_DESKTOP);
    renderer = SDL_CreateRenderer(sdl_screen, -1, 0);
    SDL_Rect r;
    SDL_RenderGetViewport(renderer,&r);
    desktop_w = r.w;
    desktop_h = r.h;
#endif
    SDL_ShowCursor(SDL_DISABLE);
    FILE *f = fopen("desktop","w");
    if (f) {
	fprintf(f,"%d\n%d\n",desktop_w,desktop_h);
	fclose(f);
    }
}

char* send_cmd(char *fifo, char *cmd) {
    char *buf = strdup(cmd);
    static char reply[256];
    if (!strncmp(fifo,"sock",4) || !strncmp(fifo,"mpvsock",7)) {
	struct sockaddr_un address;
	int  socket_fd, nbytes;
	char buffer[256];

	socket_fd = socket(PF_UNIX, SOCK_STREAM, 0);
	if(socket_fd < 0)
	{
	    printf("bmovl: send_cmd socket() failed\n");
	    return NULL;
	}

	/* start with a clean address structure */
	memset(&address, 0, sizeof(struct sockaddr_un));

	address.sun_family = AF_UNIX;
	strncpy(address.sun_path, fifo, sizeof(address.sun_path) - 1);

	if(connect(socket_fd,
		    (struct sockaddr *) &address,
		    sizeof(struct sockaddr_un)) != 0)
	{
	    printf("bmovl: send_cmd connect() failed\n");
	    return NULL;
	}

	strncpy(buffer,cmd,256);
	buffer[255] = 0;
	if (strlen(buffer) < 255)
	    strcat(buffer,"\012");
	size_t dummy = write(socket_fd, buffer, strlen(buffer));
	dummy = read(socket_fd,reply,256);

	close(socket_fd);

	return reply;
    }
    if (buf[strlen(buf)-1] >= 32)
	strcat(buf,"\n");
    int file = open(fifo,O_WRONLY|O_NONBLOCK);
    if (file > 0) {
	size_t dummy = write(file,buf,strlen(buf));
	reply[0] = 0;
	close(file);
    } else {
	// printf("could not send command %s\n",buf);
	if (strcmp(fifo,"sock_list")) {
	    printf("trying to send to sock_list instead...\n");
	    send_cmd("sock_list",cmd);
	}
    }
    free(buf);
    return reply;
}

typedef struct {
    int x,y;
} sblit;

static sblit type_blit[3];

void
blit(int fifo, SDL_Surface *bmp, int xpos, int ypos, int alpha, int clear, int id)
{
    // id is an integer id for which part is drawn : 0 for list, 1 for info, 2 for numero
    // used only by mpv
    // En fait on teste video_size et pas mpvsocket parce qu'ici ce qui nous intéresse c'est une fenêtre de vidéo ouverte !
    int mpv = access("video_size",R_OK | W_OK);

    if (!fifo && mpv < 0) {
	if (!sdl_screen) {
	    init_video();
	}
	SDL_Rect r;
	r.x = xpos; r.y = ypos;
	if (xpos + bmp->w > desktop_w)
	    r.x = desktop_w - bmp->w;
	if (ypos + bmp->h > desktop_h)
	    r.y = desktop_h - bmp->h;
	if (bmp->w > desktop_w || bmp->h > desktop_h) {
	    printf("blit too big for the screen !\n");
	    return;
	}
#ifdef SDL1
	if (clear) memset(sdl_screen->pixels,0,desktop_w*desktop_h*
		sdl_screen->format->BytesPerPixel);
	SDL_BlitSurface(bmp,NULL,sdl_screen,&r);
	SDL_UpdateRect(sdl_screen,r.x,r.y,bmp->w,bmp->h);
#else
	if (clear)
	    SDL_RenderClear(renderer);
	SDL_Texture *tex = SDL_CreateTextureFromSurface(renderer,bmp);
	// il faut initialiser w & h ici
	r.w = bmp->w; r.h = bmp->h;
	SDL_RenderCopy(renderer,tex,NULL,&r);
	SDL_RenderPresent(renderer);
	SDL_DestroyTexture(tex);
#endif
    } else if (!mpv) {
	// Bon on va essayer d'appliquer l'alpha...
	// C'est un truc tordu, le composant alpha n'a pas le droit d'être > à l'une des composantes rgb
	unsigned char trans = alpha & 0xff;
	unsigned char *p = (unsigned char *)bmp->pixels;
	int n = bmp->h*bmp->w;
	while (n-- > 0) {
	    if (p[0] < trans && p[1] < trans && p[2] < trans)
		p[3] = trans;
	    else
		p[3] = 255;
	    p += 4;
	}

	/* There is a way to pass a pointer or a file handle directly, but for that to work it needs to be the same process, that is, using libmpv becomes mandatory.
	 * I'd like to try to do without libmpv for now to try to keep things simple, maybe later... */
	FILE *f = fopen("surface","wb");
	fwrite(bmp->pixels,1,bmp->h*bmp->pitch,f);
	fclose(f);
	char buffer[256];
	sprintf(buffer,"{ \"command\": [\"overlay-add\", %d, %d, %d, \"surface\", 0, \"bgra\", %d, %d, %d ] }\n",id,xpos,ypos,
		bmp->w, bmp->h,bmp->pitch);
	char *reply = send_cmd("mpvsocket",buffer);
	if (reply && strstr(reply,"error\":\"success"))
	    unlink("surface");
	type_blit[id].x = xpos;
	type_blit[id].y = ypos;
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
    int mpv = access("mpvsocket",R_OK | W_OK);
    if (!fifo) {
	if (!strncmp(cmd,"CLEAR",5)) {
	    SDL_Rect r;
#ifdef SDL1
	    sscanf(cmd+6,"%hd %hd %hd %hd",&r.w,&r.h,&r.x,&r.y);
	    if (mpv<0) {
		SDL_FillRect(sdl_screen,&r,0);
		SDL_UpdateRect(sdl_screen,r.x,r.y,r.w,r.h);
	    }
#else
	    sscanf(cmd+6,"%d %d %d %d",&r.w,&r.h,&r.x,&r.y);
	    if (mpv < 0) {
		SDL_SetRenderDrawColor(renderer,0,0,0,SDL_ALPHA_OPAQUE);
		SDL_RenderFillRect(renderer,&r);
		SDL_RenderPresent(renderer);
	    }
#endif
	    if (mpv == 0) {
		int found = 0;
		int n;
		for (n=0; n<3; n++) {
		    if (type_blit[n].x == r.x && type_blit[n].y == r.y) {
			found = 1;
			break;
		    }
		}
		if (found) {
		    char buffer[256];
		    sprintf(buffer,"{ \"command\": [\"overlay-remove\", %d ] }\n",n);
		    char *reply = send_cmd("mpvsocket",buffer);
		    type_blit[n].x = type_blit[n].y = -1;
		} else
		    printf("bmovl clear: type_blit not found\n");
	    }
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
    SDL_Color col;
    col.r = (color & sf->format->Rmask) >> sf->format->Rshift;
    col.g = (color & sf->format->Gmask) >> sf->format->Gshift;
    col.b = (color & sf->format->Bmask) >> sf->format->Bshift;
    SDL_Surface *tf;
    if (utf)
	tf = TTF_RenderUTF8_Solid(font,text,col);
    else
	tf = TTF_RenderText_Solid(font,text,col);
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
