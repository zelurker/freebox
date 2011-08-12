
void
blit(int fifo, unsigned char *bitmap, int width, int height,
     int xpos, int ypos, int alpha, int clear);
void
set_alpha(int fifo, int width, int height, int xpos, int ypos, int alpha);

void send_command(int fifo,char *cmd);

void get_size(TTF_Font *font, char *text, int *w, int *h, int maxw);

int put_string(SDL_Surface *sf, TTF_Font *font, int x, int y, 
		char *text, int color, int maxy);

int myfgets(char *buff, int size, FILE *f);

SDL_Surface *create_surface(int w, int h);

int get_fg(SDL_Surface *sf);
int get_bg(SDL_Surface *sf);

