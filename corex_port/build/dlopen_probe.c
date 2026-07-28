#include <dlfcn.h>
#include <stdio.h>
int main(int argc, char** argv) {
    const char* lib = argv[1];
    void* h = dlopen(lib, RTLD_NOW | RTLD_GLOBAL);
    if (!h) {
        printf("dlopen FAILED for %s:\n  %s\n", lib, dlerror());
        return 1;
    }
    printf("dlopen OK for %s\n", lib);
    return 0;
}
