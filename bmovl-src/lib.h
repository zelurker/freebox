
extern SDL_Surface *sdl_screen;

void
blit(int fifo, SDL_Surface *bmp, int xpos, int ypos, int alpha, int clear);
int send_command(int fifo,char *cmd);

void get_size(TTF_Font *font, char *text, int *w, int *h, int maxw);

// direct_string : pas de retour à la ligne, sortie directe
int direct_string(SDL_Surface *sf, TTF_Font *font, int x, int y,
	char *text, int color);
int put_string(SDL_Surface *sf, TTF_Font *font, int x, int y, 
		char *text, int color, int *indents);

int myfgets(char *buff, int size, FILE *f);

SDL_Surface *create_surface(int w, int h);

int get_fg(SDL_Surface *sf);
int get_bg(SDL_Surface *sf);
char *get_next_string();
void init_video();
