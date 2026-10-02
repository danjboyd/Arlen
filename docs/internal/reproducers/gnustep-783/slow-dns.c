#define _GNU_SOURCE
#include <netdb.h>
#include <dlfcn.h>
#include <time.h>
#include <string.h>
int getaddrinfo(const char *node,const char *service,const struct addrinfo *hints,struct addrinfo **result) {
 static int (*real)(const char *,const char *,const struct addrinfo *,struct addrinfo **);
 if(!real) real=dlsym(RTLD_NEXT,"getaddrinfo");
 if(node && strcmp(node,"arlen-deadline.invalid")==0) { struct timespec delay={1,0}; nanosleep(&delay,0); return EAI_NONAME; }
 return real(node,service,hints,result);
}
int gethostbyname_r(const char *name,struct hostent *ret,char *buf,size_t buflen,struct hostent **result,int *h_errnop) {
 static int (*real)(const char *,struct hostent *,char *,size_t,struct hostent **,int *);
 if(!real) real=dlsym(RTLD_NEXT,"gethostbyname_r");
 if(name && strcmp(name,"arlen-deadline.invalid")==0) { struct timespec delay={1,0}; nanosleep(&delay,0); name="127.0.0.1"; }
 return real(name,ret,buf,buflen,result,h_errnop);
}
