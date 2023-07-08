#include <fcntl.h>
#ifdef SDL1
#include <SDL/SDL.h>
#include <SDL/SDL_ttf.h>
#include <SDL/SDL_image.h>
#include <SDL/SDL_rotozoom.h>
#else
#include <SDL2/SDL.h>
#include <SDL2/SDL_ttf.h>
#include <SDL2/SDL_image.h>
#include <SDL2/SDL2_rotozoom.h>
#endif
#include "savesurf.h"
#include "lib.h"
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h> // unix domain socket
#include <sys/stat.h>
#include <unistd.h>
#include <signal.h>
#include <errno.h>

/* Serveur bmovl : apparemment si on laisse 2 processes se partager la fifo
 * bmovl, les donnÃ©es se mélangent ! En fait ils en parlent très vaguement
 * dans perlipc, on est sensé laisser un délai entre le moment où on ferme
 * une fifo et le moment où on la réouvre sous peine de voir les 2 flux se
 * mélanger.
 * Résultat : on va être obligé d'utiliser une socket pour communiquer avec
 * ce prog, ce genre de truc n'arrive pas avec les sockets */

static int fifo;
static char *fifo_str;
static int server,infox,infoy,listx,listy,listh,old_size;
static char bg_pic[FILENAME_MAX];
#ifdef SDL1
static SDL_Surface *pic;
#else
static SDL_Texture *pic;
#endif
static int must_clear_screen;
static SDL_Surface *sf;

static void clear_screen() {
    if (sdl_screen) {

#ifdef SDL1
	if (SDL_MUSTLOCK(sdl_screen))
	    SDL_LockSurface(sdl_screen);
	*bg_pic = 0;

	memset(sdl_screen->pixels,0,sdl_screen->w*sdl_screen->h*
		sdl_screen->format->BytesPerPixel);

	if (SDL_MUSTLOCK(sdl_screen))
	    SDL_UnlockSurface(sdl_screen);

	SDL_UpdateRect(sdl_screen,0,0,sdl_screen->w,sdl_screen->h);
#else
	SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
	SDL_RenderClear(renderer);
	SDL_RenderPresent(renderer);
#endif
    }
}

/* Les commandes de connexion/déconnexion au fifo mplayer doivent être passés
 * par signaux et pas par le fifo de commande parce que malheureusement un
 * mplayer peut quitter pendant qu'une commande est en cours, dans ce cas là
 * pour ne pas rester bloqué en lecture rien de mieux que le signal */
static void disconnect(int signal) {
    if (!fifo) return;
    close(fifo);
    must_clear_screen = 1; // pas d'appel direct, ça freeze des fois

    fifo = 0;
    unlink("video_size");
}

static void myalarm(int signal) {
    printf("alarm boucle 1s\n");
    alarm(1);
}

static void myconnect(int signal) {
    /* Finalement on fait totalement confiance au script freebox pour la
     * fiabilité de la pipe ici et on l'ouvre en blocante. Il y a un SIGPIPE
     * intercepté parce qu'une écriture dedans pendant un zapping est toujours
     * possible, c'est tout */
    /* C'est plus pratique qu'une ouverture non blocante qui nécessite des
     * pauses pendant l'écriture parce qu'on est pas toujours synchronisé avec
     * le process mplayer, et après on ne sait plus si on attend à cause d'une
     * déconnexion ou d'un timeout, nettement + simple comme ça */
    if (fifo)
	close(fifo);
    if (fifo_str) {
	alarm(1);
	fifo = open( fifo_str, O_WRONLY /* |O_NONBLOCK */ );
	alarm(0);
    } else
	fifo = 0;
    if (fifo <= 0) {
	printf("server: could not open fifo !\n");
	fifo = 0;
    }
    if (fifo > 0 && pic) {
#ifdef SDL1
	SDL_FreeSurface(pic);
#else
	SDL_DestroyTexture(pic);
#endif
	pic = NULL;
    }
}

static void myexit(int signal) {
    unlink("sock_bmovl");
    unlink("info.pid");
    unlink("desktop");
    exit(0);
}

static TTF_Font *open_font(int fsize) {
    TTF_Font *font = TTF_OpenFont("Vera.ttf",fsize);
    if (!font) font = TTF_OpenFont("/usr/share/fonts/truetype/ttf-bitstream-vera/Vera.ttf",12);
    return font;
}

static int image(int argc, char **argv);

static void clear_rect(SDL_Surface *sf,int x, int y, int *indents)
{
    SDL_Rect b;
    int bg = get_bg(sf);
    int *i = indents;
    while (*i) {
	if (y > *i) {
	    // printf("next: y %d > %d, set x to %d\n",y,*i,i[1]);
	    x = i[1];
	    i += 2;
	} else {
	    // printf("next h = %d - y %d - 1\n",*i,y);
	    b.x =x; b.y = y; b.w = sf->w-x-1; b.h = *i++-y;
	    // printf("bmovl: sf fillrect %d,%d,%d,%d\n",b.x, b.y,b.w,b.h);
	    // printf("next: clear %d %d %d %d\n",x,y,b.w,b.h);
	    SDL_FillRect(sf,&b,bg);
	    x = *i++;
	    y = i[-2];
	}
    }
    b.x =x; b.y = y; b.w = sf->w-x-1; b.h = sf->h-y-1;
    SDL_FillRect(sf,&b,bg);
    // printf("bmovl: sf fillrect %d,%d,%d,%d\n",b.x, b.y,b.w,b.h);
}

static void adjust_indent(int *x, int *y, int *indents)
{
    while (*indents && *y > *indents) {
	*x = indents[1];
	indents += 2;
    }
}

static int last_htext;

static SDL_Surface *extend_surface(SDL_Surface *s) {
    if (s->format->BitsPerPixel < 16) {
	SDL_Surface *surf = create_surface(s->w,s->h);
	SDL_BlitSurface(s,NULL,surf,NULL);
	SDL_FreeSurface(s);
	s = surf;
    }
    return s;
}

static int info(int fifo, int argc, char **argv)
{
	char *s = strrchr(argv[0],'/');
	if (s) argv[0] = s+1;

	/* La gestion du défilement du bandeau par page up/down doit se faire
	 * ici et pas dans le script perl parce que le script balance tout le
	 * bandeau sans savoir ce qui va pouvoir être affiché */

	static int width, height, fg, x0, y0, nb_prev;
#define MAX_PREV 30
	static char *desc, *next, *prev[MAX_PREV], *str;
	static TTF_Font *font;
	static SDL_Rect r;
	int x,y;
	static int indents[6], nb_indents;
	SDL_Surface *chan = NULL,*pic = NULL;
	int list_opened = 0;
	FILE *f = fopen("list_coords","r");
	if (f) {
	    list_opened = 1;
	    fclose(f);
	}

	static int margew,margeh;
	if (!strcmp(argv[0],"bmovl")) {
		char *channel,*picture;
		unsigned char buff[8192];
		if(argc<4) {
			printf("Usage: %s <bmovl fifo> <width> <height> [<max height>]\n", argv[0]);
			printf("width and height are w/h of MPlayer's screen!\n");
			return -1;
		}
		char *heure, *title;
		width = atoi(argv[2]);
		height = atoi(argv[3]);
		margew = width/36;
		margeh = height/36;
		width -= 2*margew;
		int deby = height/2;
		if (argc == 5) deby = atoi(argv[4]);
		int maxh = height - deby - 8;
		int fsize = height/35;
		if (fsize < 10) fsize = 10;
		char *old_desc = desc;
		if (desc) {
			free(desc);
			TTF_CloseFont(font);
			// printf("info: free surface sf\n");
			SDL_FreeSurface(sf);
		}
		font = open_font(fsize);
		if (!font) {
			printf("Could not load Vera.ttf, come back with it !\n");
			return -1;
		}
		myfgets(buff,8192,stdin);
		channel = strdup((char*)buff);
		myfgets(buff,8192,stdin);
		picture = strdup((char*)buff);
		if (*channel) chan = IMG_Load(channel);
		if (*picture) {
		    pic = IMG_Load(picture);
		    if (!pic) {
			printf("bmovl: can't load picture %s\n",picture);
		    }
		}
		myfgets(buff,8192,stdin);
		heure = strdup((char*)buff);
		myfgets(buff,8192,stdin);
		title = strdup((char*)buff);

		/* Redimensionnement éventuel */
		if (chan) {
		    double ratio = 1.0;
		    if (chan->w > width/2)
			ratio = width/2.0/(chan->w);
		    int h = maxh - fsize - 8*2;
		    if (pic) h = h/2 - 8;
		    if (chan->h > h) {
			double ratio2 = h*1.0/chan->h;
			if (ratio2 < ratio) ratio = ratio2;
		    }

		    if (ratio < 1.0) {
			strcpy((char*)buff,channel);
			char *p = strrchr((char*)buff,'.');
			sprintf(p,"-%g.png",chan->h*ratio);
			SDL_Surface *s = IMG_Load((char*)buff);
			if (!s) {
			    s = zoomSurface(chan,ratio,ratio,SMOOTHING_ON);
			    s = extend_surface(s);
			    png_save_surface((char*)buff,s);
			}
			SDL_FreeSurface(chan);
			chan = s;
		    }
		}
		if (pic) {
		    double ratio = 1.0;
		    if (pic->w > width/2)
			ratio = width/2.0/(pic->w);
		    int h = maxh - fsize - 8*2;
		    if (chan) h = h-4-chan->h;
		    if (pic->h > h) {
			double ratio2 = h*1.0/pic->h;
			if (ratio2 < ratio) ratio = ratio2;
		    }

		    if (ratio < 1.0) {
			strcpy((char*)buff,picture);
			char *p = strrchr((char*)buff,'.');
			sprintf(p,"-%g.png",pic->h*ratio);
			SDL_Surface *s = IMG_Load((char*)buff);
			if (!s) {
			    s = zoomSurface(pic,ratio,ratio,SMOOTHING_ON);
			    s = extend_surface(s);
			    png_save_surface((char*)buff,s);
			}
			SDL_FreeSurface(pic);
			pic = s;
		    }
		}

		int myx,w=0,h;
		if (chan) w = chan->w;
		if (w) myx = 3*4+2+w; else myx = 4;
		int wtext=0,htext=0;
		buff[0] = 0;
		int len = 0;
		// Carrier returns are included, a loop is mandatory then
		while (!feof(stdin) && len < 8191) {
			fgets((char*)&buff[len],8192-len,stdin); // we keep the eol here
			while (buff[len]) len++;
		}
		while (len > 0 && buff[len-1] < 32) buff[--len] = 0; // remove the last one though
		desc = strdup((char*)buff);

		TTF_SetFontStyle(font,TTF_STYLE_BOLD);
		get_size(font,heure,&w,&h,width-4*4); // 1st string : all the width (top)
		htext += h;
		wtext = w;
		int himg = h;
		int maxw = 0;
		if (pic) maxw = pic->w;
		if (chan && chan->w>maxw) maxw = chan->w;
		if (maxw) maxw = width-maxw-3*4;
		else
			maxw = width - 4*4;

		get_size(font,title,&w,&h,maxw);
		htext += h;
		if (w > wtext) wtext = w;
		TTF_SetFontStyle(font,TTF_STYLE_NORMAL);
		htext += 12;
		get_size(font,desc,&w,&h,maxw);
		htext += h;
		if (htext != last_htext) {
		    printf("clearing nb_prev htext %d != last_htext %d\n",htext,last_htext);
		    last_htext = htext;
		    nb_prev = 0;
		    next = NULL;
		    str = desc;
		} else {
		    if (old_desc) {
			next = (next - old_desc) + desc;
			str = (str - old_desc) + desc;
			for (int n=0; n<=nb_prev; n++)
			    prev[n] = (prev[n]- old_desc)+desc;
		    }
		}

		if (w > wtext) wtext = w;
		if (h > height-16) h = height-16;

		if (pic) himg += 8+pic->h;
		if (chan) himg += 8+chan->h;
		if (himg > htext) htext = himg;
		h = (htext + 16+12 < height-16 ? htext + 16+12 : height-16);
		if (h > maxh) h = maxh;

		x = margew;
		y = height - h - margeh;
		if (list_opened && y < listy+listh) {
		    int oldy = y;
		    y = listy+listh;
		    h -= y-oldy;
		}
		// printf("info: create sf %d,%d\n",width,h);
		sf = create_surface(width,h);
		fg = get_fg(sf);

		// Ok, finalement on affiche les chaines (heure, titre, desc)
		x = myx;
		y = 4;
		TTF_SetFontStyle(font,TTF_STYLE_BOLD);
		y += put_string(sf,font,4,y,heure,fg,NULL);
		r.x = 4;
		r.y = y;
		if (chan) {
			if (y + chan->h < sf->h) {
				SDL_BlitSurface(chan,NULL,sf,&r);
				r.y += chan->h+8;
			}
			SDL_FreeSurface(chan);
		}
		nb_indents = 0;
		if (pic) {
		    Uint16 pw = pic->w, ph = pic->h;
		    if (r.y + ph >= sf->h) {
			/* Le ratio de l'image est calculé d'après une approx, on peut se retrouver avec une hauteur trop grande ici
			 * donc on clippe plutôt que de ne rien afficher */
			ph = sf->h-r.y-1;
		    }
		    SDL_Rect pr = { 0, 0, pw, ph };
		    indents[nb_indents++] = r.y;
		    indents[nb_indents++] = r.x+pic->w+4;
		    SDL_BlitSurface(pic,&pr,sf,&r);
		    r.y += pic->h+8;
		    SDL_FreeSurface(pic);
		}
		indents[nb_indents++] = r.y;
		indents[nb_indents++] = 4;
		indents[nb_indents++] = 0;
		y += put_string(sf,font,x,y,title,fg,indents);
		y += 12;
		TTF_SetFontStyle(font,TTF_STYLE_NORMAL);
		x0 = x; y0 = y;

		// Clean up
		free(channel);
		free(picture);
		free(heure);
		free(title);
	} else if (!strcmp(argv[0],"next")) {
		if (!next) return 0;
		prev[nb_prev++] = str;
		if (nb_prev == MAX_PREV) nb_prev = MAX_PREV-1;
		str = next;
		clear_rect(sf,x0,y0,indents);
		x = x0; y = y0;
		adjust_indent(&x,&y,indents);
	} else if (!strcmp(argv[0],"prev")) {
		if (!nb_prev) return 0;
		str = prev[--nb_prev];
		clear_rect(sf,x0,y0,indents);
		x = x0; y = y0;
		x = x0; y = y0;
		adjust_indent(&x,&y,indents);
	} else {
		printf("info: unknown command %s\n",argv[0]);
		return 1;
	}

	y += put_string(sf,font,x,y,str,fg,indents);
	next = get_next_string();

	// Display
	x = margew;
	y = height - sf->h - margeh;
	if (list_opened && y < listy+listh)
	    y = listy+listh;
	f = fopen("info_coords","r");
	if (f) {
	    int oldx,oldy,oldw,oldh;
	    fscanf(f,"%d %d %d %d",&oldw,&oldh,&oldx,&oldy);
	    fclose(f);
	    if (list_opened && oldy < listy+listh) {
		oldy = listy+listh;
		oldh = y+sf->h-oldy;
	    }
	    if (oldh > sf->h) {
		char buff[2048];
		sprintf(buff,"CLEAR %d %d %d %d\n",oldw,oldh-sf->h,oldx,oldy);
		printf("info: %s",buff);
		send_command(fifo, buff);
	    }
	}
	/* printf("bmovl: blit %d %d %d %d avec width %d height %d\n",
			sf->w,sf->h,x,y,width,height); */
	blit(fifo, sf, x, y, -40, 0,1);
	infox = x; infoy = y; // pour mode_list
	send_command(fifo,"SHOW\n");
	// printf("bmovl: show done\n");
	f = fopen("info_coords","w");
	fprintf(f,"%d %d %d %d ",sf->w, sf->h,
			x, y);
	fclose(f);
	if (sdl_screen && *bg_pic)
	    image(1,NULL);

	return 0;
}

static int disp_list(SDL_Surface *sf, TTF_Font *font, int x, int y, char *list,
	SDL_Surface *chan,int col, int h)
{
    int dy;
    if (chan) {
	SDL_Rect r;
	r.x = x;
	dy = put_string(sf,font,x+chan->w+4,
		y+(chan->h > h ? (chan->h-h)/2 : 0),list,col,NULL);
	if (chan->h > dy) dy = chan->h;
	r.y = y + (dy-chan->h)/2;
	SDL_BlitSurface(chan,NULL,sf,&r);
    } else
	dy = put_string(sf,font,x,y,list,col,NULL);
    return dy;
}

static SDL_Surface *sf_list;

static int list(int fifo, int argc, char **argv)
{
    int width,height;

    char *source,*list[20],status[20];
    unsigned char buff[4096];
    int heights[20];
    char *names[20];
    SDL_Surface *chan[20];

    if(argc<4) {
	printf("Usage: %s <bmovl fifo> <width> <height> [<max height>]\n", argv[0]);
	printf("width and height are w/h of MPlayer's screen!\n");
	return -1;
    }

    // int maxh;
    width = atoi(argv[2]);
    height = atoi(argv[3]);
    int fsize = height/35;
    if (fsize < 10) fsize = 10;
    int fsel = !strcmp(argv[0],"fsel");
    int mode_list = !strcmp(argv[0],"mode_list");
    TTF_Font *font = open_font(fsize);
    if (!font) {
	printf( "bmovl: no font !!! Find Vera.ttf\n");
	return 1;
    }
    int num[20];
    int current = -1;
    myfgets(buff,4096,stdin);
    source = strdup((char*)buff);
    int nb=0,w,h;
    int margew = width/36, margeh=height/36;
    int longlist = !strcmp(argv[0],"longlist");
    int maxw = (fsel || longlist ? width :
	    width/2)-margew*2;
    int maxh = height - margeh*2 - fsize*3;
    int numw = 0;
    // Lecture des chaines, 20 maxi.
    int wlist,hlist;
    TTF_SetFontStyle(font,TTF_STYLE_BOLD);
    get_size(font,source,&wlist,&hlist,maxw);
    int htitle = hlist;
    TTF_SetFontStyle(font,TTF_STYLE_NORMAL);
    hlist += 4;
    // 1ère boucle : on stocke les infos...
    while (!feof(stdin) && nb<20) {
	names[nb] = NULL;
	if (!myfgets(buff,4096,stdin)) break;
	if (buff[0] == '*') current = nb;
	status[nb] = buff[0];
	char *end_nb = (char*)&buff[4];
	while (*end_nb >= '0' && *end_nb <= '9')
	    end_nb++;
	*end_nb++ = 0;
	if (!fsel && !mode_list) {
	    num[nb] = atoi((char*)&buff[1]);
	}
	chan[nb] = NULL;
	if (!strncmp(end_nb,"pic:",4)) {
	    // Extension : si le nom commence par pic:filename
	    // alors filename est une image (séparation par un espace)
	    char *s = strchr(end_nb+4,' ');
	    if (s && s!=end_nb+4) {
		*s = 0;
		names[nb] = strdup(end_nb+4);
		end_nb = s+1;
	    }
	}
	list[nb++] = strdup(end_nb);
    }
    // 2ème tour de boucle : on trouve les dimensions
    int nb2;
    if (!fsel && !mode_list) {
	sprintf((char*)buff,"%d",num[nb-1]);
	get_size(font,(char*)buff,&w,&h,maxw);
	numw = w;
	for (nb2=nb; nb2<20; nb2++) {
	    list[nb2] = NULL;
	    chan[nb2] = NULL;
	}
    } else
	numw = 0;
    get_size(font,">",&w,&h,maxw);
    int indicw = w;
    nb2 = 0;
    int larg = maxw-numw-indicw-4*2;
    while (nb2 < nb) {
	char *end_nb = list[nb2];
	if (!end_nb) break;
	int fleche = 0;
	int l = strlen(end_nb);
	if (end_nb[l-1] == '>') {
	    end_nb[l-1] = 0;
	    fleche = 1;
	}
	get_size(font,end_nb,&w,&h,larg);
	heights[nb2] = h; // Hauteur du texte, sans l'image
		// chan[nb] = IMG_Load(end_nb+4);
		//&& (chan[nb2]->h > h || chan[nb2]->w > larg/4)
	if (names[nb2] && !longlist ) {
	    // On essaye d'abord de charger une image pré-dimensionnée
	    char name[1024];
	    strcpy(name,names[nb2]);
	    char *s = strrchr(name,'.');
	    sprintf(s,"-%d.png",h);
	    chan[nb2] = IMG_Load(name);
	    if (!chan[nb2]) chan[nb2] = IMG_Load(names[nb2]);
	    if (chan[nb2] && (chan[nb2]->h > h || chan[nb2]->w > larg/4)) {
		double ratio = h*1.0/chan[nb2]->h;
		double ratio2 = larg/4*1.0/chan[nb2]->w;
		if (ratio2 < ratio)
		    ratio = ratio2;
		SDL_Surface *s = zoomSurface(chan[nb2],ratio,ratio,SMOOTHING_ON);
		SDL_FreeSurface(chan[nb2]);
		s = extend_surface(s);
		chan[nb2] = s;
		png_save_surface(name,s); // On sauve redimensionné !
	    }
	    free(names[nb2]);
	    names[nb2] = NULL;
	} else if (names[nb2] && longlist) {// longlist : youtube, load as-is
	    chan[nb2] = IMG_Load(names[nb2]);
	    free(names[nb2]);
	    names[nb2] = NULL;
	}
	if (chan[nb2]) {
	    get_size(font,end_nb,&w,&h,larg-chan[nb2]->w-4);
	    w += chan[nb2]->w+4;
	    if (chan[nb2]->h > h) h = chan[nb2]->h;
	    // heights[nb2] = h; // Hauteur du texte, sans l'image
	}
//	printf("prévision list: hlist:%d/%d %s from %d\n",hlist,maxh,end_nb,numw+4*2);
	if (w > wlist) wlist = w;
	hlist += h;
	if (fleche) end_nb[l-1] = '>';
	nb2++;
    }

    int n;
    int x=4,y=4;

    wlist += numw+4; // le numéro sur la gauche (3 chiffres + séparateur)
    int xright = x+wlist;
    wlist += indicw; // place pour le > à la fin
    if (wlist > maxw-4*2) {
	wlist = maxw-4*2;
	xright = x+wlist-indicw-4*2;
    }
    if (hlist + fsize > maxh)
	hlist = maxh - fsize;

again:
    if (sf_list && !mode_list)
	SDL_FreeSurface(sf_list);
    SDL_Surface *sf_mode;
    if (mode_list)
	sf_mode = create_surface(wlist+4*2,hlist+4*2);
    else
	sf_list = create_surface(wlist+4*2,hlist+4*2);

    TTF_SetFontStyle(font,TTF_STYLE_BOLD);
    y += put_string(mode_list ? sf_mode : sf_list,font,x,y,source,SDL_MapRGB(sf_list->format,0xff,0xff,0x80),
	    NULL);
    if (y > htitle+4) {
	/* Débordement du titre, doit refaire sf_list */
	y -= 4;
	hlist += y-htitle;
	htitle = y;
	x = y = 4;
	SDL_FreeSurface(mode_list ? sf_mode : sf_list);
	goto again;
    }
    x += numw+4; // aligné après les numéros

    // Détermine start
    int start;
    for  (start = 0; start < current; start++) {
	int y0 = y;
	for (n=start; n<nb && y0+fsize < maxh; n++) {
	    if (chan[n] && y0+chan[n]->h > maxh)
		break;
	    y0 += (chan[n] && chan[n]->h>heights[n] ? chan[n]->h : heights[n]);
	}
	if (n>current && y0+fsize < maxh) {
	    break;
	}
    }

    int fg = get_fg(sf_list);
    int red = SDL_MapRGB(sf_list->format,0xff,0x50,0x50);
    int cyan = SDL_MapRGB(sf_list->format, 0x50,0xff,0xff);
    TTF_SetFontStyle(font,TTF_STYLE_NORMAL);
    int bg = get_bg(sf_list),sely;
    for (n=start; n<nb && y+fsize < maxh; n++) {
	if (chan[n] && y+chan[n]->h > maxh)
	    break;
	int hidden = 0;
	int l = strlen(list[n]);
	if (list[n][l-1] == '>') {
	    list[n][l-1] = 0;
	    hidden = 1;
	}
	int y0 = y;
	sprintf((char*)buff,"%d",num[n]);
	if (current == n) {
	    SDL_Rect r;
	    r.x = 4; r.y = y; r.w = wlist; r.h = heights[n];
	    if (chan[n] && chan[n]->h > heights[n]) r.h = chan[n]->h;
	    SDL_FillRect(mode_list ? sf_mode : sf_list,&r,fg);
	    if (!fsel && !mode_list)
		put_string(sf_list,font,4,y,(char*)buff,bg,NULL); // Numéro
	    int dy;
	    dy = disp_list(mode_list ? sf_mode : sf_list,font,x,y,list[n],chan[n],bg,heights[n]);
	    sely = y+dy/2;
	    y += dy;
	} else {
	    if (status[n] == 'R') {
		fg = red;
	    } else if (status[n] == 'D') {
		fg = cyan;
	    }
	    if (!fsel && !mode_list)
		put_string(sf_list,font,4,y,(char*)buff,fg,NULL); // Numéro
	    y += disp_list(mode_list ? sf_mode : sf_list,font,x,y,list[n],chan[n],fg,heights[n]);
	    if (status[n] == 'R' || status[n] == 'D') fg = get_fg(sf_list);
	}
	if (hidden) {
	    direct_string(mode_list ? sf_mode : sf_list,font,xright,y0,">",(current == n ? bg : fg));
	}
//	printf("y:%d/%d %s from %d\n",y0,maxh,list[n],x);
    }
    int nb_elem = n-start;
//    printf("sortie de boucle nb %d y %d + fsize %d < maxh %d\n",nb,y,fsize,maxh);

    int oldx,oldy,oldw,oldh,oldsel;

    FILE *f = fopen("list_coords","r");
    if (f) {
	fscanf(f,"%d %d %d %d %d",&oldw,&oldh,&oldx,&oldy,&oldsel);
	fclose(f);
	if (!mode_list) {
	    if (oldh > sf_list->h) {
		char buff[2048];
		sprintf(buff,"CLEAR %d %d %d %d\n",oldw,oldh-sf_list->h,oldx,oldy+sf_list->h);
		send_command(fifo, buff);
	    }
	    if (oldw > sf_list->w) {
		char buff[2048];
		sprintf(buff,"CLEAR %d %d %d %d\n",oldw-sf_list->w,oldh,oldx+sf_list->w,oldy);
		send_command(fifo, buff);
	    }
	}
    }

    // Display
    if (mode_list) {
	x = oldx+oldw;
	y = oldsel-sf_mode->h/2;
	if (y+sf_mode->h > infoy)
	    y = infoy-sf_mode->h;
	if (y < 0) y = 0;
	f = fopen("mode_coords","w");
	fprintf(f,"%d %d %d %d \n",sf_mode->w, sf_mode->h,
		x, y);
	fclose(f);
    } else {
	x = margew;
	y = margeh;
	f = fopen("list_coords","w");
	fprintf(f,"%d %d %d %d %d\n",sf_list->w, sf_list->h,
		x, y,sely);
	fprintf(f,"%d\n",nb_elem);
	fclose(f);
    }
    if (sdl_screen/* && *bg_pic */) {
	// Dans ce cas là il peut rester un bout d'image en dessous à virer
	// et à droite
	int infoy = 0;
	f = fopen("info_coords","r");
	if (f) {
	    int oldx,oldy,oldw,oldh;
	    fscanf(f,"%d %d %d %d",&oldw,&oldh,&oldx,&oldy);
	    fclose(f);
	    h = oldy - y;
	    infoy = oldy;
	}
	int maxy = (infoy ? infoy : desktop_h);
	SDL_Rect r;
	r.x = (mode_list ? x : 0);
	r.y = y + sf_list->h;
	r.w = sf_list->w + (mode_list ? 0 : x);
	r.h = maxy - r.y;
	if (maxy > r.y) {
#ifdef SDL1
	    SDL_FillRect(sdl_screen,&r,0);
	    SDL_UpdateRects(sdl_screen,1,&r);
#else
	    SDL_RenderFillRect(renderer,&r); // color set when clearing the screen
#endif
	}
	if (oldy < y+sf_list->h) {
	    r.x = x+sf_list->w;
	    r.y = oldy;
	    r.w = oldw-r.x;
	    r.h = y+sf_list->h-oldy;
#ifdef SDL1
	    SDL_FillRect(sdl_screen,&r,0);
	    SDL_UpdateRects(sdl_screen,1,&r);
#else
	    SDL_RenderFillRect(renderer,&r); // color set when clearing the screen
#endif
	}
    }
    // Sans le clear à 1 ici, l'affichage du bandeau d'info par blit fait
    // apparaitre des déchets autour de la liste. Ca ne devrait pas arriver.
    // Pour l'instant le meilleur contournement c'est ça.
    if (mode_list) {
	blit(fifo, sf_list, listx, listy, -40, 0,0);
	blit(fifo, sf_mode, x, y, -40, 0,1);
	SDL_FreeSurface(sf_mode);
    } else {
	blit(fifo, sf_list, x, y, -40, 1,0);
	listx = x; listy = y; listh = sf_list->h;
    }

    // Clean up

    int info=0;
    send_command(fifo,"SHOW\n");
    free(source);
    for (n=0; n<nb; n++) {
	free(list[n]);
	if (chan[n]) SDL_FreeSurface(chan[n]);
    }
    TTF_CloseFont(font);
    if (sdl_screen && *bg_pic && info <= 0) {
	printf("actualisation image après list\n");
	image(1,NULL);
    }
    return 0;
}

int clear(int fifo, int argc, char **argv)
{
	char buff[2048];
	sprintf(buff,"CLEAR %s %s %s %s\n",argv[1],argv[2],argv[3],argv[4]);
	return send_command(fifo, buff) != strlen(buff);
}

int alpha(int fifo, int argc, char **argv)
{
    int mpv = access("video_size",R_OK | W_OK);
    if (!mpv && sf) {
	// cas mpv
	// c'est un peu différent de blit
	// Là on va vraiment multiplier les composantes rgb par alpha pour forcer l'alpha
	unsigned char trans = atoi(argv[5]) & 0xff;
	unsigned char *p = (unsigned char *)sf->pixels;
	int n = sf->h*sf->w;
	unsigned char *q = (unsigned char *)malloc(n*4);
	unsigned char *orig = q;
	while (n-- > 0) {
	    q[0] = p[0]*trans/255;
	    q[1] = p[1]*trans/255;
	    q[2] = p[2]*trans/255;
	    q[3] = trans;
	    q += 4;
	    p += 4;
	}
	FILE *f = fopen("surface","wb");
	fwrite(orig,1,sf->h*sf->pitch,f);
	fclose(f);
	free(orig);
	char buffer[256];
	sprintf(buffer,"{ \"command\": [\"overlay-add\", 1, %s, %s, \"surface\", 0, \"bgra\", %d, %d, %d ] }\n",argv[3],argv[4],
		sf->w, sf->h,sf->pitch);
	char *reply = send_cmd("mpvsocket",buffer);
	if (reply && strstr(reply,"error\":\"success")) {
	    unlink("surface");
	    return 0;
	}
	return 1;
    }
    char buff[2048];
    sprintf(buff,"ALPHA %s %s %s %s %s\n",argv[1],argv[2],argv[3],argv[4],
	    argv[5]);
    return send_command(fifo, buff) != strlen(buff);
}

static int nb_keys,*keys;
static char **command;

static void read_inputs() {
    FILE *f = fopen("input-mpv.conf","r");
    if (!f) {
	printf("can't read inputs from input-mpv.conf\n");
	return;
    }
    char buff[80];
    int nb_alloc = 0;
    while (!feof(f)) {
	fgets(buff,80,f);
	if (buff[0] == '#' || !buff[0])
	    continue;
	char *c = strchr(buff,' ');
	int n;
	if (!c) continue;
	*c = 0;
	if (nb_keys == nb_alloc) {
	    nb_alloc += 10;
	    keys = (int*)realloc(keys,sizeof(int)*nb_alloc);
	    command = (char**)realloc(command,sizeof(char*)*nb_alloc);
	}
	/* Ces 2 là (+ et -) doivent etre placées en 1er parce que c'est les
	 * seules dont les codes ascii ne sont pas interpretés directement */
	if (buff[0] == '-')
	    keys[nb_keys] = SDLK_KP_MINUS;
	else if (buff[0] == '+')
	    keys[nb_keys] = SDLK_KP_PLUS;
	else if (buff[0] == '*')
	    keys[nb_keys] = SDLK_KP_MULTIPLY;
	else if (buff[0] == '/')
	    keys[nb_keys] = SDLK_KP_DIVIDE;
	else if (buff[1] == 0)
	    keys[nb_keys] = buff[0]; // touche alphanumérique (1 caractère)
	else if (!strcasecmp(buff,"BS"))
	    keys[nb_keys] = SDLK_BACKSPACE;
	else if (!strcasecmp(buff,"UP"))
	    keys[nb_keys] = SDLK_UP;
	else if (!strcasecmp(buff,"DOWN"))
	    keys[nb_keys] = SDLK_DOWN;
	else if (!strcasecmp(buff,"LEFT"))
	    keys[nb_keys] = SDLK_LEFT;
	else if (!strcasecmp(buff,"RIGHT"))
	    keys[nb_keys] = SDLK_RIGHT;
	else if (!strcasecmp(buff,"TAB"))
	    keys[nb_keys] = SDLK_TAB;
	else if ((buff[0] == 'F' || buff[0] == 'f') &&
	       	(n = atoi(&buff[1])) > 0)
	    keys[nb_keys] = SDLK_F1+n-1;
	else if (!strcasecmp(buff,"HOME"))
	    keys[nb_keys] = SDLK_HOME;
	else if (!strcasecmp(buff,"END"))
	    keys[nb_keys] = SDLK_END;
	else if (!strcasecmp(buff,"ENTER"))
	    keys[nb_keys] = SDLK_RETURN;
	else if (!strcasecmp(buff,"PGUP"))
	    keys[nb_keys] = SDLK_PAGEUP;
	else if (!strcasecmp(buff,"PGDWN"))
	    keys[nb_keys] = SDLK_PAGEDOWN;
	else if (!strcasecmp(buff,"DEL"))
	    keys[nb_keys] = SDLK_DELETE;
	else if (!strcasecmp(buff,"INS"))
	    keys[nb_keys] = SDLK_INSERT;
	else if (!strcasecmp(buff,"ESC"))
	    keys[nb_keys] = SDLK_ESCAPE;
	else if (!strcasecmp(buff,"SPACE"))
	    keys[nb_keys] = SDLK_SPACE;
	else if (!strncasecmp(buff,"KP",2))
#ifdef SDL1
	    keys[nb_keys] = SDLK_KP0 + atoi(&buff[2]);
#else
	// les scancodes sont inversés pour le pavé numérique et non linéaires, par rangées
	// du coup il faut faire un case...
	switch(atoi(&buff[2])) {
	case 0: keys[nb_keys] = SDLK_KP_0; break;
	case 1: keys[nb_keys] = SDLK_KP_1; break;
	case 2: keys[nb_keys] = SDLK_KP_2; break;
	case 3: keys[nb_keys] = SDLK_KP_3; break;
	case 4: keys[nb_keys] = SDLK_KP_4; break;
	case 5: keys[nb_keys] = SDLK_KP_5; break;
	case 6: keys[nb_keys] = SDLK_KP_6; break;
	case 7: keys[nb_keys] = SDLK_KP_7; break;
	case 8: keys[nb_keys] = SDLK_KP_8; break;
	case 9: keys[nb_keys] = SDLK_KP_9; break;
	}
#endif
	else {
	    printf("touche inconnue %s commande %s\n",buff,c+1);
	    continue;
	}
	c++;
	while (*c == ' ' || *c == 9) c++; // passe les tabs et espaces
	command[nb_keys++] = strdup(c);
    }
    fclose(f);
}

static int numero(int fifo, int argc, char **argv) {
    if (argc != 2) {
	printf("numéro: mauvais nombre d'arguments\n");
	return(1);
    }
    int width,height;
    FILE *f = fopen("video_size","r");
    if (f) {
	fscanf(f,"%d\n",&width);
	fscanf(f,"%d\n",&height);
	fclose(f);
    } else {
	width = desktop_w;
	height = desktop_h;
    }
    int margew = width/36;
    int margeh = height/36;
    TTF_Font *font = open_font(height/35);
    int w = 0, h = 0;
    get_size(font,argv[1],&w,&h,width-32);
    SDL_Surface *sf = create_surface(w+16,h+16);
    int fg = get_fg(sf);
    put_string(sf,font,8,8,argv[1],fg,NULL);
    int x = width-margew-sf->w, y = margeh*2;
    blit(fifo, sf, x, y, -40, 0,2);
    f = fopen("list_coords","r");
    if (!f) f = fopen("info_coords","r");
    if (f)
	fclose(f);
    else
	// De fortes chances que tout soit caché si y a ni liste ni info !
	send_command(fifo,"SHOW\n");
    f = fopen("numero_coords","w");
    if (f) {
	fprintf(f,"%d %d %d %d\n",sf->w,sf->h,x,y);
	fclose(f);
    }
    SDL_FreeSurface(sf);
    return 0;
}

#ifndef SDL1
static void redraw_screen() {
    if (sf_list) {
	FILE *f = fopen("list_coords","r");
	if (f) {
	    fclose(f);
	    blit(fifo, sf_list, listx, listy, -40, 1,0);
	}
    }
    if (*bg_pic) {
	image(1,NULL);
    }
    if (sf) {
	FILE *f = fopen("info_coords","r");
	if (f) {
	    fclose(f);
	    blit(fifo, sf, infox, infoy, -40, 0,1);
	}
    }
    SDL_RenderPresent(renderer);
}
#endif

static void handle_event(SDL_Event *event) {
    if (!nb_keys) read_inputs();
#ifndef SDL1
    if (event->type == SDL_WINDOWEVENT && event->window.event == SDL_WINDOWEVENT_EXPOSED) {
	redraw_screen();
	return;
    }
#endif
    static int last_win;
    if (event->type != SDL_KEYDOWN) {
	if (event->type == SDL_WINDOWEVENT) {
	    last_win = event->window.timestamp;
	}
	return;
    }
    int input = event->key.keysym.sym;
    if (event->key.timestamp - last_win < 10) {
	printf("ignoring key because of win event\n");
	return;
    }
#ifdef SDL1
    int unicode = event->key.keysym.unicode;
    // printf("reçu touche %d (%c) unicode %d %c scan %x\n",input,input,unicode,unicode,event->key.keysym.scancode);
    if (unicode && (input == 0 ||
		((unicode >= 'a' && unicode <= 'z') || (unicode >= 'A' && unicode <= 'Z'))))
	input = event->key.keysym.unicode;
    int mod = event->key.keysym.mod;
#else
    int mod = SDL_GetModState();
#endif
    int n;
    if (mod & KMOD_SHIFT)
	n=nb_keys; // skip the loop
    else {
	for (n=0; n<nb_keys; n++) {
	    if (input == keys[n] && command[n][0] != '{') {
		// Evite les commandes style {dvdnav}
		printf("touche trouvée, commande %s\n",command[n]);

		if (!strncmp(command[n],"run",3)) {
		    int ret = system(&command[n][4]);
		    if (ret)
			printf("system %d returned %d\n",command[n][4],ret >> 8);
		} else {
		    if (fifo)
			send_cmd("fifo_cmd",command[n]);
		    else
			send_cmd("sock_list",command[n]);
		}
		break;
	    }
	}
    }
    if (n >= nb_keys) { // Pas trouvé
	char buf[80];
	if (input > 255) {
	    /* Pas la peine d'essayer de renvoyer un code > 255, il est
	     * perdu. Ca olibge à une réinterprétation tordue ici */
#ifdef SDL1
	    if (input >= SDLK_KP0 && input <= SDLK_KP9)
#else
	    if (input >= SDLK_KP_1 && input <= SDLK_KP_0)

#endif
	    {
#ifdef SDL1
		buf[0] = input-SDLK_KP0+'0';
#else
		if (input == SDLK_KP_0) buf[0] = '0';
		else buf[0] = input - SDLK_KP_1 + '1';
#endif
		buf[1] = 0;
		send_cmd("sock_list",buf);
		return;
	    } else if (input == SDLK_KP_ENTER) {
		FILE *f = fopen("list_coords","r");
		if (!f) f = fopen("numero_coords","r");
		if (f) {
		    fclose(f);
		    send_cmd("sock_list","zap1");
		} else
		    send_cmd("sock_info","zap1");
		return;
	    } else if (input >= SDLK_F1 && input <= SDLK_F12) {
		buf[0] = 'F';
		if (input < SDLK_F10) {
		    buf[1] = input-SDLK_F1+'1';
		    buf[2] = 0;
		} else {
		    buf[1] = '1';
		    buf[2] = input-SDLK_F10+'0';
		    buf[3] = 0;
		}
		send_cmd("sock_list",buf);
	    }
	    return;
	} else
	    if (input >= 'a' && input <= 'z' && (mod & KMOD_SHIFT)) {
	    // Particularité : shift + touche alphabétique pour naviguer par
	    // lettre dans les listes
	    input -= 32;
	}
	if (input >= 32 && input < 255) {
	    if (fifo) {
		sprintf(buf,"key_down_event %d",input);
		send_cmd("fifo_cmd",buf);
	    } else {
		sprintf(buf,"%c",input);
		send_cmd("sock_list",buf);
	    }
	}
    }
}

static void get_free_coords(Sint16 &x, Sint16 &y, Uint16 &w, Uint16 &h) {
    int infoy=0;
    x = desktop_w/36;
    y = desktop_h/36;
    FILE *f;
    f = fopen("list_coords","r");
    if (f) {
	int oldx,oldy,oldw,oldh,oldsel;
	fscanf(f,"%d %d %d %d %d",&oldw,&oldh,&oldx,&oldy,&oldsel);
	fclose(f);
	x = oldx + oldw;
    }
    f = fopen("mode_coords","r");
    if (f) {
	int oldx,oldy,oldw,oldh,oldsel;
	fscanf(f,"%d %d %d %d %d",&oldw,&oldh,&oldx,&oldy,&oldsel);
	fclose(f);
	y = oldy + oldh;
    }
    f = fopen("info_coords","r");
    if (f) {
	int oldx,oldy,oldw,oldh;
	fscanf(f,"%d %d %d %d",&oldw,&oldh,&oldx,&oldy);
	fclose(f);
	infoy = oldy;
    }
    int maxy = (infoy ? infoy : desktop_h-desktop_h/36);
    w = desktop_w - desktop_w/36 - x;
    h = maxy - y;
}

static int vignettes(int argc, char **argv) {
    if (!sdl_screen) {
	printf("vignettes appelé sans sdl_screen !\n");
	return(1);
    }
    FILE *f = fopen("vignettes","r");
    if (!f) {
	printf("vignettes: pas de fichier vignettes\n");
	return(1);
    }
    Sint16 x,y;
    Uint16 w,h;
    get_free_coords(x,y,w,h);
    int x0 = x,maxh=0;
    SDL_Rect r = {x,y,w,h};
#ifdef SDL1
    SDL_FillRect(sdl_screen,&r,0);
#else
    SDL_RenderFillRect(renderer,&r); // color set when clearing the screen
#endif
    while (!feof(f)) {
	char buf[1024];
	buf[0] = 0;
	myfgets((unsigned char*)buf,1024,f);
	buf[1023] = 0;
#ifdef SDL1
	SDL_Surface *pic = IMG_Load(buf);
	int picw = pic->w, pich = pic->h;
#else
	SDL_Texture *pic = IMG_LoadTexture(renderer,buf);
	int access,picw,pich;
	Uint32 format;
	SDL_QueryTexture(pic, &format, &access, &picw, &pich);
#endif
	if (!pic) {
	    printf("vignettes: couldn't load %s\n",buf);
	    continue;
	}
	if (x+picw > x0+w) {
	    x = x0;
	    y += maxh;
	    h -= maxh;
	    maxh = 0;
	}
	if (picw <= w && pich <= h) {
	    SDL_Rect dst;
	    dst.x = x; dst.y = y;
#ifdef SDL1
	    SDL_BlitSurface(pic,NULL,sdl_screen,&dst);
#else
	    SDL_RenderCopy(renderer,pic,NULL,&dst);
#endif
	    x += picw;
	    if (pich > maxh) maxh = pich;
	}
#ifdef SDL1
	SDL_FreeSurface(pic);
#else
	SDL_DestroyTexture(pic);
#endif
    }
    fclose(f);
#ifdef SDL1
    SDL_UpdateRects(sdl_screen,1,&r);
#else
    SDL_RenderPresent(renderer);
#endif
    return 0;
}

static int image(int argc, char **argv) {
    static int picw,pich;
    if (argc != 2 && argc != 1) {
	printf("image: argc = %d\n",argc);
	return(1);
    }
    if (!sdl_screen) {
	printf("image appelé sans sdl_screen !\n");
	return(1);
    }
    char *bmp;
    if (argc==1)
	bmp = bg_pic;
    else
	bmp = argv[1];
    int size = 0;
    if (bmp) {
	struct stat buf;
	stat(bmp,&buf);
	size = buf.st_size;
    }
    if (strcmp(bmp,bg_pic) || size != old_size) {
#ifdef SDL1
	SDL_Surface *pic2 = IMG_Load(bmp);
#else
	SDL_Texture *pic2 = IMG_LoadTexture(renderer,bmp);
#endif
	if (pic2) {
	    if (pic) {
#ifdef SDL1
		SDL_FreeSurface(pic);
#else
		SDL_DestroyTexture(pic);
#endif
	    }
	    pic = pic2;
#ifdef SDL1
	    picw = pic->w; pich = pic->h;
#else
	    int access;
	    Uint32 format;
	    SDL_QueryTexture(pic, &format, &access, &picw, &pich);
	    // printf("picw %d pich %d\n",picw,pich);
#endif
	    strcpy(bg_pic,bmp);
	    old_size = size;
	} else {
	    printf("can't open image %s\n",bmp);
	    size_t n,l = strlen(bmp);
	    for (n=0; n<l; n++)
		printf("%02x ",bmp[n]);
	    printf("\n");
	}
    }
    if (!pic) {
	return vignettes(0,NULL);
    }
    Sint16 x,y;
    Uint16 w,h;
    get_free_coords(x,y,w,h);
    int maxy = h+y;
    if (0) { // bmp == bg_pic && lastx == x && lasty == y && lastw == w && lasth == h){
	// Rien à mettre à jour (invalide quand appelé par un event EXPOSE
	return 0;
    }

    double ratio = w*1.0/picw;
    if (h*1.0/pich < ratio) ratio = h*1.0/pich;
    if (ratio > 4.0) ratio = 4.0;
    SDL_Rect r;
    r.x = 0; r.y = 0;
#ifdef SDL1
    SDL_Surface *s = zoomSurface(pic,ratio,ratio,SMOOTHING_ON);
    r.w = s->w; r.h = s->h;
    if (s->w > w) r.w = w;
    if (s->h > h) r.h = h;
#else
    r.w = picw; r.h = pich;
#endif
    if (x + picw*ratio < desktop_w) {
	// Il peut un rester un bout de l'ancienne image à droite
	SDL_Rect r;
	r.x = x+picw*ratio;
	r.w = desktop_w-r.x;
	r.y = 0;
	r.h = maxy;
#ifdef SDL1
	SDL_FillRect(sdl_screen,&r,0);
#else
	// printf("image: fillrect1 %d,%d,%d,%d\n",r.x,r.y,r.w,r.h);
	SDL_RenderFillRect(renderer,&r); // color set when clearing the screen
#endif
    }
    if (y + pich*ratio < maxy) {
	// Et en dessous ?
	SDL_Rect r;
	r.x = x;
	r.w = desktop_w-r.x;
	r.y = y+pich*ratio;
	r.h = maxy - r.y;
#ifdef SDL1
	SDL_FillRect(sdl_screen,&r,0);
#else
	// printf("image: fillrect2 %d,%d,%d,%d\n",r.x,r.y,r.w,r.h);
	SDL_RenderFillRect(renderer,&r); // color set when clearing the screen
#endif
    }
    SDL_Rect dst;
    dst.x = x; dst.y = y;
#ifndef SDL1
    dst.w = r.w*ratio; dst.h = r.h*ratio;
    // SDL_Texture *tex = SDL_CreateTextureFromSurface(renderer,s);
    int ret = SDL_RenderCopy(renderer,pic,&r,&dst);
    // printf("image: rendercopy %d,%d,%d,%d vers %d,%d,%d,%d\n",r.x,r.y,r.w,r.h,dst.x,dst.y,dst.w,dst.h);
    if (ret < 0) {
	printf("image: SDL_RenderCopy error: %s (%d)\n",SDL_GetError(),ret);
    }
    // SDL_DestroyTexture(tex);
    // RenderPresent obligatoire pour les cas d'effacement
    SDL_RenderPresent(renderer);
#else
    SDL_BlitSurface(s,&r,sdl_screen,&dst);
    SDL_UpdateRect(sdl_screen,0,0,0,0);
    SDL_FreeSurface(s);
#endif
    return(0);
}

int main(int argc, char **argv) {

	signal(SIGUSR1, &myconnect);
	signal(SIGUSR2, &disconnect);
	signal(SIGPIPE, &disconnect);
	signal(SIGTERM, &myexit);
	signal(SIGALRM, &myalarm);
	printf("img_init %d\n",IMG_Init(IMG_INIT_PNG | IMG_INIT_JPG | IMG_INIT_WEBP));
	last_htext = 0;
	FILE *f = fopen("info.pid","w");
	fprintf(f,"%d\n",getpid());
	fclose(f);
	if (argc != 2) {
		printf("pass fifo as unique argument\n");
	}
	fifo_str = argv[1];
	// myconnect(0);
	char buff[2048];
	char *myargv[10];
	server = 0;

	/* Préparation de la socket */
#define LISTEN_BACKLOG 50
	int sfd;
	struct sockaddr_un my_addr, peer_addr;
	socklen_t peer_addr_size;

	sfd = socket(AF_UNIX, SOCK_STREAM, 0);
	if (sfd == -1) {
	    printf("bmovl: socket error\n");
	    return(-1);
	}
	memset(&my_addr, 0, sizeof(struct sockaddr_un));
	my_addr.sun_family = AF_UNIX;
	strncpy(my_addr.sun_path, "sock_bmovl", sizeof(my_addr.sun_path) - 1);
	unlink("sock_bmovl");
	if (bind(sfd, (struct sockaddr *) &my_addr,
		    sizeof(struct sockaddr_un)) == -1) {
	    printf("bind error errno %d\n",errno);
	    return(-1);
	}
	if (listen(sfd, LISTEN_BACKLOG) == -1) {
	    printf("listen error %d\n",errno);
	    return(-1);
	}
	peer_addr_size = sizeof(struct sockaddr_un);
	/* On ouvre une fenêtre quoi qu'il arrive. Ca sert de filtre de
	 * commandes pour mplayer pour les cas où c'est un flux sans video */
	init_video();
	TTF_Init();

	while (1) {
	    int len = 0;
	    *buff = 0;
	    while (len <= 0) {
		fd_set set;
		FD_ZERO(&set);
		FD_SET(sfd,&set);
		struct timeval tv;
		tv.tv_sec = 0;
		tv.tv_usec = 100000; // 0.1s
		int ret = select(sfd+1,&set,NULL,NULL,&tv);
		if (must_clear_screen) {
		    clear_screen();
		    must_clear_screen = 0;
		}
		if (ret > 0) {
		    if (server) {
			printf("server collision on accept, should not happen\n");
			exit(1);
		    }
		    server = accept(sfd, (struct sockaddr *) &peer_addr,
			    &peer_addr_size);
		    if (server == -1) {
			printf("error accept %d\n",errno);
			return(-1);
		    }
		    stdin = fdopen(server,"r");
		    len = myfgets((unsigned char*)buff,2048,stdin); // commande
		} else
		    server = 0;
		if (sdl_screen) {
		    SDL_Event event;
		    while (SDL_PollEvent(&event))
			handle_event(&event);
		}
	    }
	    argc = 1;
	    char *s = buff;
	    myargv[0] = buff;
	    while ((s = strchr(s,' '))) {
		*s = 0; s++;
		while (*s == ' ') s++;
		if (*s)
		    myargv[argc++] = s;
	    }
	    char *cmd = myargv[0];
	    s = strrchr(cmd,'/');
	    if (s) cmd =s+1;
	    // On retente une cxion quand y en a plus, ça mange pas de pain
	    // if (!fifo) myconnect(1);
	    if (1) {
		// commandes connectÃ©es
		if (!strcmp(cmd,"bmovl") || !strcmp(cmd,"next") ||
			!strcmp(cmd,"prev")) {
		    info(fifo,argc,myargv);
		} else if (!strcmp(cmd,"list")) {
		    list(fifo,argc,myargv);
		} else if (!strcmp(cmd,"list-noinfo") || !strcmp(cmd,"fsel") ||
			!strcmp(cmd,"mode_list") || !strcmp(cmd,"longlist")) {
		    list(fifo,argc,myargv);
		} else if (!strcmp(cmd,"CLEAR"))
		    clear(fifo,argc,myargv);
		else if (!strcmp(cmd,"ALPHA"))
		    alpha(fifo,argc,myargv);
		else if (!strcmp(cmd,"image"))
		    image(argc,myargv);
		else if (!strcmp(cmd,"vignettes"))
		    vignettes(argc,myargv);
		else if (!strcmp(cmd,"numero"))
		    numero(fifo,argc,myargv);
		else if (!strcmp(cmd,"HIDE"))
		    send_command(fifo,"HIDE\n");

	    } else {
		printf("server: commande ignorÃ©e : %s\n",cmd);
	    }
	    close(server);
	    server = 0;
	}
	// never reach this point
	// TTF_Quit();
	return 0;
}
