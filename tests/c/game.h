/* SPDX-License-Identifier: BSL-1.0 */

/* The C test's own types, which `describe.c` tells the registry about and
 * the other parts read back through it. */

#ifndef FXR_TEST_GAME_H
#define FXR_TEST_GAME_H

#include "fluxion_reflect.h"

typedef struct Vec2 {
    float x;
    float y;
} Vec2;

typedef enum EnemyKind { ENEMY_SLIME = 1, ENEMY_BAT = 2, ENEMY_BOSS = 10 } EnemyKind;

typedef union Payload {
    int32_t whole;
    float fraction;
} Payload;

typedef struct Enemy {
    uint32_t id;
    Vec2 at;
    int kind;
    uint8_t hp;
    char name[16];
    const char *title;
    Payload payload;
} Enemy;

extern Enemy boss;

#endif
