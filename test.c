// Test C file for xmap.nvim
// TODO: Improve parser coverage

#include <stdio.h>
#define MAX_ITEMS 128

typedef struct Item {
  int id;
  const char *name;
} Item;

enum Mode {
  MODE_IDLE = 0,
  MODE_RUN = 1,
};

static int clamp_int(int value, int min, int max) {
  if (value < min) {
    return min;
  }
  if (value > max) {
    return max;
  }
  return value;
}

int process_items(Item *items, int count) {
  // FIXME: Handle NULL items
  int i = 0;
  while (i < count) {
    printf("%d %s\n", items[i].id, items[i].name);
    i++;
  }
  return clamp_int(count, 0, MAX_ITEMS);
}
