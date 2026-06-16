; EEPROM02.asm
;
; A serial port controlled EEPROM programmer designed to write to ROM for
; 6502 and similar computer types. The PIC is controlled by the serial port and
; writes data to the ROM chip. The ultimate intent is to have this program
; controlled by an x86 program through the USART, which will take assembled
; programs from the PC and load them into the EEPROM.
; Based on the MPASM assembler

	LIST	    P=16F877A
	#include    <P16F877A.inc>
	
	__CONFIG _CP_OFF & _WDT_OFF & _PWRTE_ON & _XT_OSC & _LVP_OFF
	
	CBLOCK 0x20		    ; total available space - 32 bytes
	    D1			    ; in block 0 of memory.
            D2
            D3
            Databyte
	    AddressL
	    AddressH
	    Temp
	    Temp2
	    MsgIndex
	    MsgNumber
	    DataIndex
	    WriteSuccess
	    DeviceSize
	    BlockSize
	    InputPtr
	    PlaceHolder
	    InputBuffer0	    ; buffer starting at 0x30
	ENDC
	
	CBLOCK 0x40		    ; 64 bytes for page write
	    BlockBuffer0
	ENDC
	
	ORG 0x0000
	GOTO START
	
	ORG 0x0004
	
	#include    "USART.asm"
	#include    "EEPROM.asm"
	
; Program flow:
;
; 1) initialize USART, initialize GPIO registers, show a prompt, wait for a key

; File Register use
;
; PORTA(0): address bit A14
; PORTA(1): Write Enable
; PORTA(2): Chip Enable
; PORTA(3): Output Enable
; PORTB: address bits A0 - A7
; PORTC(0-5): A8-A13
; PORTD: data bus bits D0-D7
;
; Serial port commands
;
; A - "Address" enters the address in ROM to perform functions
; B - "Block Write ROM" writes a block of up to 64 bytes into ROM
; D - "Dump" displays entire ROM contents on the serial monitor
; F - "Fill" writes a specified byte to all ROM locations
; H - "Help" displays a help menu with commands, syntax, and function
; L - "Lock" enables software data protection
; P - "Page" loads data into memory to be written by Block Write
; R - "Read ROM" reads ROM and displays it on the serial monitor
; S - "Size" sets the size of the ROM in kB. Must be done first
; U - "Unlock" disables software data protection
; W - "Write ROM" writes a single byte to ROM
; + - "Increment Address" increases the address by one
; - - "Decrement Address" decreases the address by one
	
START:
    BCF		STATUS, RP1	    ; set memory bank 1
    BSF		STATUS, RP0
    CLRF	TRISA		    ; set PORTA to output
    CLRF	TRISB		    ; set PortB to output
    CLRF	TRISD		    ; set PortD to output
    MOVLW	0x80		    ; set PortC to output except RC7
    MOVWF	TRISC		    ; configure PORTC
    MOVLW	0x06		    ; configure ADCON1
    MOVWF	ADCON1		    ; all A/D ports are digital ports
    BCF		STATUS, 6	    ; set memory bank 0
    BCF		STATUS, 5
    BSF		PORTA, 1	    ; set control bits /WE, /CE, /OE
    BSF		PORTA, 2	    ; to initial states of high
    BSF		PORTA, 3
    CLRF	InputPtr	    ; Pointer = 0
    MOVLW	0x30		    ; establish pointer to input buffer
    MOVWF	FSR
    CALL	USART_Init	    ; initiate serial port functions
    MOVLW	0x05		    ; dictate 5 mS delay
    MOVWF	D1		    ; and set it into memory
    CALL	EEPROM_msDelay	    ; call a delay function using D1
    MOVLW	0x01		    ; select message one
    CALL	TextMessage	    ; display it
    
LOOP:
    ; Program flow:
    ;
    ; 1) get a key press from the serial port
    ; 2) check it for several special characters
    ;	a. if key was ENTER, parse and execute the command in the key buffer
    ;   b. if key was BACKSPACE or DELETE, decrement the buffer pointer by one,
    ;      move backward one on the screen, print a space, and backspace again.
    ;   c. if key was SPACE, '+', or '-', handle like a valid input (see below)
    ; 3) check for valid alphanumeric input
    ;   a. reject all other characters below ASCII '0'
    ;   b. accept any characters between '0' and '9'
    ;   c. reject any characters between '9' and 'A'
    ;   d. accept any characters between 'A' and 'Z'
    ;   e. reject any characters above 'z'
    ;   f. accept any characters between 'a' and 'z', convert to upper case
    ;
    ; 4) process invalid input - do not add to the buffer. Display a message
    ;    and move to the next line to try again
    ; 5) process valid input - add character to the buffer and echo on terminal.
    ; 6) update buffer - increment buffer pointer. If it equals 8, input is
    ;    too long and we need to try again. This does not happen if the last
    ;    character of the buffer is the enter key.
    ; 

    ; get a key press and save it to memory    
    CALL	USART_GetByte	    
    MOVWF	DataByte	    

    ; was the key press enter?
    XORLW	0x0D		    
    BTFSC	STATUS, 2	    
    GOTO	Input_Enter
    
    ; backspace?
    MOVF	DataByte, W	    
    XORLW	0x08		    
    BTFSC	STATUS, 2	    
    GOTO	Input_Backspace
    
    ; delete? (handled like backspace)
    MOVF	DataByte, W
    XORLW	0x7F		    
    BTFSC	STATUS, 2
    GOTO	Input_Backspace
    
    ; space?
    MOVF	DataByte, W
    XORLW	0x20
    BTFSC	STATUS, 2
    GOTO	Input_Valid
    
    ; '+' character? (increment address)
    MOVF	DataByte, W
    XORLW	0x2B
    BTFSC	STATUS, 2
    GOTO	Input_Valid
    
    ; '-' character? (decrement address)
    MOVF	DataByte, W
    XORLW	0x2D
    BTFSC	STATUS, 2
    GOTO	Input_Valid
    
    ; character below ascii '0'?
    MOVF	DataByte, W
    SUBLW	0x2F		    
    BTFSC	STATUS, 0	    
    GOTO	Input_Invalid	    
    
    ; character between ascii '0'-'9'?
    MOVF	DataByte, W
    SUBLW	0x39
    BTFSC	STATUS, 0
    GOTO	Input_Valid

    ; character below ascii 'A'?
    MOVF	DataByte, W
    SUBLW	0x40
    BTFSC	STATUS, 0
    GOTO	Input_Invalid
    
    ; character between ascii 'A'-'Z'?
    MOVF	DataByte, W
    SUBLW	0x5A
    BTFSC	STATUS, 0
    GOTO	Input_Valid
    
    ; character above ascii 'z'?
    MOVF	DataByte, W
    SUBLW	0x7A
    BTFSS	STATUS, 0
    GOTO	Input_Invalid

    ; character between ascii 'a'-'z'? Convert lower case to upper case
    MOVF	DataByte, W
    SUBLW	0x60
    BTFSS	STATUS, 0
    GOTO	Input_Lowercase    
    
    GOTO	Input_Invalid
    
Input_Invalid:
    ; display an error message, go to the next line, try again
    CALL	USART_SendCRLF
    MOVLW	0x80
    CALL	TextMessage
    MOVLW	0x81
    CALL	TextMessage
    GOTO	LOOP

Input_Lowercase:
    MOVLW	0xDF			; create a bit mask '11011111'
    ANDWF	DataByte, F		; mask out bit 5
    GOTO	Input_Valid		; process letter
    
Input_Valid:
    ; handle an alphanumeric input
    MOVLW	0x30			; point to the input buffer
    ADDWF	InputPtr, W		; add an offset
    MOVWF	FSR			; transfer contents to indirect pointer
    MOVF	DataByte, W		; retrieve the character
    CALL	USART_SendByte		; print it on the screen
    MOVWF	INDF			; store it in the buffer
    GOTO	Update_Buffer
    
Input_Enter:
    ; handle an enter key press - pass to the command handlers
    MOVLW	0x30			; point to the input buffer
    ADDWF	InputPtr, W		; add an offset
    MOVWF	FSR			; transfer contents to indirect pointer
    MOVLW	0x00			; load a null character
    MOVWF	INDF			; into the last spot in the input buffer
    GOTO	Command_Handler
    
Input_Backspace:
    ; handle a backspace or delete press
    MOVF	InputPtr, W
    XORLW	0x00
    BTFSS	STATUS, 2
    GOTO	Input_Backspace1
    CALL	USART_SendCRLF		; if cursor is at zero, just start
    GOTO	LOOP			; a new line and keep going
Input_Backspace1:			; InputPtr was not zero
    DECF	InputPtr, F
    MOVLW	0x30
    ADDWF	InputPtr, W
    MOVWF	FSR
    CLRF	INDF
    MOVLW	0x08			; echo backspace
    CALL	USART_SendByte
    MOVLW	0x20			; echo space to erase character
    CALL	USART_SendByte
    MOVLW	0x08			; echo backspace again to move cursor
    CALL	USART_SendByte		
    GOTO	LOOP			; begin again
    
Update_Buffer:
    INCF	InputPtr, F		; update buffer pointer
    MOVF	InputPtr, W		; get it in W register
    XORLW	0x09			; check if it is 9
    BTFSS	STATUS, 2
    GOTO	LOOP			; if not, go back and read next char
    CLRF	InputPtr
    CALL	USART_SendCRLF		; start on new line
    MOVLW	0x80			; 
    CALL	TextMessage		; display error - input too long
    MOVLW	0x82
    CALL	TextMessage
    GOTO	LOOP			; go back to input routine
    
Command_Handler:
    ; find the first character in the input buffer that is a valid command
    ; if it is space, move to the next without doing anything
    ; if it is a command, handle that command and then go back to the beginning
    ; if it is a null or the ninth character, error out and go back to LOOP
    
    CLRF	InputPtr		; make input pointer zero
    MOVLW	0x30			; start at the beginnning of the buffer
Command_Handler_Loop:
    MOVWF	FSR			; load W into the indirect pointer
    MOVF	INDF, W			; get a byte from the input buffer in W
    MOVWF	DataByte		; save it in memory
    XORLW	' '			; is the character space?
    BTFSC	STATUS, 2
    GOTO	Command_Handler_Next	; if it is, bump forward and read next

    MOVF	DataByte, W		; retrieve the letter stored in memory
    XORLW	'A'			; is it A?
    BTFSC	STATUS, 2
    GOTO	Command_Handler_Address	; handle address function
    
    MOVF	DataByte, W
    XORLW	'B'
    BTFSC	STATUS, 2
    GOTO	Command_Handler_Block	; handle block write function
    
    MOVF	DataByte, W
    XORLW	'D'
    BTFSC	STATUS, 2
    GOTO	Command_Handler_Display	; handle display all memory function
    
    MOVF	DataByte, W
    XORLW	'F'
    BTFSC	STATUS, 2
    GOTO	Command_Handler_Fill	; handle fill ROM function
    
    MOVF	DataByte, W
    XORLW	'H'
    BTFSC	STATUS, 2
    GOTO	Command_Handler_Help	; handle help function
    
    MOVF	DataByte, W
    XORLW	'L'
    BTFSC	STATUS, 2
    GOTO	Command_Handler_Lock	; handle lock SDP function
    
    MOVF	DataByte, W
    XORLW	'P'
    BTFSC	STATUS, 2
    GOTO	Command_Handler_Page	; handle page load function

    MOVF	DataByte, W
    XORLW	'R'
    BTFSC	STATUS, 2
    GOTO	Command_Handler_Read	; handle read data function

    MOVF	DataByte, W
    XORLW	'S'
    BTFSC	STATUS, 2
    GOTO	Command_Handler_Size	; handle size specify function
    
    MOVF	DataByte, W
    XORLW	'U'
    BTFSC	STATUS, 2
    GOTO	Command_Handler_Unlock	; handle unlock SDP function
    
    MOVF	DataByte, W
    XORLW	'W'
    BTFSC	STATUS, 2
    GOTO	Command_Handler_Write	; handle write byte function
    
    MOVF	DataByte, W
    XORLW	'+'
    BTFSC	STATUS, 2
    GOTO	Command_Handler_Inc	; handle increment address function
    
    MOVF	DataByte, W
    XORLW	'-'
    BTFSC	STATUS, 2
    GOTO	Command_Handler_Dec	; handle decrement address function

    GOTO	Input_Invalid		; go to beginning if input not found

Command_Handler_Help:
    INCF	InputPtr, F		; bump the input pointer up by one
    MOVLW	0x30
    ADDWF	InputPtr, W		; make W a pointer to the next char
    MOVWF	FSR
    MOVF	INDF, W			; get the character into W
    XORLW	0x00			; is W = null?
    BTFSC	STATUS, 2		; zero flag set if it is
    GOTO	Command_Handler_Help_H	; basic help message - no arguments
    XORLW	' '			; check if it is space
    BTFSC	STATUS, 2		; if next character is not space or 0
    GOTO	Input_Invalid		; input is invalid. Try again nerd
    INCF	InputPtr, F
    MOVLW	0x30
    ADDWF	InputPtr, W		; same as before - calculate address
    MOVWF	FSR			; and get the next character from the
    MOVF	INDF, W			; input buffer
    MOVWF	DataByte		; save the character in memory
    
    XORLW	0x00
    BTFSC	STATUS, 2
    GOTO	Input_Invalid
    
    MOVF	DataByte, W
    XORLW	'A'
    BTFSC	STATUS, 2
    GOTO	Command_Handler_Help_A
    
    MOVF	DataByte, W
    XORLW	'B'
    BTFSC	STATUS, 2
    GOTO	Command_Handler_Help_B
    
    MOVF	DataByte, W
    XORLW	'D'
    BTFSC	STATUS, 2
    GOTO	Command_Handler_Help_D

    MOVF	DataByte, W
    XORLW	'F'
    BTFSC	STATUS, 2
    GOTO	Command_Handler_Help_F
    
    MOVF	DataByte, W
    XORLW	'H'
    BTFSC	STATUS, 2
    GOTO	Command_Handler_Help_H

    MOVF	DataByte, W
    XORLW	'L'
    BTFSC	STATUS, 2
    GOTO	Command_Handler_Help_L

    MOVF	DataByte, W
    XORLW	'P'
    BTFSC	STATUS, 2
    GOTO	Command_Handler_Help_P

    MOVF	DataByte, W
    XORLW	'R'
    BTFSC	STATUS, 2
    GOTO	Command_Handler_Help_R

    MOVF	DataByte, W
    XORLW	'S'
    BTFSC	STATUS, 2
    GOTO	Command_Handler_Help_S

    MOVF	DataByte, W
    XORLW	'U'
    BTFSC	STATUS, 2
    GOTO	Command_Handler_Help_U

    MOVF	DataByte, W
    XORLW	'W'
    BTFSC	STATUS, 2
    GOTO	Command_Handler_Help_W

    MOVF	DataByte, W
    XORLW	'+'
    BTFSC	STATUS, 2
    GOTO	Command_Handler_Help_PLUS

    MOVF	DataByte, W
    XORLW	'-'
    BTFSC	STATUS, 2
    GOTO	Command_Handler_Help_MINUS
    
    GOTO	Input_Invalid			; help command not found

Command_Handler_Help_A:
    ; template for help message - display the needed message and then
    ; go back to the loop
    MOVLW	0x03
    CALL	TextMessage
    GOTO	LOOP     
    
Command_Handler_Help_H:
    ; template for help message - display the needed message and then
    ; go back to the loop
    MOVLW	0x02
    CALL	TextMessage
    GOTO	LOOP    
    
Command_Handler_Lock:
    CALL	EEPROM_SDP_On
    ; display message stating we turned on SDP
    GOTO	LOOP
    
Command_Handler_Unlock:
    CALL	EEPROM_SDP_Off
    ; display message stating we turned off SDP
    GOTO	LOOP
    
Command_Handler_Inc:
    CALL	EEPROM_IncrementAddress
    BTFSC	STATUS, 0		; if carry flag is set, we overflowed
    GOTO	Command_Handler_IncFail
    ; display message outputting new address
    ; and return to the main loop
    GOTO	LOOP
Command_Handler_IncFail:
    ; revert address and then display a message, go back to main loop
    GOTO	LOOP
    
Command_Handler_Dec:
    CALL	EEPROM_DecrementAddress
    BTFSC	STATUS, 0		; if carry flag is set, we underflowed
    GOTO	Command_Handler_DecFail
    ; display message outputting new address
    ; and return to the main loop
    GOTO	LOOP
Command_Handler_DecFail:
    ; revert address and display a message, go back to main loop
    GOTO	LOOP
    
Command_Handler_Next:
    INCF	InputPtr, F		; point to the next character
    MOVF	InputPtr, W		; save it in W
    XORLW	0x08			; is it 8?
    BTFSC	STATUS, 2
    GOTO	Command_Handler_End	; last byte of buffer, go back to start
    MOVLW	0x30			; otherwise, make W the pointer again
    ADDWF	InputPtr, W		; and add the updated offset
    GOTO	Command_Handler_Loop	; go back to loop and try again
        
; the next routine handles a large amount of text written into ROM. It selects
; a message we want to display on the serial monitor and prints it, one
; character at a time. Because of the way ROM is stored on the PIC, we store
; text messages with a long string of RETLW BYTE commands. Because of the way
; PCL and PCLATH are modified, the maximum size of a text string is 254 bytes,
; plus the ADDWF PCL, W and RETLW 0x00 commands, both of which are needed to
; perform this function. Larger strings must be sent as two separate messages.
;
; subroutine function:
; (1) set a counter, MsgIndex, to zero
; (2) save the message number passed in the W register to memory in MsgNumber
; (3) check if the W register is any given message number. If one is detected,
;     preload the ROM page that message is in. Load the counter into W and
;     call the subroutine for that command. The subroutine adds W to the PCL,
;     which skips over W RETLW commands and chooses the next one. 
; (4) in the end of the routine, we check if the character is null (0x00) and
;     end the routine if it is.
; (5) if the character is not 0, print it on the serial port.
; (6) increment the MsgIndex counter
; (7) load the message number back into W from MsgNumber
; (8) go to the beginning of the loop (step 3) and do it until we find 0x00
;   
; message numbers
; #1 - power on message, displays at start
; #2 - general help message, displays list of commands
; #80 - Error message prefix
; #81 - Invalid input error
; #82 - Excessive input error
    
TextMessage:
    CLRF	MsgIndex	    ; clear the counter used to display text 
    MOVWF	MsgNumber	    ; store the message number we're calling
TextMessageLoop:
    ; start message - displayed when program loads
    XORLW	0x01		    ; check for message #1
    BTFSS	STATUS, 2	    ; is zero flag set?
    GOTO	TextMessageLoop01   ; if not, check the next message
    MOVLW	0x04		    ; preload the page our message is on
    MOVWF	PCLATH		    ; into PCLATH
    MOVF	MsgIndex, W	    ; load character counter into W
    CALL	StartMsgText	    ; get a string character into W
    GOTO	TextMessageLoopEnd  ; proceed to printing it
TextMessageLoop01:
    ; displays when 'H' is entered without argument - displays list of commands
    MOVF	MsgNumber, W
    XORLW	0x02		    ; check for message #2
    BTFSS	STATUS, 2	    ; is zero flag set?
    GOTO	TextMessageLoop02   ; if not, check the next message
    MOVLW	0x04		    ; preload the page our message is on
    MOVWF	PCLATH		    ; into PCLATH
    MOVF	MsgIndex, W	    ; load character counter into W
    CALL	HelpMsgHText	    ; get a string character into W
    GOTO	TextMessageLoopEnd  ; proceed to printing it
TextMessageLoop02:
    ; Error prefix - starts with "ERROR - " when an error is encountered
    MOVF	MsgNumber, W
    XORLW	0x80		    ; check for message #80
    BTFSS	STATUS, 2	    ; is zero flag set?
    GOTO	TextMessageLoop03   ; if not, check the next message
    MOVLW	0x05		    ; preload the page our message is on
    MOVWF	PCLATH		    ; into PCLATH
    MOVF	MsgIndex, W	    ; load character counter into W
    CALL	HelpMsgHText	    ; get a string character into W
    GOTO	TextMessageLoopEnd  ; proceed to printing it
TextMessageLoop03:
    ; Error message that displays when an invalid input happens
    MOVF	MsgNumber, W
    XORLW	0x81		    ; check for message #81
    BTFSS	STATUS, 2	    ; is zero flag set?
    GOTO	TextMessageLoop04   ; if not, check the next message
    MOVLW	0x05		    ; preload the page our message is on
    MOVWF	PCLATH		    ; into PCLATH
    MOVF	MsgIndex, W	    ; load character counter into W
    CALL	HelpMsgHText	    ; get a string character into W
    GOTO	TextMessageLoopEnd  ; proceed to printing it
TextMessageLoop04:
    ; Error message that displays when too many characters are input
    MOVF	MsgNumber, W
    XORLW	0x82		    ; check for message #82
    BTFSS	STATUS, 2	    ; is zero flag set?
    GOTO	TextMessageLoop05   ; if not, check the next message
    MOVLW	0x05		    ; preload the page our message is on
    MOVWF	PCLATH		    ; into PCLATH
    MOVF	MsgIndex, W	    ; load character counter into W
    CALL	HelpMsgHText	    ; get a string character into W
    GOTO	TextMessageLoopEnd  ; proceed to printing it
TextMessageLoop05:
    ; displays help for 'A' command
    MOVF	MsgNumber, W
    XORLW	0x03		    ; check for message #3
    BTFSS	STATUS, 2	    ; is zero flag set?
    GOTO	TextMessageLoop06   ; if not, check the next message
    MOVLW	0x04		    ; preload the page our message is on
    MOVWF	PCLATH		    ; into PCLATH
    MOVF	MsgIndex, W	    ; load character counter into W
    CALL	HelpMsgAText	    ; get a string character into W
    GOTO	TextMessageLoopEnd  ; proceed to printing it
TextMessageLoop06:
    ; displays help for 'B' command
    MOVF	MsgNumber, W
    XORLW	0x04		    ; check for message #4
    BTFSS	STATUS, 2	    ; is zero flag set?
    GOTO	TextMessageLoop07   ; if not, check the next message
    MOVLW	0x04		    ; preload the page our message is on
    MOVWF	PCLATH		    ; into PCLATH
    MOVF	MsgIndex, W	    ; load character counter into W
    CALL	HelpMsgBText	    ; get a string character into W
    GOTO	TextMessageLoopEnd  ; proceed to printing it    
    
    RETURN				; in case we don't find a match
TextMessageLoopEnd:
    XORLW	0x00			; check for null character
    BTFSC	STATUS, 2		; exit routine if we find one
    RETURN
    CALL	USART_SendByte		; print the character to serial port
    INCF	MsgIndex, F		; counter ++
    MOVF	MsgNumber, W		; reclaim the message number
    GOTO	TextMessageLoop		; do it again
    
; The end of program code. What follows is text data for messages to be
; displayed over the serial port. Each message must not cross over a page
; boundary and must occupy space between 0x__00 and 0x__FF. 

    ORG		0x0400		    ; a page for message text (236 total words)

StartMsgText:			    ; 81 data words, message 01
    ; "PIC16F877A EEPROM Programmer."
    ; "2026 by Jon Edwards."
    ; "Type H for instructions."    
    ADDWF	PCL, F
    RETLW       'P'
    RETLW       'I'
    RETLW       'C'
    RETLW       '1'
    RETLW       '6'
    RETLW       'F'
    RETLW       '8'
    RETLW       '7'
    RETLW       '7'
    RETLW       'A'
    RETLW	' '
    RETLW       'E'
    RETLW       'E'
    RETLW       'P'
    RETLW       'R'
    RETLW       'O'
    RETLW       'M'
    RETLW       ' '
    RETLW       'P'
    RETLW       'r'
    RETLW       'o'
    RETLW       'g'
    RETLW       'r'
    RETLW       'a'
    RETLW       'm'
    RETLW       'm'
    RETLW       'e'
    RETLW       'r'
    RETLW       '.'    
    RETLW	0x0D
    RETLW	0x0A
    RETLW       '2'
    RETLW       '0'
    RETLW       '2'
    RETLW       '6'
    RETLW       ' '
    RETLW       'b'
    RETLW       'y'
    RETLW       ' '
    RETLW       'J'
    RETLW       'o'
    RETLW	'n'
    RETLW       ' '
    RETLW       'E'
    RETLW       'd'
    RETLW       'w'
    RETLW       'a'
    RETLW       'r'
    RETLW       'd'
    RETLW       's'
    RETLW       '.'
    RETLW	0x0D
    RETLW	0x0A
    RETLW       'T'
    RETLW       'y'
    RETLW       'p'
    RETLW       'e'
    RETLW       ' '
    RETLW       'H'
    RETLW       ' '
    RETLW       'f'
    RETLW	'o'
    RETLW       'r'
    RETLW       ' '
    RETLW       'i'
    RETLW       'n'
    RETLW       's'
    RETLW       't'
    RETLW       'r'
    RETLW       'u'
    RETLW       'c'
    RETLW       't'
    RETLW       'i'
    RETLW       'o'
    RETLW       'n'
    RETLW       's'
    RETLW       '.'
    RETLW       0x0D
    RETLW       0x0A
    RETLW	0x00
    
HelpMsgHText:				; 38 data words, message 02
    ; "Commands:"
    ; "A B D F H L P R S U W + -"
    ADDWF	PCL, F
    RETLW	'C'
    RETLW	'o'
    RETLW	'm'
    RETLW	'm'
    RETLW	'a'
    RETLW	'n'
    RETLW	'd'
    RETLW	's'
    RETLW	':'
    RETLW	0x0D
    RETLW	0x0A
    RETLW	'A'
    RETLW	' '
    RETLW	'B'
    RETLW	' '
    RETLW	'D'
    RETLW	' '
    RETLW	'F'
    RETLW	' '
    RETLW	'H'
    RETLW	' '
    RETLW	'L'
    RETLW	' '
    RETLW	'P'
    RETLW	' '
    RETLW	'R'
    RETLW	' '
    RETLW	'S'
    RETLW	' '
    RETLW	'U'
    RETLW	' '
    RETLW	'W'
    RETLW	' '
    RETLW	'+'
    RETLW	' '
    RETLW	'-'
    RETLW	0x0D
    RETLW	0x0A
    RETLW	0x00
    
HelpMsgAText:				; 55 data words, message 03
    ; "A: Address. Usage - A HHLL. Changes current address."
    ADDWF   PCL, F
    RETLW   'A'
    RETLW   ':'
    RETLW   ' '
    RETLW   'A'
    RETLW   'd'
    RETLW   'd'
    RETLW   'r'
    RETLW   'e'
    RETLW   's'
    RETLW   's'
    RETLW   '.'
    RETLW   ' '
    RETLW   'U'
    RETLW   's'
    RETLW   'a'
    RETLW   'g'
    RETLW   'e'
    RETLW   ' '
    RETLW   '-'
    RETLW   ' '
    RETLW   'A'
    RETLW   ' '
    RETLW   'H'
    RETLW   'H'
    RETLW   'L'
    RETLW   'L'
    RETLW   '.'
    RETLW   ' '
    RETLW   'C'
    RETLW   'h'
    RETLW   'a'
    RETLW   'n'
    RETLW   'g'
    RETLW   'e'
    RETLW   's'
    RETLW   ' '
    RETLW   'c'
    RETLW   'u'
    RETLW   'r'
    RETLW   'r'
    RETLW   'e'
    RETLW   'n'
    RETLW   't'
    RETLW   ' '
    RETLW   'a'
    RETLW   'd'
    RETLW   'd'
    RETLW   'r'
    RETLW   'e'
    RETLW   's'
    RETLW   's'
    RETLW   '.'
    RETLW   0x0D
    RETLW   0x0A
    RETLW   0x00
    
HelpMsgBText:			    ; 62 data words, message 04
    ; "B: Block Write. Usage - B NN. Block writes NN bytes to ROM."
    ADDWF   PCL, F
    RETLW   'B'
    RETLW   ':'
    RETLW   ' '
    RETLW   'B'
    RETLW   'l'
    RETLW   'o'
    RETLW   'c'
    RETLW   'k'
    RETLW   ' '
    RETLW   'W'
    RETLW   'r'
    RETLW   'i'
    RETLW   't'
    RETLW   'e'
    RETLW   '.'
    RETLW   ' '
    RETLW   'U'
    RETLW   's'
    RETLW   'a'
    RETLW   'g'
    RETLW   'e'
    RETLW   ' '
    RETLW   '-'
    RETLW   ' '
    RETLW   'B'
    RETLW   ' '
    RETLW   'N'
    RETLW   'N'
    RETLW   '.'
    RETLW   ' '
    RETLW   'B'
    RETLW   'l'
    RETLW   'o'
    RETLW   'c'
    RETLW   'k'
    RETLW   ' '
    RETLW   'w'
    RETLW   'r'
    RETLW   'i'
    RETLW   't'
    RETLW   'e'
    RETLW   's'
    RETLW   ' '
    RETLW   'N'
    RETLW   'N'
    RETLW   ' '
    RETLW   'b'
    RETLW   'y'
    RETLW   't'
    RETLW   'e'
    RETLW   's'
    RETLW   ' '
    RETLW   't'
    RETLW   'o'
    RETLW   ' '
    RETLW   'R'
    RETLW   'O'
    RETLW   'M'
    RETLW   '.'
    RETLW   0x0D
    RETLW   0x0A
    RETLW   0x00    

    ORG		0x500			    ; a page for message text (53 words)
    
ErrorMsgText:
    ; "ERROR - "			    ; 10 data words, message 80
    ADDWF	PCL, F
    RETLW	'E'
    RETLW	'R'
    RETLW	'R'
    RETLW	'O'
    RETLW	'R'
    RETLW	' '
    RETLW	'-'
    RETLW	' '
    RETLW	0x00

InputErrorMsgText:				; 18 data words, message 81
    ; "Invalid input."
    ADDWF	PCL, F
    RETLW	'I'
    RETLW	'n'
    RETLW	'v'
    RETLW	'a'
    RETLW	'l'
    RETLW	'i'
    RETLW	'd'
    RETLW	' '
    RETLW	'i'
    RETLW	'n'
    RETLW	'p'
    RETLW	'u'
    RETLW	't'
    RETLW	'.'
    RETLW	0x0D
    RETLW	0x0A
    RETLW	0x00
    
InputError2MsgText:				; 25 data words, message 82
    ; "8 characters maximum."
    ADDWF	PCL, F
    RETLW	'8'
    RETLW	' '
    RETLW	'c'
    RETLW	'h'
    RETLW	'a'
    RETLW	'r'
    RETLW	'a'
    RETLW	'c'
    RETLW	't'
    RETLW	'e'
    RETLW	'r'
    RETLW	's'
    RETLW	' '
    RETLW	'm'
    RETLW	'a'
    RETLW	'x'
    RETLW	'i'
    RETLW	'm'
    RETLW	'u'
    RETLW	'm'
    RETLW	'.'    
    RETLW	0x0D
    RETLW	0x0A
    RETLW	0x00
    
    END
