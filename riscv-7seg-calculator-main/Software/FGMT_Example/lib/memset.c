/*
 * memset.c
 *
 *  Created on: 25.01.2025
 *      Author: Bernhard
 */

#include<stdio.h>
#include<string.h>

void *memset(void *dest, int c, size_t n) {
  // Typecast dest addresses to (char *)
  char *cdest = (char *)dest;

  // Copy contents of src[] to dest[]
  for (int i=0; i<n; i++) {
    cdest[i] = c;
  }
  return dest;
}



