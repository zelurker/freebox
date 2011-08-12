/* Small program to test the features of vf_bmovl */

#include <fcntl.h>
#include <SDL/SDL.h>
#include <SDL/SDL_ttf.h>
#include <SDL/SDL_image.h>
#include "lib.h"
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>

/* Serveur bmovl : apparemment si on laisse 2 processes se partager la fifo
 * bmovl, les données se mélangent ! Normalement ça ne devrait pas arriver,
 * une fifo n'est pas sensée accepter 2 opens en même temps, mais là si.
 * Donc seule solution : utiliser un serveur qui est le seul à avoir le droit
 * d'utiliser cette fifo.
 * Il reçoit la ligne de commande d'abord, par la fifo suivie d'un retour
 * charriot, ensuite stdin et redirigé sur la fifo et le tout transmis à une
 * fonction dédiée en fonction de la ligne de commande, puis on boucle. */

static int info(int fifo, int argc, char **argv)
{
	if(argc<4) {
		printf("Usage: %s <bmovl fifo> <width> <height> [<max height>]\n", argv[0]);
		printf("width and height are w/h of MPlayer's screen!\n");
		return -1;
	}

	int maxh;
	int width = atoi(argv[2]);
	int height = atoi(argv[3]);
	int deby = 0;
	if (argc == 5) deby = atoi(argv[4]);
	maxh = height - deby - 8;
	int fsize = height/35;
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
	if (chan && (chan->w >= width/2 || chan->h+8+(pic ? pic->h : 0) > maxh)) {
		/* Give priority to picture, remove channel logo 1st if not enough
		 * space */
		SDL_FreeSurface(chan);
		chan = NULL;
	}
	if (pic && (pic->w >= width/2 || pic->h+8+(chan ? chan->h+8 : 0)>maxh)) {
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
    while (len > 0 && buff[len-1] < 32) buff[--len] = 0; // remove the last one though
    desc = strdup(buff);
	while (!feof(stdin)) fgets(buff,2048,stdin); // empty the pipe

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

    if (pic) himg += 8+pic->h;
    if (chan) himg += 8+chan->h;
    if (himg > htext) htext = himg;
    h = (htext + 16+12 < height-16 ? htext + 16+12 : height-16);
    if (h > maxh) h = maxh;

    SDL_Surface *sf = create_surface(width,h);
	int fg = get_fg(sf);

	// Ok, finalement on affiche les chaines (heure, titre, desc)
	int x = myx;
	int y = 8;
	TTF_SetFontStyle(font,TTF_STYLE_BOLD);
	y += put_string(sf,font,18,y,heure,fg,0);
	SDL_Rect r;
	r.x = 18;
	r.y = y;
	if (chan) {
		if (y + chan->h < sf->h) {
			SDL_BlitSurface(chan,NULL,sf,&r);
			r.y += chan->h+8;
		}
		SDL_FreeSurface(chan);
	}
	if (pic) {
		if (r.y + pic->h < sf->h) {
			SDL_BlitSurface(pic,NULL,sf,&r);
			r.y += pic->h+8;
		}
		SDL_FreeSurface(pic);
	}
	y += put_string(sf,font,x,y,title,fg,r.y);
	y += 12;
	TTF_SetFontStyle(font,TTF_STYLE_NORMAL);
	y += put_string(sf,font,x,y,desc,fg,r.y);

	// Display
	x = (width-sf->w) / 2;
	y = height - sf->h - 8;
	blit(fifo, sf->pixels, sf->w, sf->h, x, y, 0, 0);
	send_command(fifo,"SHOW\n");
#if 0
	sleep(10);

	// Fade in sf
	for(i=0; i >= -255; i-=5)
		set_alpha(fifo, sf->w, sf->h,
				x, y, i);
#endif
	FILE *f = fopen("info_coords","w");
	fprintf(f,"%d %d %d %d ",sf->w, sf->h,
			x, y);
	fclose(f);
	// Clean up
	SDL_FreeSurface(sf);
	free(heure);
	free(title);
	free(channel);
	free(picture);
	free(desc);

	return 0;
}

static int list(int fifo, int argc, char **argv)
{
    int width,height;

    if(argc<4) {
		printf("Usage: %s <bmovl fifo> <width> <height> [<max height>]\n", argv[0]);
		printf("width and height are w/h of MPlayer's screen!\n");
		return -1;
    }

    // int maxh;
    width = atoi(argv[2]);
	height = atoi(argv[3]);
	// if (argc == 5) maxh = atoi(argv[4]);
	// else maxh = height - 8;
	int fsize = height/35;
	TTF_Init();
	TTF_Font *font = TTF_OpenFont("Vera.ttf",fsize);
	if (!font) font = TTF_OpenFont("/usr/share/fonts/truetype/ttf-bitstream-vera/Vera.ttf",12);
	char *source,buff[2048],*list[20];
	int num[20];
	int current;
	myfgets(buff,2048,stdin);
	source = strdup(buff);
	int nb=0,w,h;
	int margew = width/36, margeh=height/36;
	int maxw=width/2-margew;
	int numw = 0;
	// Lecture des chaines, 20 maxi.
	int wlist,hlist;
	get_size(font,source,&wlist,&hlist,maxw);
	while (!feof(stdin) && nb<20) {
		myfgets(buff,2048,stdin);
		if (buff[0] == '*') current = nb;
		char *end_nb = &buff[4];
		while (*end_nb >= '0' && *end_nb <= '9')
			end_nb++;
		*end_nb++ = 0;
		get_size(font,&buff[1],&w,&h,maxw);
		if (w > numw) numw = w;
		num[nb] = atoi(&buff[1]);
		list[nb++] = strdup(end_nb);
		int l = strlen(end_nb);
		if (end_nb[l-1] == '>')
			end_nb[l-1] = 0;
		get_size(font,end_nb,&w,&h,maxw); 
		if (w > wlist) wlist = w;
		hlist += h;
	}
    get_size(font,">",&w,&h,maxw);
    int indicw = w;

    int n;
    int x=8,y=8;
    wlist += numw+8; // le numéro sur la gauche (3 chiffres + séparateur)
    int xright = x+wlist;
    wlist += indicw; // place pour le > à la fin
    /*	if (hlist > maxh)
	hlist = maxh; */

    SDL_Surface *sf = create_surface(wlist+16,hlist+16);

    TTF_SetFontStyle(font,TTF_STYLE_BOLD);
    y += put_string(sf,font,x,y,source,SDL_MapRGB(sf->format,0xff,0xff,0x80),
	    height);
    x += numw+8; // aligné après les numéros
    int fg = get_fg(sf);
    TTF_SetFontStyle(font,TTF_STYLE_NORMAL);
    int bg = get_bg(sf);
	for (n=0; n<nb; n++) {
		int hidden = 0;
		int l = strlen(list[n]);
		if (list[n][l-1] == '>') {
			list[n][l-1] = 0;
			hidden = 1;
		}
		int y0 = y;
		char buff[5];
		sprintf(buff,"%d",num[n]);
		if (current == n) {
			SDL_Rect r;
			r.x = 8; r.y = y; r.w = wlist; r.h = fsize;
			SDL_FillRect(sf,&r,fg);
			put_string(sf,font,8,y,buff,bg,height); // Numéro
			int dy = put_string(sf,font,x,y,list[n],bg,height);
			if (dy != fsize) { // bad guess, 2nd try...
				r.h = dy;
				SDL_FillRect(sf,&r,fg);
				put_string(sf,font,8,y,buff,bg,height); // Numéro
				dy = put_string(sf,font,x,y,list[n],bg,height);
			}
			y += dy;
		} else {
			put_string(sf,font,8,y,buff,fg,height); // Numéro
			y += put_string(sf,font,x,y,list[n],fg,height);
		}
		if (hidden) {
			put_string(sf,font,xright,y0,">",(current == n ? bg : fg),height);
		}
	}

    // Display
    x = margew;
    y = margeh;
    blit(fifo, sf->pixels, sf->w, sf->h, x, y, 0, 1);
    send_command(fifo,"SHOW\n");
    FILE *f = fopen("list_coords","w");
    fprintf(f,"%d %d %d %d ",sf->w, sf->h,
	    x, y);
    fclose(f);
    // Clean up
    SDL_FreeSurface(sf);
	if (!strcasecmp(list[current],"nolife")) {
		sprintf(buff,"perl noair.pl %d &",y+sf->h);
		system(buff);
	} else {
		FILE *f = fopen("fifo_info","w");
		if (f) {
			fprintf(f,"prog %s\n%d\n",list[current],y+sf->h);
			fclose(f);
		}
	}
#if 0
	sleep(10);

	// Fade in sf
	for(i=0; i >= -255; i-=5)
		set_alpha(fifo, sf->w, sf->h,
				x, y, i);
#endif
	free(source);
	for (n=0; n<nb; n++)
		free(list[n]);
	return 0;
}

void clear(int fifo, int argc, char **argv)
{
	char buff[2048];
	sprintf(buff,"CLEAR %s %s %s %s\n",argv[1],argv[2],argv[3],argv[4]);
	write(fifo, buff, strlen(buff));
}

void alpha(int fifo, int argc, char **argv)
{
	char buff[2048];
	sprintf(buff,"ALPHA %s %s %s %s %s\n",argv[1],argv[2],argv[3],argv[4],
			argv[5]);
	write(fifo, buff, strlen(buff));
}

int main(int argc, char **argv) {

	int fifo=-1;
	unlink("fifo_bmovl");
	mkfifo("fifo_bmovl",0700);
	if (argc != 2) {
		printf("pass fifo as unique argument\n");
		return -1;
	}
	fifo = open( argv[1], O_RDWR );
	if (fifo <= 0) {
		printf("server: could not open fifo !\n");
		return -1;
	}
	FILE *f = fopen("info.pid","w");
	fprintf(f,"%d\n",getpid());
	fclose(f);
	if(!fifo) {
		fprintf(stderr, "Error opening FIFO %s!\n", argv[1]);
		unlink("info.pid");
		exit(10);
	}
	char buff[2048];
	char *myargv[10];
	FILE *server = NULL;

    while (1) {
		if (!server) {
			server = fopen("fifo_bmovl","r");
			if (!server) {
				printf("can't open fifo_bmovl ???\n");
				return -1;
			}
		}
		int len = myfgets(buff,2048,server);
		argc = 1;
		char *s = buff;
		myargv[0] = buff;
		while ((s = strchr(s,' '))) {
			*s = 0; s++;
			while (*s == ' ') s++;
			if (*s)
				myargv[argc++] = s;
		}
		stdin = server;
		char *cmd = myargv[0];
		if (!len) *cmd = 0;
		s = strrchr(cmd,'/');
		if (s) cmd =s+1;
		if (fifo > 0) {
			// commandes connectées
			if (!strcmp(cmd,"bmovl"))
				info(fifo,argc,myargv);
			else if (!strcmp(cmd,"list"))
				list(fifo,argc,myargv);
			else if (!strcmp(cmd,"CLEAR"))
				clear(fifo,argc,myargv);
			else if (!strcmp(cmd,"ALPHA"))
				alpha(fifo,argc,myargv);
			else if (!strcmp(cmd,"disconnect")) {
				close(fifo);
				fifo = 0;
				printf("server: déconnexion ok\n");
			} else if (!strcmp(cmd,"connect")) {
				close(fifo);
				printf("connect re�u... reconnexion...\n");
				fifo = open( argv[1], O_RDWR );
				if (fifo <= 0) {
					printf("server: could not open fifo !\n");
				} else
					printf("server: reconnexion ok fifo %d\n",fifo);
			
			} else
				printf("server: commande non reconnue :%s.\n",cmd);
		} else {
			// 1 seule commande acceptée quand déconnecté
			if (!strcmp(cmd,"connect")) {
				fifo = open( argv[1], O_RDWR );
				if (fifo <= 0) {
					printf("server: could not open fifo !\n");
				} else
					printf("server: reconnexion ok fifo %d\n",fifo);
			} else 
				printf("server: commande ignorée : %s\n",cmd);
		}
		if (feof(server)) {
				fclose(server);
				server = NULL;
		}
	}
}
