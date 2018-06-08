
#ifdef SDL1
extern SDL_Surface *sdl_screen;
#else
extern SDL_Window *sdl_screen;
extern SDL_Renderer *renderer;
#endif

extern int desktop_w,desktop_h,desktop_bpp;
void
blit(int fifo, SDL_Surface *bmp, int xpos, int ypos, int alpha, int clear);
int send_command(int fifo,char *cmd);

void get_size(TTF_Font *font, char *text, int *w, int *h, int maxw);

// direct_string : pas de retour à la ligne, sortie directe
int direct_string(SDL_Surface *sf, TTF_Font *font, int x, int y,
	char *text, int color);
int put_string(SDL_Surface *sf, TTF_Font *font, int x, int y,
		char *text, int color, int *indents);

int myfgets(unsigned char *buff, int size, FILE *f);

SDL_Surface *create_surface(int w, int h);

int get_fg(SDL_Surface *sf);
int get_bg(SDL_Surface *sf);
char *get_next_string();
void init_video();
