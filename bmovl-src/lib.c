
#include <SDL/SDL.h>
#include <SDL/SDL_ttf.h>

#define DEBUG 0

void
blit(int fifo, unsigned char *bitmap, int width, int height,
     int xpos, int ypos, int alpha, int clear)
{
	char str[100];
	int  nbytes;
	
	sprintf(str, "RGBA32 %d %d %d %d %d %d\n",
	        width, height, xpos, ypos, alpha, clear);
	
	if(DEBUG) printf("Sending %s", str);

	write(fifo, str, strlen(str));
	nbytes = write(fifo, bitmap, width*height*4);

	if(DEBUG) printf("Sent %d bytes of bitmap data...\n", nbytes);
}

void
set_alpha(int fifo, int width, int height, int xpos, int ypos, int alpha) {
	char str[100];

	sprintf(str, "ALPHA %d %d %d %d %d\n",
	        width, height, xpos, ypos, alpha);
	
	if(DEBUG) printf("Sending %s", str);

	write(fifo, str, strlen(str));
}

void send_command(int fifo,char *cmd) {
	write(fifo,cmd,strlen(cmd));
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

int put_string(SDL_Surface *sf, TTF_Font *font, int x, int y,
		char *text, int color, int maxw, int maxy, int width, int maxh)
{
	/* Gère les retours charriots dans la chaine, renvoie la hauteur totale */
	int h = 0;
	char *beg = text,*s;
	do {
		s = strchr(beg,'\n');
		if (s) *s = 0;
		if (*beg) {

			char *white,old;
			int myw,myh,pos;;
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

				// we have a substring that can be displayed here...
				SDL_Rect dest;
				dest.x = x; dest.y = y;
				SDL_Color *col = (SDL_Color*)&color; // dirty hack !
				SDL_Surface *tf = TTF_RenderText_Solid(font,beg,*col);
				if (y + tf->h < maxh)
					SDL_BlitSurface(tf,NULL,sf,&dest);
				h += tf->h;
				y += tf->h;
				SDL_FreeSurface(tf);

				if (y > maxy && x > 18) {
					// We just got below the pictures, use the space then !
					maxw = width-32;
					x = 18;
				}
				if (white) {
					*white = ' ';
					beg = white+1;
				}
			} while (white);

		} else {
			h += 12;
			y += 12;
		}
		if (s) {
			*s = '\n';
			beg = s+1;
		}
	} while (s && *beg);
	return h;
}

int myfgets(char *buff, int size, FILE *f) {
  fgets(buff,size,f);
  int len = strlen(buff);
  while (len > 0 && buff[len-1] < 32)
    buff[--len] = 0;
  return len;
}
