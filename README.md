# PIC16-Code-Repository
Code written for PIC16 microcontrollers. All programs are intended to work with x86 and 6502 platforms via serial data transfer. Written in PIC16 assembly with MPLAB X IDE v5.35 and XC8 compiler/assembler. Later programs (Serial02 and on) written with MPASM assembler. Same assembly language with slightly different assembler directives.

FirstAttempt.asm - basic program to test ability to program a PIC from a laptop computer. Flashes some LEDs. Whatever.

Serial01.asm - basic program to test serial port connectivity. Sends 'S' over and over again. Will later be used to demonstrate serial transmission and reception between a PC and PIC microcontroller. Will be crucial when I am using it to program a 6502 computer.

Serial02.asm - an echo program that repeats all characters typed into the terminal. Demonstrates input and output functions.

Serial03.asm - the same function as Serial02 but with a startup message and use of an external library for USART functions.

USART.asm - the basic functions for PIC16F877A serial protocol brought out to a library.
