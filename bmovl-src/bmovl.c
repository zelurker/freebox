#include <fcntl.h>
#include <SDL/SDL.h>
#include <SDL/SDL_ttf.h>
#include <SDL/SDL_image.h>
#include <SDL/SDL_rotozoom.h>
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
static int server,infoy,listy,listh;
static char bg_pic[1024];

static void clear_screen() {
    if (sdl_screen) {

	if (SDL_MUSTLOCK(sdl_screen))
	    SDL_LockSurface(sdl_screen);
	*bg_pic = 0;

	memset(sdl_screen->pixels,0,sdl_screen->w*sdl_screen->h*
		sdl_screen->format->BytesPerPixel);
	SDL_UpdateRect(sdl_screen,0,0,sdl_screen->w,sdl_screen->h);

	if (SDL_MUSTLOCK(sdl_screen))
	    SDL_UnlockSurface(sdl_screen);
    }
}

/* Les commandes de connexion/déconnexion au fifo mplayer doivent être passés
 * par signaux et pas par le fifo de commande parce que malheureusement un
 * mplayer peut quitter pendant qu'une commande est en cours, dans ce cas là
 * pour ne pas rester bloqué en lecture rien de mieux que le signal */
static void disconnect(int signal) {
    if (!fifo) return;
    close(fifo);
    clear_screen();

    fifo = 0;
    unlink("video_size");
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
    if (fifo_str)
	fifo = open( fifo_str, O_WRONLY /* |O_NONBLOCK */ );
    else
	fifo = 0;
    if (fifo <= 0) {
	printf("server: could not open fifo !\n");
	fifo = 0;
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

int image(int argc, char **argv);

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
	    // printf("next: clear %d %d %d %d\n",x,y,b.w,b.h);
	    SDL_FillRect(sf,&b,bg);
	    x = *i++;
	    y = i[-2];
	}
    }
    b.x =x; b.y = y; b.w = sf->w-x-1; b.h = sf->h-y-1;
    SDL_FillRect(sf,&b,bg);
}

static void adjust_indent(int *x, int *y, int *indents)
{
    while (*indents && *y > *indents) {
	*x = indents[1];
	indents += 2;
    }
}

static int info(int fifo, int argc, char **argv)
{
	char *s = strrchr(argv[0],'/');
	if (s) argv[0] = s+1;

	/* La gestion du défilement du bandeau par page up/down doit se faire
	 * ici et pas dans le script perl parce que le script balance tout le
	 * bandeau sans savoir ce qui va pouvoir être affiché */

	static int width, height, fg, x0, y0, nb_prev;
#define MAX_PREV 10
	static char *desc, *next, *prev[MAX_PREV], *str;
	static TTF_Font *font;
	static SDL_Surface *sf;
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
		char *channel,*picture,buff[8192];
		if(argc<4) {
			printf("Usage: %s <bmovl fifo> <width> <height> [<max height>]\n", argv[0]);
			printf("width and height are w/h of MPlayer's screen!\n");
			return -1;
		}
		char *heure, *title;
		nb_prev = 0;
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
		if (desc) {
			free(desc);
			TTF_CloseFont(font);
			SDL_FreeSurface(sf);
		}
		font = open_font(fsize);
		if (!font) {
			printf("Could not load Vera.ttf, come back with it !\n");
			return -1;
		}
		myfgets(buff,8192,stdin);
		channel = strdup(buff);
		myfgets(buff,8192,stdin);
		picture = strdup(buff);
		if (*channel) chan = IMG_Load(channel);
		if (*picture) pic = IMG_Load(picture);
		myfgets(buff,8192,stdin);
		heure = strdup(buff);
		myfgets(buff,8192,stdin);
		title = strdup(buff);

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
			strcpy(buff,channel);
			char *p = strrchr(buff,'.');
			sprintf(p,"-%g.png",chan->h*ratio);
			SDL_Surface *s = IMG_Load(buff);
			if (!s) {
			    s = zoomSurface(chan,ratio,ratio,SMOOTHING_ON);
			    png_save_surface(buff,s);
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
			strcpy(buff,picture);
			char *p = strrchr(buff,'.');
			sprintf(p,"-%g.png",pic->h*ratio);
			SDL_Surface *s = IMG_Load(buff);
			if (!s) {
			    s = zoomSurface(pic,ratio,ratio,SMOOTHING_ON);
			    png_save_surface(buff,s);
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
			fgets(&buff[len],8192-len,stdin); // we keep the eol here
			while (buff[len]) len++;
		}
		while (len > 0 && buff[len-1] < 32) buff[--len] = 0; // remove the last one though
		desc = strdup(buff);

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
		if (w > wtext) wtext = w;
		if (h > height-16) h = height-16;

		if (pic) himg += 8+pic->h;
		if (chan) himg += 8+chan->h;
		if (himg > htext) htext = himg;
		h = (htext + 16+12 < height-16 ? htext + 16+12 : height-16);
		if (h > maxh) h = maxh;

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
			if (r.y + pic->h < sf->h) {
			    indents[nb_indents++] = r.y;
			    indents[nb_indents++] = r.x+pic->w+4;
			    SDL_BlitSurface(pic,NULL,sf,&r);
			    r.y += pic->h+8;
			}
			SDL_FreeSurface(pic);
		}
		indents[nb_indents++] = r.y;
		indents[nb_indents++] = 4;
		indents[nb_indents++] = 0;
		y += put_string(sf,font,x,y,title,fg,indents);
		y += 12;
		TTF_SetFontStyle(font,TTF_STYLE_NORMAL);
		str = desc;
		next = NULL;
		nb_prev = 0;
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
	    if (oldh > sf->h) {
		char buff[2048];
		sprintf(buff,"CLEAR %d %d %d %d\n",oldw,oldh-sf->h,oldx,oldy);
		printf("info: %s",buff);
		send_command(fifo, buff);
	    }
	}
	/* printf("bmovl: blit %d %d %d %d avec width %d height %d\n",
			sf->w,sf->h,x,y,width,height); */
	blit(fifo, sf, x, y, -40, 0);
	infoy = y; // pour mode_list
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

static int list(int fifo, int argc, char **argv, int noinfo)
{
    int width,height;

    char *source,buff[4096],*list[20],status[20];
    int heights[20];
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
    source = strdup(buff);
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
    TTF_SetFontStyle(font,TTF_STYLE_NORMAL);
    hlist += 4;
    // 1ère boucle : on stocke les infos...
    while (!feof(stdin) && nb<20) {
	if (!myfgets(buff,4096,stdin)) break;
	if (buff[0] == '*') current = nb;
	status[nb] = buff[0];
	char *end_nb = &buff[4];
	while (*end_nb >= '0' && *end_nb <= '9')
	    end_nb++;
	*end_nb++ = 0;
	if (!fsel && !mode_list) {
	    num[nb] = atoi(&buff[1]);
	}
	if (!strncmp(end_nb,"pic:",4)) {
	    // Extension : si le nom commence par pic:filename
	    // alors filename est une image (séparation par un espace)
	    char *s = strchr(end_nb+4,' ');
	    if (s) {
		*s = 0;
		chan[nb] = IMG_Load(end_nb+4);
		end_nb = s+1;
	    }
	} else
		chan[nb] = NULL;
	list[nb++] = strdup(end_nb);
    }
    // 2ème tour de boucle : on trouve les dimensions
    int nb2;
    if (!fsel && !mode_list) {
	sprintf(buff,"%d",num[nb-1]);
	get_size(font,buff,&w,&h,maxw);
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
    while ((hlist+fsize < maxh || nb2 < current) && nb2 < nb) {
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
	if (chan[nb2] && !longlist && (chan[nb2]->h > h || chan[nb2]->w > larg/4)) {
	    double ratio = h*1.0/chan[nb2]->h;
	    double ratio2 = larg/4*1.0/chan[nb2]->w;
	    if (ratio2 < ratio)
		ratio = ratio2;
	    SDL_Surface *s = zoomSurface(chan[nb2],ratio,ratio,SMOOTHING_ON);
	    SDL_FreeSurface(chan[nb2]);
	    chan[nb2] = s;
	}
	if (chan[nb2]) {
	    get_size(font,end_nb,&w,&h,larg-chan[nb2]->w-4);
	    w += chan[nb2]->w+4;
	    if (chan[nb2]->h > h) h = chan[nb2]->h;
	    heights[nb2] = h; // Hauteur du texte, sans l'image
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
    /*	if (hlist > maxh)
	hlist = maxh; */

    SDL_Surface *sf = create_surface(wlist+4*2,hlist+4*2);

    TTF_SetFontStyle(font,TTF_STYLE_BOLD);
    y += put_string(sf,font,x,y,source,SDL_MapRGB(sf->format,0xff,0xff,0x80),
	    NULL);
    x += numw+4; // aligné après les numéros

    // Détermine start
    int start;
    for  (start = 0; start < nb; start++) {
	int y0 = y;
	for (n=start; n<nb && y0+fsize < maxh; n++) {
	    if (chan[n] && y0+chan[n]->h > maxh)
		break;
	    y0 += (chan[n] && chan[n]->h>heights[n] ? chan[n]->h : heights[n]);
	}
	if (n>current) {
	    break;
	}
    }

    int fg = get_fg(sf);
    int red = SDL_MapRGB(sf->format,0xff,0x50,0x50);
    int cyan = SDL_MapRGB(sf->format, 0x50,0xff,0xff);
    TTF_SetFontStyle(font,TTF_STYLE_NORMAL);
    int bg = get_bg(sf),sely;
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
	sprintf(buff,"%d",num[n]);
	if (current == n) {
	    SDL_Rect r;
	    r.x = 4; r.y = y; r.w = wlist; r.h = heights[n];
	    if (chan[n] && chan[n]->h > heights[n]) r.h = chan[n]->h;
	    SDL_FillRect(sf,&r,fg);
	    if (!fsel && !mode_list)
		put_string(sf,font,4,y,buff,bg,NULL); // Numéro
	    int dy;
	    dy = disp_list(sf,font,x,y,list[n],chan[n],bg,heights[n]);
	    sely = y+dy/2;
	    y += dy;
	} else {
	    char oldfg;
	    if (status[n] == 'R') {
		oldfg = fg;
		fg = red;
	    } else if (status[n] == 'D') {
		oldfg = fg;
		fg = cyan;
	    }
	    if (!fsel && !mode_list)
		put_string(sf,font,4,y,buff,fg,NULL); // Numéro
	    y += disp_list(sf,font,x,y,list[n],chan[n],fg,heights[n]);
	    if (status[n] == 'R' || status[n] == 'D') fg = oldfg;
	}
	if (hidden) {
	    direct_string(sf,font,xright,y0,">",(current == n ? bg : fg));
	}
//	printf("y:%d/%d %s from %d\n",y0,maxh,list[n],x);
    }
//    printf("sortie de boucle nb %d y %d + fsize %d < maxh %d\n",nb,y,fsize,maxh);

    int oldx,oldy,oldw,oldh,oldsel;

    FILE *f = fopen("list_coords","r");
    if (f) {
	fscanf(f,"%d %d %d %d %d",&oldw,&oldh,&oldx,&oldy,&oldsel);
	fclose(f);
	if (!mode_list) {
	    if (oldh > sf->h) {
		char buff[2048];
		sprintf(buff,"CLEAR %d %d %d %d\n",oldw,oldh-sf->h,oldx,oldy+sf->h);
		send_command(fifo, buff);
	    }
	    if (oldw > sf->w) {
		char buff[2048];
		sprintf(buff,"CLEAR %d %d %d %d\n",oldw-sf->w,oldh,oldx+sf->w,oldy);
		send_command(fifo, buff);
	    }
	}
    }
	
    // Display
    if (mode_list) {
	x = oldx+oldw;
	y = oldsel-sf->h/2;
	if (y+sf->h > infoy)
	    y = infoy-sf->h;
	if (y < 0) y = 0;
	f = fopen("mode_coords","w");
	fprintf(f,"%d %d %d %d \n",sf->w, sf->h,
		x, y);
	fclose(f);
    } else {
	x = margew;
	y = margeh;
	f = fopen("list_coords","w");
	fprintf(f,"%d %d %d %d %d\n",sf->w, sf->h,
		x, y,sely);
	fclose(f);
    }
    if (sdl_screen && *bg_pic) {
	// Dans ce cas là il peut rester un bout d'image en dessous à virer
	int infoy = 0;
	f = fopen("info_coords","r");
	if (f) {
	    int oldx,oldy,oldw,oldh;
	    fscanf(f,"%d %d %d %d",&oldw,&oldh,&oldx,&oldy);
	    fclose(f);
	    h = oldy - y;
	    infoy = oldy;
	}
	int maxy = (infoy ? infoy : sdl_screen->h);
	SDL_Rect r;
	r.x = (mode_list ? x : 0);
	r.y = y + sf->h;
	r.w = sf->w + (mode_list ? 0 : x);
	r.h = maxy - r.y;
	if (maxy > r.y) {
	    SDL_FillRect(sdl_screen,&r,0);
	    SDL_UpdateRects(sdl_screen,1,&r);
	} 
    }
    // Sans le clear à 1 ici, l'affichage du bandeau d'info par blit fait
    // apparaitre des déchets autour de la liste. Ca ne devrait pas arriver.
    // Pour l'instant le meilleur contournement c'est ça.
    blit(fifo, sf, x, y, -40, (noinfo ? 0 : 1));
    listy = y; listh = sf->h;

    // Clean up

    int info=0;
    if (current > -1 && !noinfo) {
	int tries = 0;
	while (tries++ < 4 && info <= 0) {
	    info = open("fifo_info",O_WRONLY|O_NONBLOCK);
	    if (info <= 0) {
		struct timeval tv;
		tv.tv_sec = 0;
		tv.tv_usec = 100000;
		select(0,NULL, NULL, NULL, &tv);
	    }
	}

	if (info > 0) {
	    sprintf(buff,"prog:%d %s\n",y+sf->h,list[current]);
	    write(info,buff,strlen(buff));
	    close(info);
	    if (tries > 1) printf("bmovl: %d tries for fifo_info\n",tries);
	} else
	    printf("on abandonne fifo_info !\n");
    } else
	send_command(fifo,"SHOW\n");
    free(source);
    SDL_FreeSurface(sf);
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
	char buff[2048];
	sprintf(buff,"ALPHA %s %s %s %s %s\n",argv[1],argv[2],argv[3],argv[4],
			argv[5]);
	return send_command(fifo, buff) != strlen(buff);
}

static int nb_keys,*keys;
static char **command;

static void read_inputs() {
    FILE *f = fopen("input.conf","r");
    if (!f) {
	printf("can't read inputs from input.conf\n");
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
	    keys = realloc(keys,sizeof(int)*nb_alloc);
	    command = realloc(command,sizeof(char*)*nb_alloc);
	}
	/* Ces 2 là (+ et -) doivent etre placées en 1er parce que c'est les
	 * seules dont les codes ascii ne sont pas interpretés directement */
	if (buff[0] == '-')
	    keys[nb_keys] = SDLK_KP_MINUS;
	else if (buff[0] == '+')
	    keys[nb_keys] = SDLK_KP_PLUS;
	else if (buff[1] == 0)
	    keys[nb_keys] = buff[0]; // touche alphanumérique (1 caractère)
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
	    keys[nb_keys] = SDLK_KP0 + atoi(&buff[2]);
	else {
	    printf("touche inconnue %s commande %s\n",buff,c+1);
	    continue;
	}
	command[nb_keys++] = strdup(c+1);
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
	width = sdl_screen->w;
	height = sdl_screen->h;
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
    blit(fifo, sf, x, y, -40, 0);
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

static void send_cmd(char *fifo, char *cmd) {
    char *buf = strdup(cmd);
    if (buf[strlen(buf)-1] >= 32) 
	strcat(buf,"\n");
    int file = open(fifo,O_WRONLY|O_NONBLOCK);
    if (file > 0) {
	write(file,buf,strlen(buf));
	close(file);
    } else
	printf("could not send command %s\n",buf);
    free(buf);
}

static void handle_event(SDL_Event *event) {
    if (!nb_keys) read_inputs();
    if (event->type != SDL_KEYDOWN) return;
    int input = event->key.keysym.sym;
    int mod = event->key.keysym.mod;
    printf("reçu touche %d (%c)\n",input,input);
    int n;
    if (mod & KMOD_SHIFT)
	n=nb_keys; // skip the loop
    else {
	for (n=0; n<nb_keys; n++) {
	    if (input == keys[n]) {
		printf("touche trouvée, commande %s\n",command[n]);
		if (!strncmp(command[n],"run",3))
		    system(&command[n][4]);
		else {
		    send_cmd("fifo_cmd",command[n]);
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
	    if (input >= SDLK_KP0 && input <= SDLK_KP9) {
		buf[0] = input-SDLK_KP0+'0';
		buf[1] = 0;
		send_cmd("fifo_list",buf);
		return;
	    } else if (input == SDLK_KP_ENTER || input == SDLK_RETURN) {
		FILE *f = fopen("list_coords","r");
		if (!f) f = fopen("numero_coords","r");
		if (f) {
		    fclose(f);
		    send_cmd("fifo_list","zap1");
		} else
		    send_cmd("fifo_info","zap1");
		return;
	    }
	} else if (input >= 'a' && input <= 'z' && (mod & KMOD_SHIFT)) {
	    // Particularité : shift + touche alphabétique pour naviguer par
	    // lettre dans les listes
	    input -= 32;
	}
	sprintf(buf,"key_down_event %d",input);
	send_cmd("fifo_cmd",buf);
    }
}

int image(int argc, char **argv) {
    printf("start image %d\n",argc);
    static int lastx,lasty,lastw,lasth;
    if (argc != 6 && argc != 1) {
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
    SDL_Surface *pic = IMG_Load(bmp);
    if (!pic) {
	printf("image: peut pas charger %s\n",bmp);
	return(1);
    }
    if (bmp != bg_pic)
	strcpy(bg_pic,bmp);
    int x,y,w,h;
    int infoy=0;
    if (argc == 1) {
	x = sdl_screen->w/36;
	y = sdl_screen->h/36;
	w = sdl_screen->w - x;
	h = sdl_screen->h - y;
    } else {
	x = atoi(argv[2]);
	y = atoi(argv[3]);
	w = atoi(argv[4]);
	h = atoi(argv[5]);
    }
    FILE *f = fopen("mode_coords","r");
    if (!f) f = fopen("list_coords","r");
    if (f) {
	int oldx,oldy,oldw,oldh,oldsel;
	fscanf(f,"%d %d %d %d %d",&oldw,&oldh,&oldx,&oldy,&oldsel);
	fclose(f);
	x = oldx + oldw;
	// y = oldy;
    }
    f = fopen("info_coords","r");
    if (f) {
	int oldx,oldy,oldw,oldh;
	fscanf(f,"%d %d %d %d",&oldw,&oldh,&oldx,&oldy);
	fclose(f);
	infoy = oldy;
	printf("image: maxy taken from info_coords %d\n",infoy);
    }
    int maxy = (infoy ? infoy : sdl_screen->h-sdl_screen->h/36);
    w = sdl_screen->w - sdl_screen->w/36 - x;
    h = maxy - y;
    if (bmp == bg_pic && lastx == x && lasty == y && lastw == w && lasth == h){
	// Rien à mettre à jour
	SDL_FreeSurface(pic);
	return 0;
    } else {
	lastx = x;
	lasty = y;
	lastw = w;
	lasth = h;
    }

    printf("image: %d,%d\n",w,h);
    double ratio = w*1.0/pic->w;
    if (h*1.0/pic->h < ratio) ratio = h*1.0/pic->h;
    if (ratio > 4.0) ratio = 4.0;
    SDL_Surface *s = zoomSurface(pic,ratio,ratio,SMOOTHING_ON);
    SDL_FreeSurface(pic);
    pic = s;
    SDL_Rect r;
    r.x = 0; r.y = 0; r.w = pic->w; r.h = pic->h;
    if (pic->w > w) r.w = w;
    if (pic->h > h) r.h = h;
    if (x + pic->w < sdl_screen->w) {
	// Il peut un rester un bout de l'ancienne image à droite
	SDL_Rect r;
	r.x = x+pic->w;
	r.w = sdl_screen->w-r.x;
	r.y = 0;
	r.h = maxy;
	SDL_FillRect(sdl_screen,&r,0);
	printf("on vire le bout à droite : %d,%d,%d,%d\n",r.x,r.y,r.w,r.h);
    } else {
	printf("rien à virer à droite : %d + %d >= %d\n",x,w,sdl_screen->w);
    }
    if (y + pic->h < maxy) {
	// Et en dessous ?
	SDL_Rect r;
	r.x = x;
	r.w = sdl_screen->w-r.x;
	r.y = y+pic->h;
	r.h = maxy - r.y;
	SDL_FillRect(sdl_screen,&r,0);
    }
    SDL_Rect dst;
    dst.x = x; dst.y = y;
    SDL_BlitSurface(pic,&r,sdl_screen,&dst);
    printf("image %d,%d,%d,%d\n",x,y,pic->w,pic->h);
    SDL_UpdateRect(sdl_screen,0,0,0,0);
    SDL_FreeSurface(pic);
    return(0);
}

int main(int argc, char **argv) {

	signal(SIGUSR1, &myconnect);
	signal(SIGUSR2, &disconnect);
	signal(SIGPIPE, &disconnect);
	signal(SIGTERM, &myexit);
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
		    len = myfgets(buff,2048,stdin); // commande
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
	    int ret;
	    // On retente une cxion quand y en a plus, ça mange pas de pain
	    // if (!fifo) myconnect(1);
	    if (1) {
		// commandes connectÃ©es
		if (!strcmp(cmd,"bmovl") || !strcmp(cmd,"next") ||
			!strcmp(cmd,"prev")) {
		    ret = info(fifo,argc,myargv);
		} else if (!strcmp(cmd,"list")) {
		    ret = list(fifo,argc,myargv,0);
		} else if (!strcmp(cmd,"list-noinfo") || !strcmp(cmd,"fsel") ||
			!strcmp(cmd,"mode_list") || !strcmp(cmd,"longlist")) {
		    ret = list(fifo,argc,myargv,1);
		} else if (!strcmp(cmd,"CLEAR"))
		    ret = clear(fifo,argc,myargv);
		else if (!strcmp(cmd,"ALPHA"))
		    ret = alpha(fifo,argc,myargv);
		else if (!strcmp(cmd,"image"))
		    ret = image(argc,myargv);
		else if (!strcmp(cmd,"numero"))
		    ret = numero(fifo,argc,myargv);
		else if (!strcmp(cmd,"HIDE"))
		    send_command(fifo,"HIDE\n");

		if (ret) {
		    printf("bmovl: command returned %d\n",ret);
		    /* disconnect(0);
		    myconnect(0); */
		}
	    } else {
		printf("server: commande ignorÃ©e : %s\n",cmd);
	    }
	    close(server);
	    server = 0;
	}
	// never reach this point
	// TTF_Quit();
}
