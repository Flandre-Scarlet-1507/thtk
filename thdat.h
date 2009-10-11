/*
 * Redistribution and use in source and binary forms, with
 * or without modification, are permitted provided that the
 * following conditions are met:
 *
 * 1. Redistributions of source code must retain this list
 *    of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce this
 *    list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the
 *    distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND
 * CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
 * WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
 * PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
 * COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 * INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 * OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
 * DAMAGE.
 */
#ifndef THDAT_H_
#define THDAT_H_

#include <config.h>
#include <inttypes.h>
#include <stdio.h>
#include "datpacker.h"

/* TODO: Rename functions. */
archive_t* archive_open(FILE* fd, uint32_t version, uint32_t offset, unsigned int count);

/* All of these functions set library_error on error. */

/* Reads entry->size bytes from the passed file descriptor.  Returns a newly
 * allocated buffer with the read data.  Returns NULL on error. */
unsigned char* thdat_read_file(entry_t* entry, FILE* fd);
/* Reads entry->size bytes from the passed file descriptor.  Returns a newly
 * allocated buffer containing an LZSS compressed version of the read data.
 * Returns NULL on error. */
unsigned char* thdat_read_file_lzss(entry_t* entry, FILE* fd);
/* Performs RLE on the passed buffer.  Frees the passed buffer.  Updates
 * entry->zsize.  Returns a newly allocated buffer containing the RLE data.
 * Returns NULL on error. */
unsigned char* thdat_rle(entry_t* entry, unsigned char* data);
/* Writes the entry->zsize bytes from the passed buffer to the archive.  Frees
 * the passed buffer.  Updates the archive offset.  Returns -1 on error. */
int thdat_write_entry(archive_t* archive, entry_t* entry, unsigned char* data);
/* Sorts the entries in the archive according to their offsets. */
void thdat_sort(archive_t* archive);

#endif
