#ifndef __JENKINS_H__
#define __JENKINS_H__

#ifndef DEV_RANDOM
#define DEV_RANDOM "/dev/random"
#endif

void raninit(uint32_t seed);
uint32_t ranval(void);

#endif
