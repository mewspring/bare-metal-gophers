package main

import (
	"unsafe"
)

const (
	fbWidth            = 80
	fbHeight           = 25
	fbPhysAddr uintptr = 0xb8000
)

func main() {
	// framebuffer points to the physical memory address of the mapped VGA text
	// buffer.
	fb := unsafe.Slice((*uint16)(unsafe.Pointer(fbPhysAddr)), fbWidth*fbHeight)

	// clear framebuffer.
	clear(fb)

	// print hello world.
	s := "hello world!"
	attr := uint16(2<<4 | 0) // black text; green background
	for i := 0; i < len(s); i++ {
		fb[i] = attr<<8 | uint16(s[i])
	}
}
