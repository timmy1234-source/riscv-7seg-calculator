// A C implementation of memcpy()
// see https://www.geeksforgeeks.org/write-memcpy/
#include<stdio.h>
#include<string.h>

void *memcpy(void *dest, const void *src, size_t n) {
  // Typecast src and dest addresses to (char *)
  char *csrc = (char *)src;
  char *cdest = (char *)dest;

  // Copy contents of src[] to dest[]
  for (int i=0; i<n; i++) {
    cdest[i] = csrc[i];
  }
  return dest;
}
