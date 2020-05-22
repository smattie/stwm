;;; ----------------------------------------------------------------------------
;;; stwm
;;;
;;; This work is free. You can redistribute it and/or modify it under the
;;; terms of the Do What The Fuck You Want To Public License, Version 2,
;;; as published by Sam Hocevar. See the COPYING file for more details.
;;;
;;; 2020/05 - smattie <https://github.com/smattie>
;;; ----------------------------------------------------------------------------

format elf executable 3
entry start

define read    3
define write   4
define socket  359
define connect 362

define PF_UNIX     1
define SOCK_STREAM 1

define ButtonPressMask   04h
define ButtonReleaseMask 08h
define PointerMotionMask 40h

define ShiftMask   01h
define ControlMask 04h
define Mod1Mask    08h
define Mod4Mask    40h
define Button1Mask 100h
define Button3Mask 400h

define KeyPress      2
define KeyRelease    3
define ButtonPress   4
define ButtonRelease 5
define MotionNotify  6

segment readable writable executable
start:
	sub esp, 124
	xor esi, esi

	mov eax, socket
	mov ebx, PF_UNIX
	mov ecx, SOCK_STREAM
	xor edx, edx
	int 80h
	mov ebx, eax
	test eax, eax
	js  .socketerror

	mov eax, connect
	mov ecx, xsocket
	mov  dl, sockaddr_un!size
	int 80h
	test eax, eax
	js  .socketerror

	mov  al, write
	mov ecx, xconnect
	mov  dl, xconnect!size
	int 80h

	;;; read the reply header

	mov eax, read
	mov ecx, esp
	mov  dl, xconnectreply!size
	int 80h
	cmp [esp], byte 1
	jne .xconnerror

	;;; and the rest of the reply

	mov eax, read
	mov  dx, [esp + xconnectreply.length]
	shl edx, 2
	sub esp, edx
	mov ecx, esp
	int 80h

	movzx eax, [esp + xinfo.formatcount]
	movzx edx, [esp + xinfo.vendorlen]
	shl eax, 3
	mov ebp, esp
	add ebp, xinfo!size
	add ebp, eax
	add ebp, edx
	mov edi, [ebp + xscreen.root]

	;;; setup keybindings

	mov [xgrabkey.window], edi
	mov [xgrabbutton.window], edi
	mov [xgrabbutton.button], byte 1
	mov  ax, write
	mov ecx, xgrabkey
	mov  dx, xgrabkey!size + xgrabbutton!size
	int 80h

	mov [xgrabbutton.button], byte 3
	mov eax, write
	mov ecx, xgrabbutton
	mov  dx, xgrabbutton!size
	int 80h

	;;; saving the root id to prime window raising
	mov [xconfigurewindow.window], edi

.eventloop:
	mov eax, read
	mov ecx, esp
	mov edx, 512
	int 80h

	movzx eax, byte [esp]
	mov edi, [esp + keypress.child]

	@@:
	cmp al, KeyPress
	jne @f

		test edi, edi
		jz  .eventloop

		mov eax, [xconfigurewindow.window]
		mov [xconfigurewindow.window], edi

		mov [xconfigurewindow.valuemask], 20h + 40h
		mov [xconfigurewindow.data     ], eax
		mov [xconfigurewindow.data + 4 ], esi

		mov eax, write
		mov ecx, xconfigurewindow
		mov edx, xconfigurewindow!size + 8
		int 80h

		jmp .eventloop

	@@:
	cmp al, ButtonPress
	jne @f

		test edi, edi
		jz  .eventloop

		mov eax, dword [esp + buttonpress.rootx]
		mov [pointer], eax

		mov [xgrabpointer.window], edi
		mov [xgetgeometry.drawable], edi
		mov eax, write
		mov ecx, xgetgeometry
		mov edx, xgetgeometry!size + xgrabpointer!size
		int 80h

		mov eax, read
		mov ecx, esp
		mov edx, 512
		int 80h

		;;; could do a movq if you had a fancy mmx chip
		mov eax, dword [esp + xwindowgeometry.x]
		mov ecx, dword [esp + xwindowgeometry.width]
		mov dword [window.x], eax
		mov dword [window.w], ecx

		;;; save the id for motionnotify
		mov [xconfigurewindow.window], edi
		jmp .eventloop

	@@:
	cmp al, MotionNotify
	jne @f

		;;; get the held button and clear any modifiers

		movzx edx, [esp + motionnotify.state]
		shr edx, 8

		movzx eax, word [esp + motionnotify.rootx]
		movzx ecx, word [esp + motionnotify.rooty]
		sub ax, [pointer.x]
		sub cx, [pointer.y]

		cmp edx, 4
		je .resize

		.move:
		add ax, word [window.x]
		add cx, word [window.y]

		mov  dl, 01h + 02h ;; x, y
		jmp .send

		.resize:
		add ax, word [window.w]
		cmovle eax, edx
		add cx, word [window.h]
		cmovle ecx, edx

		mov  dl, 04h + 08h ;; width, height

		.send:
		mov [xconfigurewindow.valuemask], dx
		mov [xconfigurewindow.data     ], eax
		mov [xconfigurewindow.data + 4 ], ecx

		mov eax, write
		mov ecx, xconfigurewindow
		mov edx, xconfigurewindow!size + 8
		int 80h
		jmp .eventloop

	@@:
	cmp al, ButtonRelease
	jne @f

		mov  al, write
		mov ecx, xungrabpointer
		mov  dx, xungrabpointer!size
		int 80h

	@@:
	jmp .eventloop

.socketerror:
	xor ebx, ebx
	inc ebx
	jmp finish

.xconnerror:
	mov ebx, 2

finish:
	xor eax, eax
	inc eax
	int 80h

window:
	.x dw ?
	.y dw ?
	.w dw ?
	.h dw ?

pointer:
	.x dw ?
	.y dw ?

xgetgeometry:
	.opcode   db 14
	.pad0     db 0
	.length   dw 2
	.drawable dd ?
	xgetgeometry!size = $ - xgetgeometry

xgrabpointer:
	.opcode       db 26
	.ownerevents  db 1
	.length       dw 6
	.window       dd ?
	.eventmask    dw ButtonReleaseMask or PointerMotionMask
	.pointermode  db 1
	.keyboardmode db 1
	.confineto    dd 0
	.cursor       dd 0
	.timestamp    dd 0
	xgrabpointer!size = $ - xgrabpointer

xungrabpointer:
	.opcode    db 27
	.pad0      db 0
	.length    dw 2
	.timestamp dd 0
	xungrabpointer!size = $ - xungrabpointer

xgrabkey:
	.opcode       db 33
	.ownerevents  db 1
	.length       dw 4
	.window       dd ?
	.modifiers    dw Mod1Mask
	.keycode      db 43h
	.pointermode  db 1
	.keyboardmode db 1
	.pad0         rb 3
	xgrabkey!size = $ - xgrabkey

xgrabbutton:
	.opcode       db 28
	.ownerevents  db 1
	.length       dw 6
	.window       dd ?
	.eventmask    dw ButtonPressMask
	.pointermode  db 1
	.keyboardmode db 1
	.confineto    dd 0
	.cursor       dd 0
	.button       db ?
	.pad0         db 0
	.modifiers    dw Mod1Mask
	xgrabbutton!size = $ - xgrabbutton

xconfigurewindow:
	.opcode    db 12
	.pad0      db 0
	.length    dw 3 + 2
	.window    dd ?
	.valuemask dw ?
	.pad1      dw 0
	xconfigurewindow!size = $ - xconfigurewindow
	.data: ;; suck it whatever's next

xconnect:
	.endianess dw 'l'
	.protocol  dd 11
	.auth      dd 0
	.pad       dw 0
	xconnect!size = $ - xconnect

xsocket:
	.sun_family dw PF_UNIX
	.sun_path   db "/tmp/.X11-unix/X0", 0
	.len = $ - xsocket

virtual at 0
	xconnectreply:
	.status rb 1
	.pad0   rb 1
	.major  rw 1
	.minor  rw 1
	.length rw 1
	xconnectreply!size = $
	end virtual

virtual at 0
	xinfo:
	.releasenum    rd 1
	.idbase        rd 1
	.idmask        rd 1
	.motionbufsz   rd 1
	.vendorlen     rw 1
	.maxrequestlen rw 1
	.screencount   rb 1
	.formatcount   rb 1
	.byteorder     rb 1
	.bitorder      rb 1
	.scanlineunit  rb 1
	.scanlinepad   rb 1
	.minkeycode    rb 1
	.maxkeycode    rb 1
	.pad0          rd 1
	xinfo!size = $
	end virtual

virtual at 0
	xscreen:
	.root         rd 1
	.colormap     rd 1
	.white        rd 1
	.black        rd 1
	.inputmask    rd 1
	.width        rw 1
	.height       rw 1
	.widthmm      rw 1
	.heightmm     rw 1
	.minmaps      rw 1
	.maxmaps      rw 1
	.rootvisual   rd 1
	.backingstore rb 1
	.saveunder    rb 1
	.rootdepth    rb 1
	.depthcount   rb 1
	xscreen!size = $
	end virtual

virtual at 0
	xwindowgeometry:
	.reply       rb 1
	.depth       rb 1
	.serial      rw 1
	.length      rd 1
	.root        rd 1
	.x           rw 1
	.y           rw 1
	.width       rw 1
	.height      rw 1
	.borderwidth rw 1
	.pad0        rb 10
	xwindowgeometry!size = $
	end virtual

virtual at 0
	keypress:
	.type       rb 1
	.detail     rb 1
	.serial     rw 1
	.timestamp  rd 1
	.root       rd 1
	.event      rd 1
	.child      rd 1
	.rootx      rw 1
	.rooty      rw 1
	.eventx     rw 1
	.eventy     rw 1
	.state      rw 1
	.samescreen rb 1
	.pad0       rb 1
	keypress!size = $
	end virtual

virtual at 0
	buttonpress:
	.type       rb 1
	.detail     rb 1
	.serial     rw 1
	.timestamp  rd 1
	.root       rd 1
	.event      rd 1
	.child      rd 1
	.rootx      rw 1
	.rooty      rw 1
	.eventx     rw 1
	.eventy     rw 1
	.state      rw 1
	.samescreen rb 1
	.pad0       rb 1
	buttonpress!size = $
	end virtual

virtual at 0
	motionnotify:
	.type       rb 1
	.detail     rb 1
	.serial     rw 1
	.timestamp  rd 1
	.root       rd 1
	.event      rd 1
	.child      rd 1
	.rootx      rw 1
	.rooty      rw 1
	.eventx     rw 1
	.eventy     rw 1
	.state      rw 1
	.samescreen rb 1
	.pad0       rb 1
	motionnotify!size = $
	end virtual

virtual at 0
	sockaddr_un:
	.sun_family rw 1
	.sun_path   rb 108
	sockaddr_un!size = $
	end virtual

;;; vim: set ft=fasm:
