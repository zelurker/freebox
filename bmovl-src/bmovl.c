#include <fcntl.h>
#include <SDL/SDL.h>
#include <SDL/SDL_ttf.h>
#include <SDL/SDL_image.h>
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
static int server;

/* Les commandes de connexion/déconnexion au fifo mplayer doivent être passés
 * par signaux et pas par le fifo de commande parce que malheureusement un
 * mplayer peut quitter pendant qu'une commande est en cours, dans ce cas là
 * pour ne pas rester bloqué en lecture rien de mieux que le signal */
static void disconnect(int signal) {
	if (!fifo) return;
	close(fifo);
	if (sdl_screen) {
	    memset(sdl_screen->pixels,0,sdl_screen->w*sdl_screen->h*
		    sdl_screen->format->BytesPerPixel);
	    SDL_UpdateRect(sdl_screen,0,0,sdl_screen->w,sdl_screen->h);
	}

	fifo = 0;
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
	SDL_Surface *chan = NULL,*pic = NULL; 

	int margew,margeh;
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
		if (desc) {
			free(desc);
			TTF_CloseFont(font);
			SDL_FreeSurface(sf);
		}
		font = TTF_OpenFont("Vera.ttf",fsize);
		if (!font) font = TTF_OpenFont("/usr/share/fonts/truetype/ttf-bitstream-vera/Vera.ttf",12);
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

		/* Determine max length of text */
		if (chan && (chan->w >= width/2 || 3+fsize+chan->h+8+(pic ? pic->h+8 : 0) >= maxh)) {
			/* Give priority to picture, remove channel logo 1st if not enough
			 * space */
			SDL_FreeSurface(chan);
			chan = NULL;
		}
		if (pic && (pic->w >= width/2 || 3+fsize+pic->h+8+(chan ? chan->h+8 : 0)>=maxh)) {
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
		while (!feof(stdin) && len < 8191) {
			fgets(&buff[len],8192-len,stdin); // we keep the eol here
			while (buff[len]) len++;
		}
		while (len > 0 && buff[len-1] < 32) buff[--len] = 0; // remove the last one though
		desc = strdup(buff);

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

		sf = create_surface(width,h);
		fg = get_fg(sf);

		// Ok, finalement on affiche les chaines (heure, titre, desc)
		x = myx;
		y = 8;
		TTF_SetFontStyle(font,TTF_STYLE_BOLD);
		y += put_string(sf,font,18,y,heure,fg,0);
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
		x = x0; y = y0;
		if (!next) return 0;
		prev[nb_prev++] = str;
		if (nb_prev == MAX_PREV) nb_prev = MAX_PREV-1;
		str = next;
		SDL_Rect b;
		int bg = get_bg(sf);
		b.x = x; b.y = y; b.w = sf->w-x-1; b.h = sf->h-y-1;
		SDL_FillRect(sf,&b,bg);
		b.x = 18; b.y = r.y; b.w = x-18; b.h = sf->h-r.y-1;
		SDL_FillRect(sf,&b,bg);
	} else if (!strcmp(argv[0],"prev")) {
		if (!nb_prev) return 0;
		str = prev[--nb_prev];
		x = x0; y = y0;
		SDL_Rect b;
		int bg = get_bg(sf);
		b.x = x; b.y = y; b.w = sf->w-x-1; b.h = sf->h-y-1;
		SDL_FillRect(sf,&b,bg);
		b.x = 18; b.y = r.y; b.w = x-18; b.h = sf->h-r.y-1;
		SDL_FillRect(sf,&b,bg);
	} else {
		printf("info: unknown command %s\n",argv[0]);
		return 1;
	}
		
	y += put_string(sf,font,x,y,str,fg,r.y);
	next = get_next_string();

	// Display
	x = margew;
	y = height - sf->h - margeh;
	FILE *f = fopen("info_coords","r");
	if (f) {
		int oldx,oldy,oldw,oldh;
		fscanf(f,"%d %d %d %d",&oldw,&oldh,&oldx,&oldy);
		fclose(f);
		if (oldh > sf->h) {
			char buff[2048];
			sprintf(buff,"CLEAR %d %d %d %d\n",oldw,oldh-sf->h,oldx,oldy);
			send_command(fifo, buff);
		}
	}
	/* printf("bmovl: blit %d %d %d %d avec width %d height %d\n",
			sf->w,sf->h,x,y,width,height); */
	blit(fifo, sf, x, y, -40, 0);
	send_command(fifo,"SHOW\n");
	// printf("bmovl: show done\n");
	f = fopen("info_coords","w");
	fprintf(f,"%d %d %d %d ",sf->w, sf->h,
			x, y);
	fclose(f);

	return 0;
}

static int list(int fifo, int argc, char **argv, int noinfo)
{
    int width,height;

    char *source,buff[4096],*list[20],status[20];
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
    TTF_Font *font = TTF_OpenFont("Vera.ttf",fsize);
    if (!font) font = TTF_OpenFont("/usr/share/fonts/truetype/ttf-bitstream-vera/Vera.ttf",12);
    int num[20];
    int current = -1;
    myfgets(buff,4096,stdin);
    source = strdup(buff);
    int nb=0,w,h;
    int margew = width/36, margeh=height/36;
    int maxw=width/2-margew;
    int numw = 0;
    // Lecture des chaines, 20 maxi.
    int wlist,hlist;
    TTF_SetFontStyle(font,TTF_STYLE_BOLD);
    get_size(font,source,&wlist,&hlist,maxw);
    TTF_SetFontStyle(font,TTF_STYLE_NORMAL);
    while (!feof(stdin) && nb<20) {
	if (!myfgets(buff,4096,stdin)) break;
	if (buff[0] == '*') current = nb;
	status[nb] = buff[0];
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
	get_size(font,end_nb,&w,&h,maxw-numw); 
	if (w > wlist) wlist = w;
	hlist += h;
    }
    get_size(font,">",&w,&h,maxw);
    int indicw = w;

    int n;
    int x=8,y=8;
    wlist += numw+8; // le numÃ©ro sur la gauche (3 chiffres + sÃ©parateur)
    if (wlist > maxw) {
	wlist = maxw;
    }
    int xright = x+wlist;
    wlist += indicw; // place pour le > Ã  la fin
    /*	if (hlist > maxh)
	hlist = maxh; */

    SDL_Surface *sf = create_surface(wlist+16,hlist+16);

    TTF_SetFontStyle(font,TTF_STYLE_BOLD);
    y += put_string(sf,font,x,y,source,SDL_MapRGB(sf->format,0xff,0xff,0x80),
	    height);
    x += numw+8; // alignÃ© aprÃ¨s les numÃ©ros
    int fg = get_fg(sf);
    int red = SDL_MapRGB(sf->format,0xff,0x50,0x50);
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
	    put_string(sf,font,8,y,buff,bg,height); // NumÃ©ro
	    int dy = put_string(sf,font,x,y,list[n],bg,height);
	    if (dy != fsize) { // bad guess, 2nd try...
		r.h = dy;
		SDL_FillRect(sf,&r,fg);
		put_string(sf,font,8,y,buff,bg,height); // NumÃ©ro
		dy = put_string(sf,font,x,y,list[n],bg,height);
	    }
	    y += dy;
	} else {
	    char oldfg;
	    if (status[n] == 'R') {
		oldfg = fg;
		fg = red;
	    }
	    put_string(sf,font,8,y,buff,fg,height); // NumÃ©ro
	    y += put_string(sf,font,x,y,list[n],fg,height);
	    if (status[n] == 'R') fg = oldfg;
	}
	if (hidden) {
	    put_string(sf,font,xright,y0,">",(current == n ? bg : fg),height);
	}
    }

    FILE *f = fopen("list_coords","r");
    if (f) {
	int oldx,oldy,oldw,oldh;
	fscanf(f,"%d %d %d %d",&oldw,&oldh,&oldx,&oldy);
	fclose(f);
	if (oldh > sf->h) {
	    char buff[2048];
	    sprintf(buff,"CLEAR %d %d %d %d\n",oldw,oldh-sf->h,oldx,oldy+sf->h);
	    send_command(fifo, buff);
	}
	if (oldw > sf->w) {
	    char buff[2048];
	    sprintf(buff,"CLEAR %d %d %d %d\n",oldw-sf->w,oldh,oldx+sf->w,oldy);
	    printf("list: %s",buff);
	    send_command(fifo, buff);
	}
    }

    // Display
    x = margew;
    y = margeh;
    // Sans le clear à 1 ici, l'affichage du bandeau d'info par blit fait
    // apparaitre des déchets autour de la liste. Ca ne devrait pas arriver.
    // Pour l'instant le meilleur contournement c'est ça.
    blit(fifo, sf, x, y, -40, (noinfo ? 0 : 1));
    send_command(fifo,"SHOW\n");
    f = fopen("list_coords","w");
    fprintf(f,"%d %d %d %d ",sf->w, sf->h,
	    x, y);
    fclose(f);
    // Clean up
    SDL_FreeSurface(sf);
    if (current > -1 && !noinfo) {
	int info=0;
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
	} else
	    printf("on abandonne fifo_info !\n");
    }
    free(source);
    for (n=0; n<nb; n++)
	free(list[n]);
    TTF_CloseFont(font);
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
	if (buff[1] == 0)
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

static void handle_event(SDL_Event *event) {
    if (!nb_keys) read_inputs();
    if (event->type != SDL_KEYDOWN) return;
    int input = event->key.keysym.sym;
    printf("reçu touche %d (%c)\n",input,input);
    int n;
    for (n=0; n<nb_keys; n++) {
	if (input == keys[n]) {
	    printf("touche trouvée, commande %s\n",command[n]);
	    if (!strncmp(command[n],"run",3)) 
		system(&command[n][4]);
	    else {
		int cmd = open("fifo_cmd",O_WRONLY|O_NONBLOCK);
		if (cmd > 0) {
		    write(cmd,command[n],strlen(command[n]));
		    close(cmd);
		} else
		    printf("could not send command\n");
	    }
	    break;
	}
    }
}

int main(int argc, char **argv) {

	signal(SIGUSR1, &myconnect);
	signal(SIGUSR2, &disconnect);
	signal(SIGPIPE, &disconnect);
	signal(SIGTERM, &myexit);
	FILE *f = fopen("info.pid","w");
	fprintf(f,"%d\n",getpid());
	fclose(f);
	unlink("fifo_bmovl");
	mkfifo("fifo_bmovl",0700);
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
		    if (SDL_PollEvent(&event))
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
		} else if (!strcmp(cmd,"list-noinfo")) {
		    ret = list(fifo,argc,myargv,1);
		} else if (!strcmp(cmd,"CLEAR")) {
		    ret = clear(fifo,argc,myargv);
		} else if (!strcmp(cmd,"ALPHA")) {
		    ret = alpha(fifo,argc,myargv);
		} 
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
