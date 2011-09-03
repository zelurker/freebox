
extern SDL_Surface *sdl_screen;

void
blit(int fifo, SDL_Surface *bmp, int xpos, int ypos, int alpha, int clear);
void send_command(int fifo,char *cmd);

void get_size(TTF_Font *font, char *text, int *w, int *h, int maxw);

int put_string(SDL_Surface *sf, TTF_Font *font, int x, int y, 
		char *text, int color, int maxy);

int myfgets(char *buff, int size, FILE *f);

SDL_Surface *create_surface(int w, int h);

int get_fg(SDL_Surface *sf);
int get_bg(SDL_Surface *sf);
char *get_next_string();
