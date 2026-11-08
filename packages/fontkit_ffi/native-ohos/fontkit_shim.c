#include <dirent.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
typedef struct { int n; char** labels; char** paths; } FL;
static char* dup(const char*s){ size_t n=strlen(s)+1; char*p=malloc(n); memcpy(p,s,n); return p; }
static char* strip_ext(const char*name){ char*p=dup(name); char*dot=strrchr(p,'.'); if(dot)*dot=0; return p; }
static int hasfont(const char*n){ const char*e=strrchr(n,'.'); if(!e)return 0; return !strcmp(e,".ttf")||!strcmp(e,".ttc")||!strcmp(e,".otf"); }
void* lanlu_font_list_create(void){
  DIR*d=opendir("/system/fonts"); if(!d) return 0;
  FL*f=calloc(1,sizeof(FL)); int cap=128; f->labels=malloc(sizeof(char*)*cap); f->paths=malloc(sizeof(char*)*cap);
  struct dirent*e; while((e=readdir(d))){ if(e->d_name[0]=='.')continue; if(!hasfont(e->d_name))continue;
    if(f->n>=cap){cap*=2; f->labels=realloc(f->labels,sizeof(char*)*cap); f->paths=realloc(f->paths,sizeof(char*)*cap);}
    char full[512]; snprintf(full,sizeof full,"/system/fonts/%s",e->d_name);
    f->paths[f->n]=dup(full); f->labels[f->n]=strip_ext(e->d_name); f->n++; }
  closedir(d); return f;
}
unsigned long lanlu_font_list_count(void*p){ return p?((unsigned long)((FL*)p)->n):0; }
const char* lanlu_font_list_label(void*p,unsigned long i){ FL*f=p; if(!f||i>=(unsigned long)f->n) return 0; return f->labels[i]; }
const char* lanlu_font_list_path(void*p,unsigned long i){ FL*f=p; if(!f||i>=(unsigned long)f->n) return 0; return f->paths[i]; }
void lanlu_font_list_destroy(void*p){ FL*f=p; if(!f)return; for(int i=0;i<f->n;i++){free(f->labels[i]);free(f->paths[i]);} free(f->labels);free(f->paths);free(f);}
