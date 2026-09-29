/* C port (c/planet-time). Usage: probe <inputs.txt> */
#include <stdio.h>
#include <string.h>
#include <inttypes.h>
#include "libinterplanet.h"

static const char *BODIES[] = {"mercury", "venus", "earth", "mars", "jupiter",
                               "saturn", "uranus", "neptune", "moon"};

int main(int argc, char **argv) {
    if (argc < 2) return 2;
    FILE *f = fopen(argv[1], "r");
    if (!f) { perror(argv[1]); return 2; }
    char body[32];
    long long ms;
    while (fscanf(f, "%31s %lld", body, &ms) == 2) {
        int p = -1;
        for (int i = 0; i < 9; i++) if (strcmp(body, BODIES[i]) == 0) p = i;
        if (p < 0) { fprintf(stderr, "unknown body %s\n", body); return 1; }
        ipt_planet_time_t pt;
        if (ipt_get_planet_time((ipt_planet_t)p, ms, 0, &pt) != 0) { printf("%s\t%lld\terror\n", body, ms); continue; }
        printf("%s\t%lld\t%d\t%d\t%d\t%" PRId32 "\t", body, ms, pt.hour, pt.minute, pt.second, pt.day_number);
        if (p == IPT_EARTH || p == IPT_MOON) printf("-\t");
        else printf("%.3f\t", ipt_light_travel_s(IPT_EARTH, (ipt_planet_t)p, ms));
        if (p == IPT_MARS) {
            ipt_mtc_t m;
            ipt_get_mtc(ms, &m);
            printf("%" PRId32 "\t%d\t%d\t%d\n", m.sol, m.hour, m.minute, m.second);
        } else {
            printf("-\t-\t-\t-\n");
        }
    }
    fclose(f);
    return 0;
}
