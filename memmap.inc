; =====================================================================
;  memmap.inc - constantes del mapa de memoria banked compartidas entre
;  bank.z80, diskio.z80 y el resto del XIOS. Ver memory_map.md para la
;  justificacion completa de cada valor.
; =====================================================================

BANK0_BASE   equ 0    ; pagina fisica del banco 0 en el contexto sistema
BANK1_BASE   equ 8    ; pagina fisica del banco 0 en el contexto usuario
                       ; (la 7 la ocupa la zona comun, fija)

WINBLK       equ 6    ; banco usado como ventana temporal por el driver
                       ; del disco RAM (map1blk)

RAMDISK_BASE equ 15   ; primera pagina fisica del pool del disco RAM
                       ; (paginas 15-63, 49 en total)
