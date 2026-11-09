#!/usr/bin/env python3
"""
Python implementation of simg2img (sparse image to raw image converter).
Handles Android sparse image format (0xED26FF3A).
"""

import sys
import struct
import os

SPARSE_HEADER_MAGIC = 0xED26FF3A
CHUNK_TYPE_RAW = 0xCAC1
CHUNK_TYPE_FILL = 0xCAC2
CHUNK_TYPE_DONT_CARE = 0xCAC3
CHUNK_TYPE_CRC32 = 0xCAC4

def is_sparse(path):
    with open(path, "rb") as f:
        magic = f.read(4)
        if len(magic) == 4 and struct.unpack("<I", magic)[0] == SPARSE_HEADER_MAGIC:
            return True
    return False

def simg2img(src_path, dst_path):
    with open(src_path, "rb") as src:
        header = src.read(28)
        if len(header) < 28:
            raise ValueError("File is too short to be a sparse image")
        
        magic, major, minor, file_hdr_sz, chunk_hdr_sz, blk_sz, total_blks, total_chunks, crc = struct.unpack(
            "<IHHHHIIII", header
        )
        
        if magic != SPARSE_HEADER_MAGIC:
            raise ValueError(f"Invalid magic: {hex(magic)}, expected {hex(SPARSE_HEADER_MAGIC)}")
        
        if major != 1:
            raise ValueError(f"Unsupported major version: {major}")
        
        if file_hdr_sz > 28:
            src.seek(file_hdr_sz - 28, os.SEEK_CUR)
            
        print(f"[*] Sparse image: {total_blks} blocks ({total_blks * blk_sz / (1024*1024):.1f} MB), {total_chunks} chunks, block size {blk_sz}")
        
        with open(dst_path, "wb") as dst:
            for c_idx in range(total_chunks):
                chunk_hdr = src.read(chunk_hdr_sz)
                if len(chunk_hdr) < chunk_hdr_sz:
                    raise ValueError(f"Premature EOF reading chunk {c_idx}")
                
                chunk_type, reserved, chunk_sz, total_sz = struct.unpack("<HHII", chunk_hdr[:12])
                data_sz = total_sz - chunk_hdr_sz
                
                if chunk_type == CHUNK_TYPE_RAW:
                    if data_sz != chunk_sz * blk_sz:
                        raise ValueError(f"RAW chunk size mismatch: data_sz={data_sz}, expected {chunk_sz * blk_sz}")
                    # Stream in 1MB chunks to avoid memory spike
                    remaining = data_sz
                    while remaining > 0:
                        to_read = min(remaining, 1024 * 1024)
                        buf = src.read(to_read)
                        if not buf:
                            raise ValueError("Unexpected EOF in RAW chunk")
                        dst.write(buf)
                        remaining -= len(buf)
                elif chunk_type == CHUNK_TYPE_FILL:
                    fill_bin = src.read(4)
                    if data_sz != 4:
                        src.seek(data_sz - 4, os.SEEK_CUR)
                    fill_unit = fill_bin * (blk_sz // 4)
                    for _ in range(chunk_sz):
                        dst.write(fill_unit)
                elif chunk_type == CHUNK_TYPE_DONT_CARE:
                    if data_sz > 0:
                        src.seek(data_sz, os.SEEK_CUR)
                    # Sparse seek (creates a hole in raw ext4)
                    dst.seek(chunk_sz * blk_sz, os.SEEK_CUR)
                elif chunk_type == CHUNK_TYPE_CRC32:
                    if data_sz > 0:
                        src.seek(data_sz, os.SEEK_CUR)
                else:
                    raise ValueError(f"Unknown chunk type: {hex(chunk_type)} at chunk {c_idx}")
                
                if (c_idx + 1) % 500 == 0 or (c_idx + 1) == total_chunks:
                    print(f"[*] Processed {c_idx + 1}/{total_chunks} chunks...", end="\r", flush=True)

            # Ensure file reaches full size if last chunk was DONT_CARE
            cur_pos = dst.tell()
            expected_sz = total_blks * blk_sz
            if cur_pos < expected_sz:
                dst.truncate(expected_sz)

        print(f"\n[+] Successfully converted to raw image: {dst_path} ({os.path.getsize(dst_path)} bytes)")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <input.img> <output.raw.img>")
        sys.exit(1)
    simg2img(sys.argv[1], sys.argv[2])

