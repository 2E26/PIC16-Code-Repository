# PIC16-Code-Repository
Code written for PIC16 microcontrollers. All programs are intended to work with x86 and 6502 platforms via serial data transfer. Written in PIC16 assembly with MPLAB X IDE v5.35 and XC8 compiler/assembler. Later programs (Serial02 and on) written with MPASM assembler. Same assembly language with slightly different assembler directives.

FirstAttempt.asm - basic program to test ability to program a PIC from a laptop computer. Flashes some LEDs. Whatever.

Serial01.asm - basic program to test serial port connectivity. Sends 'S' over and over again. Will later be used to demonstrate serial transmission and reception between a PC and PIC microcontroller. Will be crucial when I am using it to program a 6502 computer.

Serial02.asm - an echo program that repeats all characters typed into the terminal. Demonstrates input and output functions.

Serial03.asm - the same function as Serial02 but with a startup message and use of an external library for USART functions.

USART.asm - the basic functions for PIC16F877A serial protocol brought out to a library.

EEPROM.asm - a library with EEPROM functions for handling ROM chips in the AT28C256 family.

EEPROM01.asm - the beginnings of an EEPROM programmer library to include a small 6502 program to be written into an AT28C256 EEPROM. Also, added character tables to enable display of text over the serial port with the PIC16.

EEPROM0A.asm - a sample program to read all memory from an AT28C256. A troubleshooting tool more than anything else.

EEPROM02.asm - a complete EEPROM programming application for EEPROM in the AT28C family. Maybe adaptable for EPROM and other ROM types as I become familiar with them.
