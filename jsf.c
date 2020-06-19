/* Jenkins Small Fast -- "A small noncryptographic PRNG"
 * http://burtleburtle.net/bob/rand/smallprng.html
 * https://www.pcg-random.org/posts/some-prng-implementations.html */

#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

// 2009 macbook gets illegal instruction but compiler does define
// __RDRND__ so instead if want this supply this custom define
#ifdef USE_RDRND
#include <immintrin.h>
#endif

#include "jsf.h"

#define rot32(x, k) (((x) << (k)) | ((x) >> (32 - (k))))

struct ranctx {
    uint32_t a;
    uint32_t b;
    uint32_t c;
    uint32_t d;
};

struct ranctx ctx;

uint32_t seed;

inline void raninit(uint32_t seed) {
    uint32_t i;
    ctx.a = 0xf1ea5eed, ctx.b = ctx.c = ctx.d = seed;
    for (i = 0; i < 20; i++)
        ranval();
}

uint32_t ranval(void) {
    uint32_t e = ctx.a - rot32(ctx.b, 27);
    ctx.a      = ctx.b ^ rot32(ctx.c, 17);
    ctx.b      = ctx.c + ctx.d;
    ctx.c      = ctx.d + e;
    ctx.d      = e + ctx.a;
    return ctx.d;
}

void setup_jsf(void) {
#ifdef USE_RDRND
    int ret = _rdrand32_step(&seed);
    if (ret != 1) abort();
#else
    int fd = open(DEV_RANDOM, O_RDONLY);
    if (fd == -1) abort();
    if (read(fd, &seed, sizeof(seed)) != sizeof(seed)) abort();
    close(fd);
#endif
    raninit(seed);
}
