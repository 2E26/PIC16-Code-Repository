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
            DataByte
	    AddressL
	    AddressH
	    Temp
	    Temp2
	    MsgIndex
	    MsgNumber
	    DataIndex
	    WriteSuccess
	    DeviceSize
	    PageSize
	    InputPtr
	    PagePtr
	    InputBuffer0	    ; buffer starting at 0x30
	    InputBuffer1
	    InputBuffer2
	    InputBuffer3
	    InputBuffer4
	    InputBuffer5
	    InputBuffer6
	    InputBuffer7
	    InputBuffer8
	    InByteL
	    InByteH
	ENDC
	
	CBLOCK 0x40		    ; 64 bytes for page write
	    PageBuffer0
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
; Serial port commands (* indicates code is finished for this routine)
;
; A - "Address" enters the address in ROM to perform functions*
; B - "Block Write ROM" writes a block of up to 64 bytes into ROM
; D - "Dump" displays entire ROM contents on the serial monitor*
; F - "Fill" writes a specified byte to all ROM locations*
; H - "Help" displays a help menu with commands, syntax, and function*
; L - "Lock" enables software data protection*
; P - "Page" loads data into memory to be written by Block Write*
; R - "Read ROM" reads ROM and displays it on the serial monitor*
; S - "Size" sets the size of the ROM in kB. Must be done first*
; U - "Unlock" disables software data protection*
; W - "Write ROM" writes a single byte to ROM*
; + - "Increment Address" increases the address by one*
; - - "Decrement Address" decreases the address by one*
	
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
    CLRF	DeviceSize	    ; Size = 0 kB
    CLRF	AddressH	    ; Address starts at 0x0000
    CLRF	AddressL
    CLRF	D1		    ; clear all the other memory 
    CLRF	D2
    CLRF	D3
    CLRF	DataByte
    CLRF	Temp
    CLRF	Temp2
    CLRF	MsgIndex
    CLRF	MsgNumber
    CLRF	DataIndex
    CLRF	WriteSuccess
    CLRF	PageSize
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
    CLRF	InputPtr
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
    CALL	USART_SendCRLF
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
    
    MOVLW	0x30			; start at the beginnning of the buffer
    CLRF	InputPtr		; InputPtr is an offset (starts at 0)
Command_Handler_Loop:
    MOVWF	FSR			; load W into the indirect pointer
    MOVF	INDF, W			; get a byte from the input buffer in W
    MOVWF	DataByte		; save it in memory
    XORLW	0x00			; is the character null?
    BTFSC	STATUS, 2
    GOTO	Command_Handler_End
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
    GOTO	Command_Handler_Dump	; handle display all memory function
    
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
    MOVLW	0x30			; set W to 30h
    ADDWF	InputPtr, W		; add the offset
    MOVWF	FSR			; copy W to the indirect register
    MOVF	INDF, W			; get the character into W
    XORLW	0x00			; is W = null?
    BTFSC	STATUS, 2		; zero flag set if it is
    GOTO	Command_Handler_Help_H	; basic help message - no arguments
    XORLW	' '			; check if it is space
    BTFSS	STATUS, 2		; if next character is not space or 0
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

Command_Handler_Address:
    ; sets the current address to a value entered in hexadecimal
    CALL	Command_Handler_Size_Check	; check if ROM size is set
    BTFSC	STATUS, 0			; carry flag will tell us
    GOTO	Command_Handler_End		; error out if not
    CALL	USART_SendCRLF			; start on a new line
    ; Flow of routine
    ;
    ; 1) increase the buffer pointer to the next character read it into W
    ; 2) if W is null at this point, error out (invalid character)
    ; 3) if W is anything other than a space, error out (invalid character)
    ; 4) read the next characters as hexadecimal digits.
    ; 5) check if address entered is higher than stated maximum ROM size
    ; 6) if ROM size is 64 kB, any address is valid
    ; 7) if address is valid, move it to AddressH:AddressL and write it
    ;    to the appropriate pins
    ; 8) if address is not valid, display a message telling the user so
    ; 9) in either case, return to main command loop
    INCF	InputPtr, F		; bump the input pointer up by one
    MOVLW	0x30			; offset the pointer by 30
    ADDWF	InputPtr, W		; mix the two in W
    MOVWF	FSR			; copy W to the indirect register
    MOVF	INDF, W			; get the character into W
    BTFSC	STATUS, 2		; zero flag set if it is null char
    GOTO	Input_Invalid		; reject input
    XORLW	' '			; check if it is space
    BTFSS	STATUS, 2		; if next character is not space or 0
    GOTO	Input_Invalid		; input is invalid. Try again nerd
    INCF	InputPtr, F		; check character after space to see if
    MOVLW	0x30			; it is a null character. This is to
    ADDWF	InputPtr, W		; reject commands like "A "
    MOVWF	FSR
    MOVF	INDF, W
    BTFSC	STATUS, 2
    GOTO	Input_Invalid
    DECF	InputPtr, F    
    CALL	Text_Hexadecimal
    XORLW	0x00			; check if W is 0 (success!)
    BTFSC	STATUS, 2		; proceed to print character if so
    GOTO	Command_Handler_Address_BoundChk
    MOVWF	DataByte		; save W
    XORLW	0xFD			; check for buffer overrun
    BTFSS	STATUS, 2		; is W = 0xFD?
    GOTO	Input_Invalid		; if not, print invalid input message
    MOVLW	0x80
    CALL	TextMessage
    MOVLW	0x82
    CALL	TextMessage
    CALL	USART_SendCRLF
    GOTO	Command_Handler_End
Command_Handler_Address_BoundChk:
    CALL	EEPROM_BoundCheck
    BTFSC	STATUS, 0
    GOTO	Command_Handler_Address_Invalid	
Command_Handler_Address_Write:
    ; the address is within the allowed range. Write it to the address pins.
    MOVF	InByteH, W
    MOVWF	AddressH
    MOVF	InByteL, W
    MOVWF	AddressL
    CALL	EEPROM_SetAddress
    CALL	USART_SendCRLF
    MOVLW	0x11
    CALL	TextMessage
    MOVF	AddressH, W
    CALL	USART_PrintBytetoChar
    MOVF	AddressL, W
    CALL	USART_PrintBytetoChar
    CALL	USART_SendCRLF
    GOTO	Command_Handler_End
Command_Handler_Address_Invalid:
    ; address is not within the allowed range. Error out with a message.
    MOVLW	0x80
    CALL	TextMessage
    MOVLW	0x86
    CALL	TextMessage
    GOTO	Command_Handler_End
    
Command_Handler_Block:
    ; writes NN bytes from the page into ROM at the current address. Maximum
    ; block write is 64 bytes. Can only start on an address where bits 0-5
    ; are cleared (EG - address low byte is 0b**00 0000)
    CALL	Command_Handler_Size_Check	; check if ROM size is set
    BTFSC	STATUS, 0			; carry flag will tell us
    GOTO	Command_Handler_End		; error out if not
    ; Flow of routine:
    ;
    ; 1) normal checks - ensure ROM size exists, ensure input is valid.
    ; 2) valid input check - is the number entered larger than 255? Is it more
    ;    than 64? Is it larger than PageSize? Is it zero? All of these 
    ;    conditions will result in a specific error which tells the user 
    ;    that data demand exceeds the supply
    ; 3) address check - does the address start at a value divisible by 64?
    ; 4) clear the page pointer
    ; 5) use the current page pointer to point to a byte in the page buffer,
    ;    grab a byte from the page buffer, and write it to EEPROM
    ; 6) increment address, increment the page buffer. See if the page buffer
    ;    equals the page size. If it doesn't, repeat from step 5
    ; 7) if the pointer equals the page size, we are done writing. Delay by
    ;    10 milliseconds to allow the ROM to write to its internal memory.
    ; 8) display a message stating the number of bytes written and where to
    ; 9) if step 2 found that the input byte demand exceeds the amount of bytes
    ;    written in the page buffer, display an error message to indicate that
    ; A) if step 3 found that the address could not support a page write,
    ;    display an error message stating that
    ;
    INCF	InputPtr, F		; bump the input pointer up by one
    MOVLW	0x30			; offset the pointer by 30
    ADDWF	InputPtr, W		; mix the two in W
    MOVWF	FSR			; copy W to the indirect register
    MOVF	INDF, W			; get the character into W
    BTFSC	STATUS, 2		; zero flag set if it is null char
    GOTO	Input_Invalid
    XORLW	' '			; check if it is space
    BTFSS	STATUS, 2		; if next character is not space or 0
    GOTO	Input_Invalid		; input is invalid. Try again nerd
    INCF	InputPtr, F		; check character after space to see if
    MOVLW	0x30			; it is a null character. This is to
    ADDWF	InputPtr, W		; reject commands like "R "
    MOVWF	FSR
    MOVF	INDF, W
    BTFSC	STATUS, 2
    GOTO	Input_Invalid
    DECF	InputPtr, F
    CALL	Text_Decimal
    XORLW	0x00			; check if W is 0 (success!)
    BTFSC	STATUS, 2		; proceed to print character if so
    GOTO	Command_Handler_Block_1
    MOVWF	DataByte		; save W
    XORLW	0xFD			; check for buffer overrun
    BTFSS	STATUS, 2		; is W = 0xFD?
    GOTO	Input_Invalid		; if not, print invalid input message
    MOVLW	0x80
    CALL	TextMessage
    MOVLW	0x82
    CALL	TextMessage
    CALL	USART_SendCRLF
    GOTO	Command_Handler_End
Command_Handler_Block_1:
    ; the most basic input checks have passed. Now we make sure that the input
    ; was a number between 1-64, and it does not exceed the PageSize variable.
    ; if PageSize is at zero, this will also fail and display a distinct error
    ; to remind the user we need to load data into memory before trying to
    ; write it to ROM.
    MOVF	InByteH, F		; did the decimal read result in a
    BTFSS	STATUS, 2		; value in the high byte? Error out.
    GOTO	Input_Invalid
    MOVF	InByteL, W		; load low byte into W. Check if it is
    BTFSC	STATUS, 2		; zero. Error out if zero.
    GOTO	Input_Invalid
    SUBLW	0x40			; check if input was larger than 64
    BTFSS	STATUS, 0		; and error out if it was
    GOTO	Input_Invalid
    MOVF	InByteL, W
    SUBWF	PageSize, W		; compare W and page size. If page
    BTFSS	STATUS, 0		; size is less than W, specific error
    GOTO	Command_Handler_Block_5
Command_Handler_Block_1.5:
    ; now we need to ensure that the current address is correct. To write to
    ; a block, we need to start at an address that is divisible by 64. That is,
    ; the low byte of the address must have bits 0-5 clear. There should be a
    ; distinct error message if the address is not valid.
    MOVF	AddressL, W
    ANDLW	0x3F
    BTFSS	STATUS, 2
    GOTO	Command_Handler_Block_6
Command_Handler_Block_2:
    ; the input is valid. Initialize the variables we need to write our data to
    ; ROM.
    CLRF	PagePtr
    BSF		STATUS, RP0			; set PORTD to output
    BCF		STATUS, RP1
    CLRF	TRISD
    BCF		STATUS, RP0
    BCF		STATUS, RP1
Command_Handler_Block_3:
    ; set up the indirect register to point to a certain variable in the page
    ; buffer. Withdraw a byte from it and write it to ROM.
    MOVLW	0x40			
    ADDWF	PagePtr, W
    MOVWF	FSR
    MOVF	INDF, W
    CALL	EEPROM_WriteByte
    CALL	EEPROM_IncrementAddress
    INCF	PagePtr, F
    MOVF	PagePtr, W
    XORWF	InByteL, W
    BTFSS	STATUS, 2
    GOTO	Command_Handler_Block_3
Command_Handler_Block_4:
    ; the code falls through to this part once all of the bytes have been
    ; written to ROM
    MOVLW	0x0A
    MOVWF	D1
    CALL	EEPROM_msDelay
Command_Handler_Block_4.5:
    ; after the delay to allow EEPROM to write data, we display a message
    ; and return control to the user.
    MOVF	InByteL, W		    ; print number of bytes
    CALL	Decimal_Text
    MOVLW	0x1E
    CALL	TextMessage
    MOVF	AddressH, W		    ; print current address
    CALL	USART_PrintBytetoChar	    ; after block write
    MOVF	AddressL, W
    CALL	USART_PrintBytetoChar
    CALL	USART_SendCRLF
    GOTO	Command_Handler_End   
Command_Handler_Block_5:
    ; this code executes if the number of bytes to block-write entered is
    ; greater than the number of bytes in the page.
    MOVLW	0x80
    CALL	TextMessage
    MOVLW	0x86
    CALL	TextMessage
    GOTO	Command_Handler_End
Command_Handler_Block_6:
    ; this code executes if the address is not valid for a block write. It
    ; can only start on the beginning of a 64-byte page in ROM.
    MOVLW	0x80
    CALL	TextMessage
    MOVLW	0x87
    CALL	TextMessage
    GOTO	Command_Handler_End
    
Command_Handler_Dump:
    ; sets address to zero and displays contents of entire ROM in 32 byte lines
    CALL	Command_Handler_Size_Check	; check if ROM size is set
    BTFSC	STATUS, 0			; carry flag will tell us
    GOTO	Command_Handler_End		; error out if not
    CALL	USART_SendCRLF			; start on a new line
    ; Flow of routine:
    ; 
    ; 1 - initialize variables. Set PORTD to input, copy DeviceSize to an
    ;     unused byte D1, and zeroize Address low and high.
    ; 2 - print "0x" at the beginning of the line, followed by AddressL and
    ;     AddressH, then a ": ".
    ; 3 - read a byte from EEPROM at current address. Print the byte followed
    ;     by a space. Increment address.
    ; 4 - 1024 check: get the low address byte in W, AND with 0xFF. Zero flag is
    ;     clear unless W is 0x00. If zero flag is set, get high address byte
    ;     in W, AND with 0x03. If either of the first two bits of that byte are
    ;     set, the address is not divisible by 1024 (e.g., 0x400, 0x800, etc)
    ; 5 - if Address is divisible by 1024, we decrement D1 by one. If the
    ;     decrement results in a zero, we are done reading and displaying all
    ;     bytes in ROM. Otherwise, we go back to step 2 and go again.
    ; 6 - 32 check: get the low address byte in W, AND with 0x3F. This returns
    ;     a zero flag if the low byte is divisible by 32, so repeat step 2. If
    ;     zero flag is clear, repeat step 3.
    BSF		STATUS, RP0			; set PORTD to input
    BCF		STATUS, RP1
    MOVLW	0xFF
    MOVWF	TRISD
    BCF		STATUS, RP0
    BCF		STATUS, RP1
    MOVF	DeviceSize, W
    MOVWF	D1				; D1 is a counter of kB
    CLRF	AddressH
    CLRF	AddressL
    CALL	EEPROM_SetAddress
Command_Handler_Dump_Loop01:
    MOVLW	'0'				; start every line by
    CALL	USART_SendByte			; printing "0x" followed by
    MOVLW	'x'				; the address and ":".
    CALL	USART_SendByte
    MOVF	AddressH, W
    CALL	USART_PrintBytetoChar
    MOVF	AddressL, W
    CALL	USART_PrintBytetoChar
    MOVLW	':'
    CALL	USART_SendByte
    MOVLW	' '
    CALL	USART_SendByte
Command_Handler_Dump_Loop02:
    CALL	EEPROM_ReadByte			; get one byte from ROM
    CALL	USART_PrintBytetoChar		; print it to the monitor
    MOVLW	' '				; follow up with a space
    CALL	USART_SendByte			
    CALL	EEPROM_IncrementAddress		; move up one in ROM
    BTFSC	STATUS, 0			; check if carry flag is set
    GOTO	Command_Handler_Dump_Loop_End
    MOVF	AddressL, W			; 1024 check - see if we need			
    BTFSS	STATUS, 2			; to roll over a kilobyte
    GOTO	Command_Handler_Dump_Loop03	; skip to 32 check
    MOVF	AddressH, W
    ANDLW	0x03
    BTFSS	STATUS, 2
    GOTO	Command_Handler_Dump_Loop03	; skip to 32 check
    DECFSZ	D1, F
    GOTO	Command_Handler_Dump_Loop01	; go to new line and go again
    GOTO	Command_Handler_Dump_Loop_End	; if D1 = 0, end function
Command_Handler_Dump_Loop03:
    MOVF	AddressL, W
    ANDLW	0x1F
    BTFSS	STATUS, 2
    GOTO	Command_Handler_Dump_Loop02
    CALL	USART_SendCRLF
    GOTO	Command_Handler_Dump_Loop01
Command_Handler_Dump_Loop_End:
    CALL	USART_SendCRLF
    GOTO	Command_Handler_End
    
Command_Handler_Fill:
    CALL	Command_Handler_Size_Check	; check if ROM size is set
    BTFSC	STATUS, 0			; carry flag will tell us
    GOTO	Command_Handler_End		; error out if not
    CALL	USART_SendCRLF			; start on a new line
    ; this procedure reads a single byte in the command line and validates
    ; the input. Then it prompts the user to confirm the fill. A 'Y' or 'y'
    ; press executes the fill. Anything else cancels.
    ;
    ; routine flow:
    ;
    ; 1) perform usual checks for validating input. If the input is anything
    ;    other than "F xx", the check fails and we end up leaving the routine
    ; 2) display a message prompting the user to confirm they want to fill
    ;    the entire EEPROM with the given byte. Wait for an input. If it is
    ;    anything other than 'Y' or 'y', go back to the main loop
    ; 3) set PORTD to output, clear current address, and copy DeviceSize to
    ;    InByteH
    ; 4) put the fill byte in W and write it to the ROM
    ; 5) increment the address. If it overflowed, error out
    ; 6) check if address is divisible by 64 (logical AND with 0x3F, check for
    ;    zero result). If so, go to a delay routine so the EEPROM can write
    ;    the page. If not, go back to #4
    ; 7) after waiting the 10 mS, check if the address is divisible by 1024. If
    ;    so, decrement D1 (we crossed into another kB of space). If D1 is zero,
    ;    we have finished writing to ROM and can be finished.
    ;
    INCF	InputPtr, F		; bump the input pointer up by one
    MOVLW	0x30			; offset the pointer by 30
    ADDWF	InputPtr, W		; mix the two in W
    MOVWF	FSR			; copy W to the indirect register
    MOVF	INDF, W			; get the character into W
    BTFSC	STATUS, 2		; zero flag set if it is null char
    GOTO	Input_Invalid		; reject input
    XORLW	' '			; check if it is space
    BTFSS	STATUS, 2		; if next character is not space or 0
    GOTO	Input_Invalid		; input is invalid. Try again nerd
    INCF	InputPtr, F		; check character after space to see if
    MOVLW	0x30			; it is a null character. This is to
    ADDWF	InputPtr, W		; reject commands like "A "
    MOVWF	FSR
    MOVF	INDF, W
    BTFSC	STATUS, 2
    GOTO	Input_Invalid
    DECF	InputPtr, F    
    CALL	Text_Hexadecimal
    XORLW	0x00			; check if W is 0 (success!)
    BTFSC	STATUS, 2		; proceed to print character if so
    GOTO	Command_Handler_Fill_Check
    MOVWF	DataByte		; save W
    XORLW	0xFD			; check for buffer overrun
    BTFSS	STATUS, 2		; is W = 0xFD?
    GOTO	Input_Invalid		; if not, print invalid input message
    MOVLW	0x80
    CALL	TextMessage
    MOVLW	0x82
    CALL	TextMessage
    CALL	USART_SendCRLF
    GOTO	Command_Handler_End
Command_Handler_Fill_Check:
    ; check to ensure the input was only a single byte
    MOVF	InByteH, F
    BTFSS	STATUS, 2
    GOTO	Input_Invalid
Command_Handler_Fill_Prompt:
    ; display a prompt to ensure the user really wants to fill the entire ROM
    ; with only one value. Essentially, "Are you sure? (Y/N)"
    CALL	USART_SendCRLF
    MOVF	InByteL, W		; print the address
    CALL	USART_PrintBytetoChar
    MOVLW	0x16
    CALL	TextMessage
    MOVF	DeviceSize, W
    CALL	Decimal_Text
    MOVLW	0x17
    CALL	TextMessage
    MOVLW	0x18
    CALL	TextMessage
    CALL	USART_GetByte		; get a character from the keyboard
    ANDLW	0xDF			; convert to upper case
    XORLW	0x59			; check if it is 'Y'
    BTFSC	STATUS, 2		; if so, move on to the function
    GOTO	Command_Handler_Fill_Go
    MOVLW	0x19
    CALL	TextMessage
    GOTO	Command_Handler_End
Command_Handler_Fill_Go:
    ; at this point we have a valid byte in InByteL. We clear the address,
    ; record the number of kilobytes in another byte, and count until we finish
    ; covering all bytes in EEPROM. One difference from this and Dump is that
    ; we don't have to display each byte. We just have to report at the end
    ; when we have written all data into memory.
    MOVLW	0x59
    CALL	USART_SendByte
    CALL	USART_SendCRLF
    BSF		STATUS, RP0			; set PORTD to output
    BCF		STATUS, RP1
    CLRF	TRISD
    BCF		STATUS, RP0
    BCF		STATUS, RP1
    CLRF	AddressL			; set address to 0x0000
    CLRF	AddressH
    CALL	EEPROM_SetAddress
    MOVF	DeviceSize, W
    MOVWF	InByteH				; copy kB number to InByteH
Command_Handler_Fill_Go2:
    ; write the byte, increment address. If the increment overflows, stop.
    ; If we crossed a 64 threshold, pause for 10 mS so the EEPROM can enter
    ; its write phase. While we're doing that, check if we crossed a 1024
    ; boundary so we can decrement the kilobytes counter (if needed)
    MOVF	InByteL, W			; get the fill byte
    CALL	EEPROM_WriteByte		; pop it onto ROM
    CALL	EEPROM_IncrementAddress		; address++
    BTFSC	STATUS, 0
    GOTO	Command_Handler_Fill_FinalDelay
    MOVF	AddressL, W
    ANDLW	0x3F				; check if address is divisible
    BTFSC	STATUS, 2			; by 64. If so, go to 10 mS
    GOTO	Command_Handler_Fill_Go3    
    GOTO	Command_Handler_Fill_Go2
Command_Handler_Fill_Go3:
    ; delays 10 milliseconds to allow EEPROM write sequence to work. After
    ; the delay, check if address is divisible by 1024 by ANDing AddressL
    ; with 0xFF and ANDing AddressH by 
    MOVLW	0x0A				; set W to 10
    MOVWF	D1				; set to D1
    CALL	EEPROM_msDelay			; wait 10 milliseconds
    MOVF	AddressL, F			; bit test low Address byte
    BTFSS	STATUS, 2
    GOTO	Command_Handler_Fill_Go2	; if AddressL != 0 repeat write
    MOVLW	0x03				; check if AddressH is divisible
    ANDWF	AddressH, W			; by 4. If so, we count down
    BTFSS	STATUS, 2			; one kB in InByteH
    GOTO	Command_Handler_Fill_Go2
    DECFSZ	InByteH, F
    GOTO	Command_Handler_Fill_Go2
    GOTO	Command_Handler_Fill_End
Command_Handler_Fill_FinalDelay:		; this only executes if
    MOVLW	0x0A				; ROM is 64 KB. Increment will
    MOVWF	D1				; not raise it above 0xFFFF,
    CALL	EEPROM_msDelay			; which will fail regular checks
Command_Handler_Fill_End:
    ; Sets address to 0x0000 after filling all memory
    ; Display text messaging stating the successfull fill operation
    CLRF	AddressL
    CLRF	AddressH
    CALL	EEPROM_SetAddress
    MOVF	InByteL, W
    CALL	USART_PrintBytetoChar
    MOVLW	0x1A
    CALL	TextMessage
    GOTO	Command_Handler_End
    
Command_Handler_Help_A:
    MOVLW	0x03
    CALL	TextMessage
    GOTO	Command_Handler_End    

Command_Handler_Help_B:
    MOVLW	0x04
    CALL	TextMessage
    GOTO	Command_Handler_End
    
Command_Handler_Help_D:
    MOVLW	0x05
    CALL	TextMessage
    GOTO	Command_Handler_End 
    
Command_Handler_Help_F:
    MOVLW	0x06
    CALL	TextMessage
    GOTO	Command_Handler_End      
    
Command_Handler_Help_H:
    MOVLW	0x02
    CALL	TextMessage
    GOTO	Command_Handler_End
    
Command_Handler_Help_L:
    MOVLW	0x07
    CALL	TextMessage
    GOTO	Command_Handler_End  

Command_Handler_Help_P:
    MOVLW	0x08
    CALL	TextMessage
    GOTO	Command_Handler_End
    
Command_Handler_Help_R:
    MOVLW	0x09
    CALL	TextMessage
    GOTO	Command_Handler_End
    
Command_Handler_Help_S:
    MOVLW	0x0A
    CALL	TextMessage
    GOTO	Command_Handler_End
    
Command_Handler_Help_U:
    MOVLW	0x0B
    CALL	TextMessage
    GOTO	Command_Handler_End
    
Command_Handler_Help_W:
    MOVLW	0x0C
    CALL	TextMessage
    GOTO	Command_Handler_End
    
Command_Handler_Help_PLUS:
    MOVLW	0x0D
    CALL	TextMessage
    GOTO	Command_Handler_End   
    
Command_Handler_Help_MINUS:
    MOVLW	0x0E
    CALL	TextMessage
    GOTO	Command_Handler_End    
    
Command_Handler_Lock:
    ; engages software data protection. Currently only supports the AT28C256.
    CALL	Command_Handler_Size_Check	; check if ROM size is set
    BTFSC	STATUS, 0			; carry flag will tell us
    GOTO	Command_Handler_End		; error out if not
    MOVF	DeviceSize, W			; SDP on routine is only
    XORLW	0x20				; compatible with AT28C256
    BTFSS	STATUS, 2			; exit if size != 32
    GOTO	Command_Handler_End
    ; later, should print a message to notify 
    CALL	EEPROM_SDP_On
    MOVLW	0x0F
    CALL	TextMessage
    GOTO	Command_Handler_End
    
Command_Handler_Page:
    ; allows the user (or another digital controller) to load bytes for a
    ; block write. Validates entries and places them into media.
    CALL	Command_Handler_Size_Check	; check if ROM size is set
    BTFSC	STATUS, 0			; carry flag will tell us
    GOTO	Command_Handler_End		; error out if not
    ; Flow:
    ;
    ; 1) normal size check - do not proceed until we know what size the ROM is
    ; 2) check the command. If it is "P" with no arguments, display the current
    ;    page if the size is not zero. Otherwise, error out (invalid input)
    ; 3) if there is an argument, validate it is a decimal number between
    ;    1-64. This is the valid page size.
    ; 4) clear the page pointer and the entire page buffer to enter new data.
    ; 5) accept bytes one at a time from input. Validate if byte is an ascii
    ;    character '0'-'9' or 'A'-'F'. Echo a valid character. If character
    ;    entered is ENTER (0x0A or 0x0D), stop entering characters and jump
    ;    to step 9.
    ; 6) on the second character, perform three operations: write the entered
    ;    characters into the buffer page as a byte, increment the page
    ;    buffer pointer, and echo a space.
    ; 7) check if the buffer pointer is equal to the page size. If so, end
    ;    a page write and display a success message.
    ; 8) if buffer pointer is not equal to the page size, check if it is 32.
    ;    if it is 32, print a CR/LF combo to move to a new line.
    ; 9) display a message stating the number of bytes written to the page.
    ;
    INCF	InputPtr, F		; bump the input pointer up by one
    MOVLW	0x30			; offset the pointer by 30
    ADDWF	InputPtr, W		; mix the two in W
    MOVWF	FSR			; copy W to the indirect register
    MOVF	INDF, W			; get the character into W
    BTFSC	STATUS, 2		; zero flag set if it is null char
    GOTO	Command_Handler_Page_Display
    XORLW	' '			; check if it is space
    BTFSS	STATUS, 2		; if next character is not space or 0
    GOTO	Input_Invalid		; input is invalid. Try again nerd
    INCF	InputPtr, F		; check character after space to see if
    MOVLW	0x30			; it is a null character. This is to
    ADDWF	InputPtr, W		; reject commands like "R "
    MOVWF	FSR
    MOVF	INDF, W
    BTFSC	STATUS, 2
    GOTO	Input_Invalid
    DECF	InputPtr, F
    CALL	Text_Decimal
    XORLW	0x00			; check if W is 0 (success!)
    BTFSC	STATUS, 2		; proceed to print character if so
    GOTO	Command_Handler_Page_1
    MOVWF	DataByte		; save W
    XORLW	0xFD			; check for buffer overrun
    BTFSS	STATUS, 2		; is W = 0xFD?
    GOTO	Input_Invalid		; if not, print invalid input message
    MOVLW	0x80
    CALL	TextMessage
    MOVLW	0x82
    CALL	TextMessage
    CALL	USART_SendCRLF
    GOTO	Command_Handler_End
Command_Handler_Page_Display:
    ; if command P was used with no arguments, display the entire page buffer
    ; first, check if PageSize is zero. Error out if so
    ; 
    ; if we have something to display, print a message and then print
    ; every byte in the page buffer starting at 0x40
    MOVF	PageSize, F
    BTFSC	STATUS, 2
    GOTO	Input_Invalid
    MOVLW	0x1B
    CALL	TextMessage
    CLRF	PagePtr
    CALL	USART_SendCRLF
Command_Handler_Page_Disp_Loop:
    ; load the indirect address into FSR, grab a byte, and print it. Then
    ; print a space and increment the page pointer. Check if the page pointer
    ; equals the page size and end if it is.
    ;
    ; if we haven't reached the end of the page yet, check if the page pointer
    ; is divisible by 32. If not, return to beginning of loop. If so, print
    ; a new line and then loop around.
    MOVLW	0x40
    ADDWF	PagePtr, W
    MOVWF	FSR
    MOVF	INDF, W
    CALL	USART_PrintBytetoChar
    MOVLW	0x20
    CALL	USART_SendByte
    INCF	PagePtr, F
    MOVF	PageSize, W
    XORWF	PagePtr, W
    BTFSC	STATUS, 2
    GOTO	Command_Handler_Page_Display_End
    MOVF	PagePtr, W
    ANDLW	0x1F
    BTFSS	STATUS, 2
    GOTO	Command_Handler_Page_Disp_Loop
    CALL	USART_SendCRLF
    GOTO	Command_Handler_Page_Disp_Loop
Command_Handler_Page_Display_End:
    CALL	USART_SendCRLF
    GOTO	Command_Handler_End
Command_Handler_Page_1:
    ; if we are here, a decimal quantity was written into InByteH:InByteL.
    ; we can only accept values between 1 and 64. Let us check both of those
    ; values now.
    MOVF	InByteH, W		; check if input was higher
    BTFSS	STATUS, 2		; than 255 (high byte should be zero)
    GOTO	Input_Invalid
    MOVF	InByteL, W		; check if input is zero
    BTFSC	STATUS, 2		; if it is, error out
    GOTO	Input_Invalid
    ADDLW	0xBF			; add 191 to W. If W is higher than 64,
    BTFSC	STATUS, 0		; carry will set and we error out again
    GOTO	Input_Invalid
    MOVF	InByteL, W		; if everything passes, load byte in W
    MOVWF	PageSize
Command_Handler_Page_2:
    ; now that the input has passed the 1-64 check, initialize the variables
    ; in the page buffer.
    ;
    ; also clear InByteL and InByteH. Low will be used as temp storage for
    ; data until we can move it to the buffer. High will be used as a character
    ; counter so we can keep track of how many characters are input.
    CLRF	InByteL
    CLRF	InByteH
    MOVLW	0x40			; pointer to 64
    MOVWF	PagePtr			; store in memory
Command_Handler_Page_2.5:
    DECF	PagePtr, F		; count the pointer down by one
    MOVF	PagePtr, W		; store the new value in W
    ADDLW	0x40			; add an offset
    MOVWF	FSR			; use offset+pointer in W to point to
    CLRF	INDF			; memory in buffer and clear it
    MOVF	PagePtr, F		; bit check PagePtr
    BTFSC	STATUS, 2		; if PagePtr = 0, move on
    GOTO	Command_Handler_Page_3	; next part of routine gets data
    GOTO	Command_Handler_Page_2.5
Command_Handler_Page_3:
    ; page buffer is zero-initialized, page pointer is at zero, and we are
    ; ready to start taking characters.
    MOVLW	0x1C
    CALL	TextMessage
    CALL	USART_SendCRLF
Command_Handler_Page_3.5:
    ; loop for retrieving data from serial port. First, check if the byte is
    ; 0x0D or 0x0A (Enter Key pressed). If so, we exit the page entry routine
    ; with however many bytes we managed to grab.
    ;
    ; if not enter, bump over to the ASCII/hex validation routine. If it fails,
    ; don't do anything. Go back and get another byte.
    ; 
    ; if the command passes, rotate left InByteL four times and then OR it with
    ; W. This preserves whatever was written in the low nibble already. Also
    ; increment InByteH. Display the typed character on the screen.
    ;
    ; if InByteH is even, record InByteL in the current buffer location. Echo
    ; a space character to the terminal. Increment the buffer pointer. If the
    ; buffer pointer equals the buffer size, end the routine.
    ; 
    ; check if InByteH is divisible by 64 (should only happen one time). If
    ; it is, print CRLF and start on the new line.
    CALL	USART_GetByte
    MOVWF	DataByte		; save W to memory
    XORLW	0x0D			; is it Enter?
    BTFSC	STATUS, 2
    GOTO	Command_Handler_Page_End
    MOVF	DataByte, W
    XORLW	0x0A
    BTFSC	STATUS, 2
    GOTO	Command_Handler_Page_End
    MOVF	DataByte, W
    CALL	Check_ASCII_Hex
    BTFSC	STATUS, 0
    GOTO	Command_Handler_Page_3.5
    SWAPF	InByteL, F
    IORWF	InByteL, F
    MOVF	DataByte, W
    CALL	USART_SendByte
    INCF	InByteH, F
    BTFSC	InByteH, 0
    GOTO	Command_Handler_Page_3.5
    MOVF	PagePtr, W
    ADDLW	0x40
    MOVWF	FSR
    MOVF	InByteL, W
    MOVWF	INDF
    CLRF	InByteL
    MOVLW	0x20
    CALL	USART_SendByte
    INCF	PagePtr, F
    MOVF	PagePtr, W
    XORWF	PageSize, W
    BTFSC	STATUS, 2
    GOTO	Command_Handler_Page_End
    MOVF	InByteH, W
    ANDLW	0x3F
    BTFSS	STATUS, 2
    GOTO	Command_Handler_Page_3.5
    CALL	USART_SendCRLF
    GOTO	Command_Handler_Page_3.5
Command_Handler_Page_End:
    MOVF	PagePtr, W
    MOVWF	PageSize
    CALL	USART_SendCRLF
    MOVF	PagePtr, W
    CALL	Decimal_Text
    MOVLW	0x1D
    CALL	TextMessage
    GOTO	Command_Handler_End
    
Command_Handler_Read:
    ; displays a set number of bytes from 1 - 255, ends at upper ROM boundary
    CALL	Command_Handler_Size_Check	; check if ROM size is set
    BTFSC	STATUS, 0			; carry flag will tell us
    GOTO	Command_Handler_End		; error out if not
    ; Flow:
    ;
    ; 1) standard check for next character: anything other than space, error
    ;    out with Invalid Input message. Check if next character is 0x00 with
    ;    same result if it is. This prevents inputs of "R "
    ; 2) read decimal numbers into InByteH:InByteL
    ; 3) if number > 255, error out with invalid input
    ; 4) save InByteL in D1 to use as a down counter
    ; 5) use D2 as an up counter
    ; 6) print the current address in the format of "0x----: "
    ; 7) read the ROM byte at the current address and print it on screen
    ;    followed by a ' ' character
    ; 8) decrement the first counter. If zero, end routine.
    ; 9) increment the second one. If 32, send a CR-LF and repeat from step 6.
    ; A) increment address. If fail due to address 0xFFFF, end routine.
    ; B) if routine not ended already, repeat from step 7
    ;
    INCF	InputPtr, F		; bump the input pointer up by one
    MOVLW	0x30			; offset the pointer by 30
    ADDWF	InputPtr, W		; mix the two in W
    MOVWF	FSR			; copy W to the indirect register
    MOVF	INDF, W			; get the character into W
    BTFSC	STATUS, 2		; zero flag set if it is null char
    GOTO	Input_Invalid		; reject input
    XORLW	' '			; check if it is space
    BTFSS	STATUS, 2		; if next character is not space or 0
    GOTO	Input_Invalid		; input is invalid. Try again nerd
    INCF	InputPtr, F		; check character after space to see if
    MOVLW	0x30			; it is a null character. This is to
    ADDWF	InputPtr, W		; reject commands like "R "
    MOVWF	FSR
    MOVF	INDF, W
    BTFSC	STATUS, 2
    GOTO	Input_Invalid
    DECF	InputPtr, F
    CALL	Text_Decimal
    XORLW	0x00			; check if W is 0 (success!)
    BTFSC	STATUS, 2		; proceed to print character if so
    GOTO	Command_Handler_Read_1
    MOVWF	DataByte		; save W
    XORLW	0xFD			; check for buffer overrun
    BTFSS	STATUS, 2		; is W = 0xFD?
    GOTO	Input_Invalid		; if not, print invalid input message
    MOVLW	0x80
    CALL	TextMessage
    MOVLW	0x82
    CALL	TextMessage
    CALL	USART_SendCRLF
    GOTO	Command_Handler_End
Command_Handler_Read_1:
    ; validate value of input (1 - 255) and set PORTD to input
    MOVF	InByteL, W		; check if low byte is 0
    BTFSC	STATUS, 2		; if it is, error out
    GOTO	Input_Invalid
    MOVWF	D1			; save low byte in D1
    MOVF	InByteH, W		; check if high byte is anything but 0
    BTFSS	STATUS, 2		; if it is, error out
    GOTO	Input_Invalid
    CLRF	D2			; use D2 as up counter
    BSF		STATUS, RP0		; set PORTD to input
    BCF		STATUS, RP1
    MOVLW	0xFF
    MOVWF	TRISD
    BCF		STATUS, RP0
    BCF		STATUS, RP1
Command_Handler_Read_2:
    ; print the address at the beginning of the line
    CALL	USART_SendCRLF
    MOVLW	0x30			; set W to '0'
    CALL	USART_SendByte
    MOVLW	0x78			; set W to 'x'
    CALL	USART_SendByte
    MOVF	AddressH, W		; print hexadecimal of high byte
    CALL	USART_PrintBytetoChar
    MOVF	AddressL, W		; print hexadecimal of low byte
    CALL	USART_PrintBytetoChar
    MOVLW	0x3A			; print ':'
    CALL	USART_SendByte
    MOVLW	0x20			; print ' '
    CALL	USART_SendByte
    CLRF	D2
Command_Handler_Read_3:
    ; read a byte from ROM and print it on the screen
    CALL	EEPROM_ReadByte
    CALL	USART_PrintBytetoChar
    MOVLW	0x20			; print ' '
    CALL	USART_SendByte
    MOVF	AddressL, W		; copy address data to other memory
    MOVWF	InByteL			; and increment both by one
    INCF	InByteL, F
    MOVF	AddressH, W
    MOVWF	InByteH
    MOVF	InByteL, F
    BTFSS	STATUS, 2
    GOTO	Command_Handler_Read_3.5
    INCF	InByteH, F
    CALL	EEPROM_BoundCheck
    BTFSC	STATUS, 0
    GOTO	Command_Handler_Read_4
Command_Handler_Read_3.5:
    CALL	EEPROM_IncrementAddress ; increment address, set carry bit if
    BTFSC	STATUS, 0		; we are at FFFF. Stop printing bytes
    GOTO	Command_Handler_Read_4
    DECF	D1, F			; count down the number of bytes
    MOVF	D1, F			; check if D1 is zero
    BTFSC	STATUS, 2
    GOTO	Command_Handler_Read_4
    INCF	D2, F			; count up the row counter
    MOVF	D2, W			; save it to W
    XORLW	0x20			; check if W = 32
    BTFSC	STATUS, 2
    GOTO	Command_Handler_Read_2	; if W = 32, print a new line
    GOTO	Command_Handler_Read_3	; otherwise, keep printing bytes
Command_Handler_Read_4:
    CALL	USART_SendCRLF		; new line
    MOVLW	0x11			; message 11 ("Address: ")
    CALL	TextMessage
    MOVF	AddressH, W
    CALL	USART_PrintBytetoChar
    MOVF	AddressL, W
    CALL	USART_PrintBytetoChar
    CALL	USART_SendCRLF
    GOTO	Command_Handler_End    

Command_Handler_Size:
    ; dictates the number of kilobytes in the ROM
    ; normal values are 1, 2, 4, 8, 16, 32, 64
    ; 
    ; Flow:
    ; 1) read the second character in the buffer. Exit if it is null
    ; or anything other than space.
    ; 2) call a function to read remaining characters in the buffer
    ; and return value of the numbers in InByteH:InByteL
    ; 3) if the function returns an error, handle that error
    ; 4) check if input was larger than 64 kB, error out if so
    ; 5) save validated input in DeviceSize
    ; 6) display a message stating we changed the memory
    INCF	InputPtr, F		; bump the input pointer up by one
    MOVLW	0x30			; offset the pointer by 30
    ADDWF	InputPtr, W		; mix the two in W
    MOVWF	FSR			; copy W to the indirect register
    MOVF	INDF, W			; get the character into W
    BTFSC	STATUS, 2		; zero flag set if it is null char
    GOTO	Input_Invalid		; reject input
    XORLW	' '			; check if it is space
    BTFSS	STATUS, 2		; if next character is not space or 0
    GOTO	Input_Invalid		; input is invalid. Try again nerd
    CALL	Text_Decimal		; turn numerical characters into a
    XORLW	0x00			; check if W is 0 (success!)
    BTFSC	STATUS, 2		; proceed to print character if so
    GOTO	Command_Handler_Size_PrintValue
    MOVWF	DataByte		; save W
    XORLW	0xFD			; check for buffer overrun
    BTFSS	STATUS, 2		; is W = 0xFD?
    GOTO	Input_Invalid		; if not, print invalid input message
    MOVLW	0x80
    CALL	TextMessage
    MOVLW	0x82
    CALL	TextMessage
    CALL	USART_SendCRLF
    GOTO	Command_Handler_End
Command_Handler_Size_PrintValue:
    MOVF	InByteH, F		; check if high byte is zero
    BTFSS	STATUS, 2		; if it isn't, reject the input
    GOTO	Input_Invalid		
    MOVF	InByteL, W		; check if low byte is zero
    BTFSC	STATUS, 2		; if it is, reject the input
    GOTO	Input_Invalid
    ADDLW	0xBF			; checking for values higher than
    BTFSC	STATUS, 0		; 64 (0x40 + 0xBF) = FF
    GOTO	Input_Invalid		; error out if W > 64
    MOVF	InByteL, W
    MOVWF	DeviceSize
    MOVLW	0x12			; select message 12
    CALL	TextMessage		; print to serial monitor
    MOVF	DeviceSize, W		; retrieve the device size value
    CALL	Decimal_Text		; convert it to ASCII and print it
    CALL	USART_SendCRLF
    GOTO	Command_Handler_End	; return to main loop    
    
Command_Handler_Unlock:
    CALL	Command_Handler_Size_Check	; check if ROM size is set
    BTFSC	STATUS, 0			; carry flag will tell us
    GOTO	Command_Handler_End		; error out if not
    MOVF	DeviceSize, W			; check if size = 32
    XORLW	0x20				; this only works for AT28C256
    BTFSS	STATUS, 2			; type ROM
    GOTO	Command_Handler_Unlock_Fail
    CALL	EEPROM_SDP_Off
    MOVLW	0x10
    CALL	TextMessage
    GOTO	Command_Handler_End
Command_Handler_Unlock_Fail:
    MOVLW	0x80
    CALL	TextMessage
    ; display an error message for Unlock Fail
    GOTO	Command_Handler_End
    
Command_Handler_Write:
    CALL	Command_Handler_Size_Check	; check if ROM size is set
    BTFSC	STATUS, 0			; carry flag will tell us
    GOTO	Command_Handler_End		; error out if not
    ; writes a byte to the current memory address and then verifies the write.
    ; note - this routine does not increment address. That has to be done
    ;        via the increment (+) command. 
    ;
    ; Flow:
    ;
    ; 1) check two spaces after "W". It expects to see a space and a character
    ;    that isn't null. If we have something after a space, we proceed.
    ; 2) read the following characters as hexadecimal. Call out invalid input
    ;    if the data is not a single byte in hex format (EG, "W 2F")
    ; 3) since the current address would've been validated, we go straight
    ;    into writing the byte. Set PORTD to output and call a write
    ; 4) display message stating a write with the byte and address
    ; 4) wait 10 mS to allow EEPROM to write
    ; 5) set PORTD to input and call a read from the same address
    ; 6) verify read byte was same as written byte
    ; 7) display message showing byte read and address
    ;
    INCF	InputPtr, F		; bump the input pointer up by one
    MOVLW	0x30			; offset the pointer by 30
    ADDWF	InputPtr, W		; mix the two in W
    MOVWF	FSR			; copy W to the indirect register
    MOVF	INDF, W			; get the character into W
    BTFSC	STATUS, 2		; zero flag set if it is null char
    GOTO	Input_Invalid		; reject input
    XORLW	' '			; check if it is space
    BTFSS	STATUS, 2		; if next character is not space or 0
    GOTO	Input_Invalid		; input is invalid. Try again nerd
    INCF	InputPtr, F		; check character after space to see if
    MOVLW	0x30			; it is a null character. This is to
    ADDWF	InputPtr, W		; reject commands like "A "
    MOVWF	FSR
    MOVF	INDF, W
    BTFSC	STATUS, 2
    GOTO	Input_Invalid
    DECF	InputPtr, F    
    CALL	Text_Hexadecimal
    XORLW	0x00			; check if W is 0 (success!)
    BTFSC	STATUS, 2		; proceed to print character if so
    GOTO	Command_Handler_Write_Go
    MOVWF	DataByte		; save W
    XORLW	0xFD			; check for buffer overrun
    BTFSS	STATUS, 2		; is W = 0xFD?
    GOTO	Input_Invalid		; if not, print invalid input message
    MOVLW	0x80
    CALL	TextMessage
    MOVLW	0x82
    CALL	TextMessage
    CALL	USART_SendCRLF
    GOTO	Command_Handler_End
Command_Handler_Write_Go:
    MOVF	InByteH, F		; check if input was higher than 255
    BTFSS	STATUS, 2
    GOTO	Input_Invalid
    BSF		STATUS, RP0		; set PORTD to output
    BCF		STATUS, RP1
    CLRF	TRISD
    BCF		STATUS, RP0
    BCF		STATUS, RP1
    MOVF	InByteL, W		; save byte to be written in W
    CALL	EEPROM_WriteByte
    MOVLW	0x13			; display message showing byte and
    CALL	TextMessage		; address we are trying to write data
    MOVF	InByteL, W		; to.
    CALL	USART_PrintBytetoChar
    MOVLW	0x14
    CALL	TextMessage
    MOVF	AddressH, W
    CALL	USART_PrintBytetoChar
    MOVF	AddressL, W
    CALL	USART_PrintBytetoChar
    CALL	USART_SendCRLF		; print endline characters to terminal
    MOVLW	0x0A			; delay 10 mS to allow the ROM to write
    MOVWF	D1
    CALL	EEPROM_msDelay
    BSF		STATUS, RP0		; set PORTD to input
    BCF		STATUS, RP1
    MOVLW	0xFF
    MOVWF	TRISD
    BCF		STATUS, RP0
    BCF		STATUS, RP1
    CALL	EEPROM_ReadByte		; read the location we just wrote to
    MOVWF	DataByte		; and save it to memory.
    CALL	USART_PrintBytetoChar	; Print the value we read
    MOVLW	0x15			; along with a message to show address
    CALL	TextMessage
    MOVF	AddressH, W
    CALL	USART_PrintBytetoChar
    MOVF	AddressL, W
    CALL	USART_PrintBytetoChar
    CALL	USART_SendCRLF
    GOTO	Command_Handler_End
    
Command_Handler_Inc:
    CALL	Command_Handler_Size_Check	; check if ROM size is set
    BTFSC	STATUS, 0			; carry flag will tell us
    GOTO	Command_Handler_End		; error out if not
    ; upper boundary check: copy current address into InByteH:InByteL and
    ; increment the InByteL. If it rolls over to 0x00, increment the high
    ; byte and do a 
    MOVF	AddressL, W
    MOVWF	InByteL
    INCF	InByteL, F
    MOVF	AddressH, W
    MOVWF	InByteH
    MOVF	InByteL, F
    BTFSS	STATUS, 2
    GOTO	Command_Handler_Inc_2
    INCF	InByteH, F
    CALL	EEPROM_BoundCheck
    BTFSC	STATUS, 0
    GOTO	Command_Handler_IncFail
Command_Handler_Inc_2:    
    CALL	EEPROM_IncrementAddress
    BTFSC	STATUS, 0		; if carry flag is set, we overflowed
    GOTO	Command_Handler_IncFail
Command_Handler_Inc_3:    
    MOVLW	0x11
    CALL	TextMessage		; print "Address: "
    MOVF	AddressH, W		; get high byte of address
    CALL	USART_PrintBytetoChar	; print it
    MOVF	AddressL, W		; get low byte of address
    CALL	USART_PrintBytetoChar	; print it
    CALL	USART_SendCRLF
    GOTO	Command_Handler_End
Command_Handler_IncFail:
    ; cannot increment address past FFFF or memory size limit.
    MOVLW	0x80
    CALL	TextMessage
    MOVLW	0x86
    CALL	TextMessage
    MOVLW	0x11
    CALL	TextMessage		; print "Address: "
    MOVF	AddressH, W		; get high byte of address
    CALL	USART_PrintBytetoChar	; print it
    MOVF	AddressL, W		; get low byte of address
    CALL	USART_PrintBytetoChar	; print it
    CALL	USART_SendCRLF
    GOTO	Command_Handler_End
    
Command_Handler_Dec:
    CALL	Command_Handler_Size_Check	; check if ROM size is set
    BTFSC	STATUS, 0			; carry flag will tell us
    GOTO	Command_Handler_End		; error out if not
    CALL	EEPROM_DecrementAddress
    BTFSC	STATUS, 0		; if carry flag is set, we underflowed
    GOTO	Command_Handler_DecFail
    MOVLW	0x11
    CALL	TextMessage		; print "Address: "
    MOVF	AddressH, W		; get high byte of address
    CALL	USART_PrintBytetoChar	; print it
    MOVF	AddressL, W		; get low byte of address
    CALL	USART_PrintBytetoChar	; print it
    CALL	USART_SendCRLF
    GOTO	Command_Handler_End
Command_Handler_DecFail:
    ; cannot decrement address past 0000.
    CLRF	AddressH		; if we tried to decrement below
    CLRF	AddressL		; 0, make it 0 again.
    MOVLW	0x80			; print error message
    CALL	TextMessage
    MOVLW	0x84
    CALL	TextMessage
    MOVLW	0x11
    CALL	TextMessage		; print "Address: "
    MOVF	AddressH, W		; get high byte of address
    CALL	USART_PrintBytetoChar	; print it
    MOVF	AddressL, W		; get low byte of address
    CALL	USART_PrintBytetoChar	; print it
    CALL	USART_SendCRLF
    GOTO	Command_Handler_End

Command_Handler_Size_Check:
    ; checks if a value is entered in the device size
    ; and prevents command execution if it is empty
    MOVF	DeviceSize, W		; checks if ROM capacity is written
    XORLW	0x00			; compare it to zero
    BTFSC	STATUS, 2
    GOTO	Command_Handler_NoSize
    BCF		STATUS, 0		; clear the carry flag
    RETURN				; go back
Command_Handler_NoSize:
    MOVLW	0x80			; display Size Undefined message
    CALL	TextMessage
    MOVLW	0x85
    CALL	TextMessage
    BSF		STATUS, 0		; set carry flag to indicate problem
    RETURN

Text_Decimal:
    ; converts characters in the buffer from decimal ASCII to binary value
    ; in memory. Stores the value in InByteH:InByteL
    ; stops when we read 0x00, hit InputPtr value of 8, or read a non-digit.
    ;
    ; Flow:
    ;
    ; 1) clears output variables (if no valid characters are read, they
    ;    fall through as zero)
    ; 2) point to next byte in the buffer. If the pointer is 8, we
    ;    have overrun the buffer and exit. If not, get the character at
    ;    that position
    ; 3) if the read character is null, return from routine with W = 0.
    ; 4) add 0xD0 to W (same as subtracting 0x30), check result.
    ; 5) if result is more than 0x09, return from routine with W = 255 (-1)
    ; 6) clear the carry bit and rotate output variables left. Check if carry
    ;    flag is set after shifting left both the low and high byte.
    ; 7) if shifts left restult in a carry, exit with W = 254 (-2) for overflow
    ; 8) repeat 6 and 7 two more times, check for carry, and save the output
    ;    variables in two new bytes. This results in multiplication by 8.
    ; 9) rotate the output variables twice. This is multiplication by 2.
    ; A) add the two and check for carry yet again. The final result is a
    ;    multiplication by 10. The first time around, the two values are zero.
    ; B) add the character read from the buffer, check for carry.
    ; C) if not carry, go to the repeat again from 2. If carry, error out.
    CLRF	InByteL			; the output bytes. Default = 0x0000
    CLRF	InByteH
Text_Decimal_Loop:
    INCF	InputPtr, F		; advance buffer pointer by one
    MOVF	InputPtr, W		; check if it points too high
    XORLW	0x08			; if buffer pointer > 7 then error out
    BTFSC	STATUS, 2
    GOTO	Text_Decimal_BufferEnd	; handle buffer overflow.
    MOVF	InputPtr, W		; otherwise, restore pointer plus
    ADDLW	0x30			; offset in W, set FSR and draw a byte
    MOVWF	FSR			; from the buffer array
    MOVF	INDF, W
    BTFSC	STATUS, 2		; check if read character was 0x00
    GOTO	Text_Decimal_Success	; if so, stop reading and go back
    ADDLW	0xD0			; same as subtracting 30 from W
    MOVWF	DataByte		; save numeric value in DataByte
    ; now, we have a value in W and DataByte that should be between 0-9. If
    ; not, the character entered was not a digit and should be rejected.
    SUBLW	0x09			; W = 9 - W
    BTFSS	STATUS, 0		; was W bigger than 9?
    GOTO	Text_Decimal_Invalid	; error out if it was
    ; if we made it this far, we have a decimal value in W/DataByte
    ; first, we multiply InByteL by ten (should be zero on the first go)
    ; 1) rotate left the low byte (if overflow, will be in the C flag)
    ; 2) rotate left the high byte (if low byte overflowed, will rotate in)
    ; 3) check if the high byte rotated out a 1 bit (stored in carry flag)
    ; 4) if a 1 was rotated out, handle an overflow (value over FFFF)
    ; 5) repeat 1-4 two more times. The end result is multiplication by 8
    BCF		STATUS, 0
    RLF		InByteL, F
    RLF		InByteH, F
    BTFSC	STATUS, 0
    GOTO	Text_Decimal_Overflow
    RLF		InByteL, F
    RLF		InByteH, F
    BTFSC	STATUS, 0
    GOTO	Text_Decimal_Overflow
    RLF		InByteL, F
    RLF		InByteH, F
    BTFSC	STATUS, 0
    GOTO	Text_Decimal_Overflow
    ; now we save the two bytes to Temp and Temp2. These are used by other
    ; routines, but not in this bit of code.
    MOVF	InByteL, W
    MOVWF	Temp
    MOVF	InByteH, W
    MOVWF	Temp2
    ; next we rotate right both InByte L/H twice. This is the same as division
    ; by four, so they end up at twice their original value. The carry flag is
    ; cleared both times, which prevents a 1 from being rotated in.
    BCF		STATUS, 0
    RRF		InByteH, F
    RRF		InByteL, F
    BCF		STATUS, 0
    RRF		InByteH, F
    RRF		InByteL, F
    BCF		STATUS, 0
    ; the next step is to get the 8n values of low and high byte into W, add
    ; the 2n values, and then store them in InByteL/H. If addition to the low
    ; byte carries, increment the high byte. If addition to the high byte
    ; carries, handle overflow.
    MOVF	Temp, W
    ADDWF	InByteL, F
    BTFSS	STATUS, 0
    GOTO	Text_Decimal_NoLowOverflow
    INCF	InByteH, F
    MOVF	InByteH, W
    BTFSC	STATUS, 2
    GOTO	Text_Decimal_Overflow
Text_Decimal_NoLowOverflow:
    MOVF	Temp2, W
    ADDWF	InByteH, F
    BTFSC	STATUS, 0
    GOTO	Text_Decimal_Overflow
    ; lastly, we get the value of the read character and add it to the low byte
    ; if the addition carries, increment the high byte. If that addition
    ; carries, handle invalid input. Otherwise, go back and read the next
    ; character.
    MOVF	DataByte, W
    ADDWF	InByteL, F
    BTFSS	STATUS, 0
    GOTO	Text_Decimal_Loop
    INCF	InByteH, F
    MOVF	InByteH, F
    BTFSS	STATUS, 2
    GOTO	Text_Decimal_Loop
    GOTO	Text_Decimal_Overflow
Text_Decimal_Success:
    ; if we reached a null character before running out of buffer space, all
    ; of the characters were numeric, and the total amount was not more than
    ; 0xFFFF, W = 0 to signal a valid read of ASCII numbers into binary.
    CLRW
    RETURN
Text_Decimal_Invalid:
    ; set W to -1 if a non-number character (0x30-0x39) was encountered
    MOVLW	0xFF
    RETURN
Text_Decimal_Overflow:
    ; set W to -2 if the value in InByteH:InByteL exceeded 0xFFFF
    MOVLW	0xFE
    RETURN
Text_Decimal_BufferEnd:
    ; set W to -3 if we ran out of room in the text buffer, then return
    MOVLW	0xFD
    RETURN
    
Decimal_Text:
    ; a routine to take the value in W and print it as a decimal quantity
    ; on the serial port. Prints a value up to 255.
    ;
    ; Flow:
    ; 1) clear three bytes in memory
    ; 2) hundreds: add 2's complement of 100 to W. If carry results, add one to
    ;    hundreds memory byte and try it again. Do until add does not result
    ;    in a carry bit set.
    ; 3) tens: add 100, which returns W to the value after subtracting all of
    ;    the hundreds. Do the same thing with 2's complement of 10 (0xF6).
    ;    For each carry bit, increment another memory byte. Keep going until
    ;    carry does not happen.
    ; 4) ones: add 10 to restore ones value of original number. Save this
    ;    value in DataByte
    ; 5) print hundreds: get the hundreds value from memory. If it is not
    ;    zero, print the ASCII character of its value.
    ; 6) print tens: get the tens value from memory. If it is not zero, print
    ;    it. If it is, check if the hundreds value was zero. If hundreds was
    ;    not zero but tens is, then print a zero in the tens place. If tens
    ;    and hundreds are both zero, move on to ones.
    ; 7) print ones: get the ones value from memory. Print it regardless of
    ;    what its value is. Return from subroutine.
    CLRF	DataByte		; a place to tally ones
    CLRF	Temp			; a place to tally hundreds
    CLRF	Temp2			; a place to tally tens
Decimal_Text_100:
    ADDLW	0x9C			; add 2's complement of 100 (156)
    BTFSS	STATUS, 0		; if we didn't carry, W < 100
    GOTO	Decimal_Text_10		; and go to the tens handler
    INCF	Temp, F			; otherwise, increment hundreds
    GOTO	Decimal_Text_100	; and return
Decimal_Text_10:
    ADDLW	0x64			; add 100 to restore W
Decimal_Text_10_Loop:
    ADDLW	0xF6			; now add 2's complement of 10 (246)
    BTFSS	STATUS, 0		; check if carry. If not, W < 10
    GOTO	Decimal_Text_1		; and go to the ones handler
    INCF	Temp2, F		; otherwise, increment tens
    GOTO	Decimal_Text_10_Loop
Decimal_Text_1:
    ADDLW	0x0A			; add 10 to restore W
    MOVWF	DataByte		; save the 1s value in memory
Decimal_Text_Print_H:
    MOVF	Temp, W			; retrieve the hundreds value
    XORLW	0x00			; see if there's anything there
    BTFSC	STATUS, 2		; is zero flag set?
    GOTO	Decimal_Text_Print_T	; if so, go to next digit
    ADDLW	0x30			; otherwise, make W into ASCII of W
    CALL	USART_SendByte		; and print it to the terminal
Decimal_Text_Print_T:
    MOVF	Temp2, W		; retrieve the tens value
    XORLW	0x00			; see if there's anything there
    BTFSS	STATUS, 2		; if W != 0
    GOTO	Decimal_Text_Print_T2	; skip ahead to printing the character 
    MOVF	Temp, F
    BTFSC	STATUS, 2		; if W = 0
    GOTO	Decimal_Text_Print_O	; then go on to the ones digit
Decimal_Text_Print_T2:
    ADDLW	0x30			; ASCII-fy the value in W
    CALL	USART_SendByte		; and print it to the serial terminal
Decimal_Text_Print_O:
    MOVF	DataByte, W		; retrieve the ones value
    ADDLW	0x30			; ASCII-fy it
    CALL	USART_SendByte		; and print it regardless of value
    RETURN
    
Text_Hexadecimal:
    ; converts characters in the buffer from ASCII to hexadecimal values.
    ; stores the value in InByteH:InByteL. Ends when we reach 0x00 character,
    ; reach the end of the 8-byte buffer, or find an invalid character.
    CLRF	InByteH
    CLRF	InByteL
Text_Hexadecimal_Loop:
    MOVLW	0x04			; set a counter to 4
    MOVWF	Temp
    INCF	InputPtr, F		; advance buffer pointer by one
    MOVF	InputPtr, W		; check if it points too high
    XORLW	0x08			; if buffer pointer > 7 then error out
    BTFSC	STATUS, 2
    GOTO	Text_Hexadecimal_BufferEnd
    MOVF	InputPtr, W		; otherwise, restore pointer plus
    ADDLW	0x30			; offset in W, set FSR and draw a byte
    MOVWF	FSR			; from the buffer array
    MOVF	INDF, W
    BTFSC	STATUS, 2		; check if read character was 0x00
    GOTO	Text_Hexadecimal_Success; if so, stop reading and go back
    ADDLW	0xD0			; same as subtracting 30 from W
    MOVWF	DataByte		; save numeric value in DataByte
    ; now, we have a value in W and DataByte that should be between 0-9 or A-F.
    ; this is a little more complicated than the decimal version, as we are
    ; also going to check for lower-case letters. At the start, W is 0x30 lower
    ; than the ASCII value of the read character.
    ;
    ; 1) add ones complement of 0x09 (F6). If it sets the carry, the value was
    ;    higher than 9. If not, handle a number character.
    ; 2) restore W and then add twos complement of 0x11. If it does not set the
    ;    carry, W was less than 11 and invalid. Throw it away.
    ; 3) restore W and add ones complement of 0x16 (E9). If carry flag is not
    ;    set, character was between 'A' and 'F' inclusive. Handle capital
    ;    letter as a hex digit.
    ; 4) restore W and add twos complement of 0x31 (CF). If carry flag is not
    ;    set, W was lower than 0x31 ('a' - 0x30)
    ; 5) restore W and add ones complement of 0x36 (C9). If carry flag is not
    ;    set, character was between 'a' and 'f' inclusive. Handle lower case
    ;    letter as a hex digit.
    ; 6) if character is not a hex digit, error out
    ADDLW	0xF6			    ; 0-9 check. Carry flag sets if
    BTFSS	STATUS, 0		    ; W is more than 0x09
    GOTO	Text_Hexadecimal_4	    ; Jump on carry clear
    MOVF	DataByte, W
    ADDLW	0xEF			    ; less than 'A' check. Carry flag
    BTFSS	STATUS, 0		    ; only sets if W is 'A' or higher
    GOTO	Text_Hexadecimal_Invalid
    MOVF	DataByte, W		    
    ADDLW	0xE9			    ; less than 'G' check. Carry flag
    BTFSS	STATUS, 0		    ; only sets if W is higher than
    GOTO	Text_Hexadecimal_3	    ; 'F'
    MOVF	DataByte, W
    ADDLW	0xCF			    ; less than 'a' check. Carry flag
    BTFSS	STATUS, 0		    ; only sets if W is 'a' or higher.
    GOTO	Text_Hexadecimal_Invalid
    MOVF	DataByte, W
    ADDLW	0xC9			    ; less than 'g' check. Carry flag
    BTFSS	STATUS, 0		    ; only sets if W is higher than 'f'
    GOTO	Text_Hexadecimal_2
    GOTO	Text_Hexadecimal_Invalid
    ; Now that we filtered the character and have proven it valid, we have
    ; three paths we can take.
    ;
    ; path 2: character was lower case between 'a' and 'f'. Clear bit 5 to
    ;         make it upper case. Fall into path 3
    ; path 3: character was upper case between 'A' and 'F'. Subtract 7 to
    ;         place value into character. Save back into memory. Fall into
    ;         path 4.
    ; path 4: value of character is ready to be loaded into memory, or was a.
    ;         Shift left both memory bytes four times, checking for overflow 
    ;         each time. After that happens, add the value in DataByte
Text_Hexadecimal_2:
    BCF		DataByte, 5
Text_Hexadecimal_3:
    MOVF	DataByte, W
    ADDLW	0xF9
    MOVWF	DataByte
Text_Hexadecimal_4:
    BCF		STATUS, 0
    RLF		InByteL, F
    RLF		InByteH, F
    BTFSC	STATUS, 0
    GOTO	Text_Hexadecimal_Overflow
    DECFSZ	Temp, F
    GOTO	Text_Hexadecimal_4
    MOVF	DataByte, W
    ADDWF	InByteL, F
    GOTO	Text_Hexadecimal_Loop
Text_Hexadecimal_Success:
    ; set W to 0. We made it to the null character and read whatever ASCII
    ; characters were typed as data.
    ; Data is stored in InByteH:InByteL
    CLRW
    RETURN
Text_Hexadecimal_Invalid:
    ; set W to -1. We encountered a character outside a hexidecimal range.
    MOVLW	0xFF
    RETURN
Text_Hexadecimal_Overflow:
    ; set W to -2. We encountered a hexadecimal input that exceeds FFFF.
    MOVLW	0xFE
    RETURN
Text_Hexadecimal_BufferEnd:
    ; set W to -3. We encountered an input that exceeds 8 bytes.
    MOVLW	0xFD
    RETURN

Check_ASCII_Hex:
    ; checks if the byte in W is a hexadecimal value. Works on upper and
    ; lower case letters.
    ; In: W - one byte of ASCII data
    ; Out: Carry set if not a hexadecimal digit, W clear
    ;      Carry clear if a hexadecimal digit, W = value of ASCII digit
    MOVWF	D1			; save W
    ; first check for numerical digit by subtracting 0x30 from W and checking
    ; the carry flag. If it is not set, W < 0x30 and we already know it
    ; does not pass the check.
    ;
    ; Next, add 0xF6 which will cause the carry flag to set if W > 9. If W < 10
    ; then we handle W as a digit and return. Adding 0x0A to the value reverts
    ; it to 0x100 plus its numeric value. We clear Carry and return.
    ADDLW	0xD0
    BTFSS	STATUS, 0
    GOTO	Check_ASCII_Hex_Fail
    BCF		STATUS, 0
    ADDLW	0xF6
    BTFSC	STATUS, 0
    GOTO	Check_ASCII_Hex_Ltr
    ADDLW	0x0A
    BCF		STATUS, 0
    RETURN
Check_ASCII_Hex_Ltr:
    ; letter check - restore W from memory. AND it with 0xDF to convert any
    ; lower case letters to upper case. Lastly, add 0xBF. Anything lower than
    ; 0x41, 'A' will fail the check.
    ;
    ; should we still be here, clear the carry flag and add 0xFA. The value
    ; in W would be 0-5 for a valid number, so adding 0xFA will make the carry
    ; set if the value is higher than 5. A set carry causes this check to fail.
    ;
    ; if we've made it past the second check, add 0x10 to restore the hex
    ; value, clear the carry flag, and return.
    MOVF	D1, W
    ANDLW	0xDF
    ADDLW	0xBF
    BTFSS	STATUS, 0
    GOTO	Check_ASCII_Hex_Fail
    BCF		STATUS, 0
    ADDLW	0xFA
    BTFSC	STATUS, 0
    GOTO	Check_ASCII_Hex_Fail
    ADDLW	0x10
    BCF		STATUS, 0
    RETURN
Check_ASCII_Hex_Fail:
    BSF		STATUS, 0
    CLRW
    RETURN
    
Command_Handler_Next:
    INCF	InputPtr, F		; point to the next character
    MOVF	InputPtr, W		; save it in W
    XORLW	0x08			; is it 8?
    BTFSC	STATUS, 2
    GOTO	Command_Handler_End	; last byte of buffer, go back to start
    MOVLW	0x30			; otherwise, make W the pointer again
    ADDWF	InputPtr, W		; and add the updated offset
    GOTO	Command_Handler_Loop	; go back to loop and try again

Command_Handler_End:
    CLRF	InputPtr		; set the input pointer back to start
    GOTO	LOOP			; go back to input segment
        
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
; #3 - help message for Address command "A"
; #4 - help message for Block Write command "B"
; #5 - help message for Dump command "D"
; #6 - help message for Fill command "F"
; #7 - help message for Lock command "L"
; #8 - help message for Page command "P"
; #9 - help message for Read command "R"
; #A - help message for Size command "S"
; #B - help message for Unlock command "U"
; #C - help message for Write command "W"
; #D - help message for Increment command "+"
; #E - help message for Decrement command "-"
; #F - response to lock ROM command
; #10 - response to unlock ROM command
; #11 - Address indication. Followed by value of AddressH and AddressL
; #12 - Size indication. Followed by value of DeviceSize
; #13 - Write attempt message #1
; #14 - Write attempt message #2
; #15 - Write result message
; #16 - Fill prompt - displays byte and number of kilobytes to fill
; #17 - Fill prompt - prints the word " kilobytes."
; #18 - Fill prompt - asks user to press Y to continue or else to cancel
; #19 - Fill cancel message
; #1A - Fill complete message
; #1B - Page display message
; #1C - Page buffer data entry prompt
; #1D - Page buffer success message
; #1E - Block write success message
; #80 - Error message prefix
; #81 - Invalid input error
; #82 - Excessive input error
; #83 - Increment error
; #84 - Decrement error
; #85 - ROM Size unspecified error
; #86 - Address out of bounds error
; #87 - Block excess demand error
; #88 - Block address invalid error
    
TextMessage:
    CLRF	MsgIndex	    ; clear the counter used to display text 
    MOVWF	MsgNumber	    ; store the message number we're calling
TextMessageLoop:
    ; start message - displayed when program loads
    XORLW	0x01		    ; check for message #1
    BTFSS	STATUS, 2	    ; is zero flag set?
    GOTO	TextMessageLoop01   ; if not, check the next message
    MOVLW	0x08		    ; preload the page our message is on
    MOVWF	PCLATH		    ; into PCLATH
    MOVF	MsgIndex, W	    ; load character counter into W
    CALL	StartMsgText	    ; get a string character into W
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd  ; proceed to printing it
TextMessageLoop01:
    ; displays when 'H' is entered without argument - displays list of commands
    MOVF	MsgNumber, W
    XORLW	0x02		    ; check for message #2
    BTFSS	STATUS, 2	    ; is zero flag set?
    GOTO	TextMessageLoop02   ; if not, check the next message
    MOVLW	0x08		    ; preload the page our message is on
    MOVWF	PCLATH		    ; into PCLATH
    MOVF	MsgIndex, W	    ; load character counter into W
    CALL	HelpMsgHText	    ; get a string character into W
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd  ; proceed to printing it
TextMessageLoop02:
    ; Error prefix - starts with "ERROR - " when an error is encountered
    MOVF	MsgNumber, W
    XORLW	0x80		    ; check for message #80
    BTFSS	STATUS, 2	    ; is zero flag set?
    GOTO	TextMessageLoop03   ; if not, check the next message
    MOVLW	0x09		    ; preload the page our message is on
    MOVWF	PCLATH		    ; into PCLATH
    MOVF	MsgIndex, W	    ; load character counter into W
    CALL	ErrorMsgText	    ; get a string character into W
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd  ; proceed to printing it
TextMessageLoop03:
    ; Error message that displays when an invalid input happens
    MOVF	MsgNumber, W
    XORLW	0x81		    ; check for message #81
    BTFSS	STATUS, 2	    ; is zero flag set?
    GOTO	TextMessageLoop04   ; if not, check the next message
    MOVLW	0x09		    ; preload the page our message is on
    MOVWF	PCLATH		    ; into PCLATH
    MOVF	MsgIndex, W	    ; load character counter into W
    CALL	InputErrorMsgText   ; get a string character into W
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd  ; proceed to printing it
TextMessageLoop04:
    ; Error message that displays when too many characters are input
    MOVF	MsgNumber, W
    XORLW	0x82		    ; check for message #82
    BTFSS	STATUS, 2	    ; is zero flag set?
    GOTO	TextMessageLoop05   ; if not, check the next message
    MOVLW	0x09		    ; preload the page our message is on
    MOVWF	PCLATH		    ; into PCLATH
    MOVF	MsgIndex, W	    ; load character counter into W
    CALL	InputError2MsgText  ; get a string character into W
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd  ; proceed to printing it
TextMessageLoop05:
    ; displays help for 'A' command
    MOVF	MsgNumber, W
    XORLW	0x03		    ; check for message #3
    BTFSS	STATUS, 2	    ; is zero flag set?
    GOTO	TextMessageLoop06   ; if not, check the next message
    MOVLW	0x08		    ; preload the page our message is on
    MOVWF	PCLATH		    ; into PCLATH
    MOVF	MsgIndex, W	    ; load character counter into W
    CALL	HelpMsgAText	    ; get a string character into W
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd  ; proceed to printing it
TextMessageLoop06:
    ; displays help for 'B' command
    MOVF	MsgNumber, W
    XORLW	0x04		    ; check for message #4
    BTFSS	STATUS, 2	    ; is zero flag set?
    GOTO	TextMessageLoop07   ; if not, check the next message
    MOVLW	0x08		    ; preload the page our message is on
    MOVWF	PCLATH		    ; into PCLATH
    MOVF	MsgIndex, W	    ; load character counter into W
    CALL	HelpMsgBText	    ; get a string character into W
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd  ; proceed to printing it    
TextMessageLoop07:
    ; displays help for 'D' command
    MOVF	MsgNumber, W
    XORLW	0x05		    ; check for message #5
    BTFSS	STATUS, 2	    ; is zero flag set?
    GOTO	TextMessageLoop08   ; if not, check the next message
    MOVLW	0x09		    ; preload the page our message is on
    MOVWF	PCLATH		    ; into PCLATH
    MOVF	MsgIndex, W	    ; load character counter into W
    CALL	HelpMsgDText	    ; get a string character into W
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd  ; proceed to printing it 
TextMessageLoop08:
    ; displays help for 'F' command
    MOVF	MsgNumber, W
    XORLW	0x06		    ; check for message #6
    BTFSS	STATUS, 2	    ; is zero flag set?
    GOTO	TextMessageLoop09   ; if not, check the next message
    MOVLW	0x09		    ; preload the page our message is on
    MOVWF	PCLATH		    ; into PCLATH
    MOVF	MsgIndex, W	    ; load character counter into W
    CALL	HelpMsgFText	    ; get a string character into W
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd  ; proceed to printing it 
TextMessageLoop09:
    ; displays help for 'L' command
    MOVF	MsgNumber, W
    XORLW	0x07		    ; check for message #7
    BTFSS	STATUS, 2	    ; is zero flag set?
    GOTO	TextMessageLoop0A   ; if not, check the next message
    MOVLW	0x09		    ; preload the page our message is on
    MOVWF	PCLATH		    ; into PCLATH
    MOVF	MsgIndex, W	    ; load character counter into W
    CALL	HelpMsgLText	    ; get a string character into W
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd  ; proceed to printing it 
TextMessageLoop0A:
    ; displays help for 'P' command
    MOVF	MsgNumber, W
    XORLW	0x08		    ; check for message #8
    BTFSS	STATUS, 2	    ; is zero flag set?
    GOTO	TextMessageLoop0B   ; if not, check the next message
    MOVLW	0x0A		    ; preload the page our message is on
    MOVWF	PCLATH		    ; into PCLATH
    MOVF	MsgIndex, W	    ; load character counter into W
    CALL	HelpMsgPText	    ; get a string character into W
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd  ; proceed to printing it 
TextMessageLoop0B:
    ; displays help for 'R' command
    MOVF	MsgNumber, W
    XORLW	0x09		    ; check for message #9
    BTFSS	STATUS, 2	    ; is zero flag set?
    GOTO	TextMessageLoop0C   ; if not, check the next message
    MOVLW	0x0A		    ; preload the page our message is on
    MOVWF	PCLATH		    ; into PCLATH
    MOVF	MsgIndex, W	    ; load character counter into W
    CALL	HelpMsgRText	    ; get a string character into W
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd  ; proceed to printing it 
TextMessageLoop0C:
    ; displays help for 'S' command
    MOVF	MsgNumber, W
    XORLW	0x0A		    ; check for message #A
    BTFSS	STATUS, 2	    ; is zero flag set?
    GOTO	TextMessageLoop0D   ; if not, check the next message
    MOVLW	0x0A		    ; preload the page our message is on
    MOVWF	PCLATH		    ; into PCLATH
    MOVF	MsgIndex, W	    ; load character counter into W
    CALL	HelpMsgSText	    ; get a string character into W
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd  ; proceed to printing it 
TextMessageLoop0D:
    ; displays help for 'U' command
    MOVF	MsgNumber, W
    XORLW	0x0B		    ; check for message #B
    BTFSS	STATUS, 2	    ; is zero flag set?
    GOTO	TextMessageLoop0E   ; if not, check the next message
    MOVLW	0x0B		    ; preload the page our message is on
    MOVWF	PCLATH		    ; into PCLATH
    MOVF	MsgIndex, W	    ; load character counter into W
    CALL	HelpMsgUText	    ; get a string character into W
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd  ; proceed to printing it 
TextMessageLoop0E:
    ; displays help for 'W' command
    MOVF	MsgNumber, W
    XORLW	0x0C		    ; check for message #C
    BTFSS	STATUS, 2	    ; is zero flag set?
    GOTO	TextMessageLoop0F   ; if not, check the next message
    MOVLW	0x0B		    ; preload the page our message is on
    MOVWF	PCLATH		    ; into PCLATH
    MOVF	MsgIndex, W	    ; load character counter into W
    CALL	HelpMsgWText	    ; get a string character into W
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd  ; proceed to printing it    
TextMessageLoop0F:
    ; displays help for '+' command
    MOVF	MsgNumber, W
    XORLW	0x0D		    ; check for message #D
    BTFSS	STATUS, 2	    ; is zero flag set?
    GOTO	TextMessageLoop10   ; if not, check the next message
    MOVLW	0x0B		    ; preload the page our message is on
    MOVWF	PCLATH		    ; into PCLATH
    MOVF	MsgIndex, W	    ; load character counter into W
    CALL	HelpMsgPLUSText	    ; get a string character into W
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd  ; proceed to printing it      
TextMessageLoop10:
    ; displays help for '-' command
    MOVF	MsgNumber, W
    XORLW	0x0E		    ; check for message #E
    BTFSS	STATUS, 2	    ; is zero flag set?
    GOTO	TextMessageLoop11   ; if not, check the next message
    MOVLW	0x0B		    ; preload the page our message is on
    MOVWF	PCLATH		    ; into PCLATH
    MOVF	MsgIndex, W	    ; load character counter into W
    CALL	HelpMsgMINUSText    ; get a string character into W
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd  ; proceed to printing it      
TextMessageLoop11:
    ; response message for enabling Software Data Protection
    MOVF	MsgNumber, W
    XORLW	0x0F		    ; check for message #F
    BTFSS	STATUS, 2	    ; is zero flag set?
    GOTO	TextMessageLoop12   ; if not, check the next message
    MOVLW	0x0A		    ; preload the page our message is on
    MOVWF	PCLATH		    ; into PCLATH
    MOVF	MsgIndex, W	    ; load character counter into W
    CALL	LockMsgText	    ; get a string character into W
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd  ; proceed to printing it     
TextMessageLoop12:
    ; response message for disabling Software Data Protection
    MOVF	MsgNumber, W
    XORLW	0x10		    ; check for message #10
    BTFSS	STATUS, 2	    ; is zero flag set?
    GOTO	TextMessageLoop13   ; if not, check the next message
    MOVLW	0x0A		    ; preload the page our message is on
    MOVWF	PCLATH		    ; into PCLATH
    MOVF	MsgIndex, W	    ; load character counter into W
    CALL	UnlockMsgText	    ; get a string character into W
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd  ; proceed to printing it       
TextMessageLoop13:
    ; indicates new address. Literally "Address: " and then the address
    MOVF	MsgNumber, W
    XORLW	0x11		    ; check for message #11
    BTFSS	STATUS, 2	    ; is zero flag set?
    GOTO	TextMessageLoop13a  ; if not, check the next message
    MOVLW	0x0B		    ; preload the page our message is on
    MOVWF	PCLATH		    ; into PCLATH
    MOVF	MsgIndex, W	    ; load character counter into W
    CALL	AddressMsgText	    ; get a string character into W
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd  ; proceed to printing it
TextMessageLoop13a:
    ; declares ROM size set to a certain value.
    MOVF	MsgNumber, W
    XORLW	0x12
    BTFSS	STATUS, 2
    GOTO	TextMessageLoop14
    MOVLW	0x0C
    MOVWF	PCLATH
    MOVF	MsgIndex, W
    CALL	DeviceSizeMsgText
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd
TextMessageLoop14:
    ; Increment error. Displays the address right afterward
    MOVF	MsgNumber, W
    XORLW	0x83		    ; check for message #83
    BTFSS	STATUS, 2	    ; is zero flag set?
    GOTO	TextMessageLoop15   ; if not, check the next message
    MOVLW	0x0C		    ; preload the page our message is on
    MOVWF	PCLATH		    ; into PCLATH
    MOVF	MsgIndex, W	    ; load character counter into W
    CALL	IncFailMsgText	    ; get a string character into W
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd  ; proceed to printing it    
TextMessageLoop15:
    ; Increment error. Displays the address right afterward
    MOVF	MsgNumber, W
    XORLW	0x84		    ; check for message #84
    BTFSS	STATUS, 2	    ; is zero flag set?
    GOTO	TextMessageLoop16   ; if not, check the next message
    MOVLW	0x0C		    ; preload the page our message is on
    MOVWF	PCLATH		    ; into PCLATH
    MOVF	MsgIndex, W	    ; load character counter into W
    CALL	DecFailMsgText	    ; get a string character into W
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd  ; proceed to printing it    
TextMessageLoop16:
    ; Increment error. Displays the address right afterward
    MOVF	MsgNumber, W
    XORLW	0x85		    ; check for message #85
    BTFSS	STATUS, 2	    ; is zero flag set?
    GOTO	TextMessageLoop17   ; if not, check the next message
    MOVLW	0x0C		    ; preload the page our message is on
    MOVWF	PCLATH		    ; into PCLATH
    MOVF	MsgIndex, W	    ; load character counter into W
    CALL	InvalidSizeMsgText  ; get a string character into W
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd  ; proceed to printing it
TextMessageLoop17:
    ; Invalid address error. User tried to specify an address outside of
    ; current ROM size
    MOVF	MsgNumber, W
    XORLW	0x86
    BTFSS	STATUS, 2
    GOTO	TextMessageLoop18
    MOVLW	0x0C
    MOVWF	PCLATH
    MOVF	MsgIndex, W
    CALL	InvalidAddrMsgText
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd
TextMessageLoop18:
    ; Write message. Shows the user we are trying to write a byte
    MOVF	MsgNumber, W
    XORLW	0x13
    BTFSS	STATUS, 2
    GOTO	TextMessageLoop19
    MOVLW	0x0C
    MOVWF	PCLATH
    MOVF	MsgIndex, W
    CALL	WriteByteMsg1Text
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd    
TextMessageLoop19:
    ; Write message part two. Shows the user the address we are writing to.
    MOVF	MsgNumber, W
    XORLW	0x14
    BTFSS	STATUS, 2
    GOTO	TextMessageLoop20
    MOVLW	0x0C
    MOVWF	PCLATH
    MOVF	MsgIndex, W
    CALL	WriteByteMsg2Text
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd
TextMessageLoop20:
    ; Write message part three. Displays the written byte read back and address.
    MOVF	MsgNumber, W
    XORLW	0x15
    BTFSS	STATUS, 2
    GOTO	TextMessageLoop21
    MOVLW	0x0C
    MOVWF	PCLATH
    MOVF	MsgIndex, W
    CALL	WriteByteMsg3Text
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd
TextMessageLoop21:
    ; Fill message prompt. Displays byte entered and ROM size
    MOVF	MsgNumber, W
    XORLW	0x16
    BTFSS	STATUS, 2
    GOTO	TextMessageLoop22
    MOVLW	0x0C
    MOVWF	PCLATH
    MOVF	MsgIndex, W
    CALL	FillMsg1Text
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd
TextMessageLoop22:
    ; Fill message prompt. Displays " kilobytes." after the ROM size.
    MOVF	MsgNumber, W
    XORLW	0x17
    BTFSS	STATUS, 2
    GOTO	TextMessageLoop23
    MOVLW	0x0C
    MOVWF	PCLATH
    MOVF	MsgIndex, W
    CALL	FillMsg2Text
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd
TextMessageLoop23:
    ; Fill message prompt. Tells user to hit Y or any other key
    MOVF	MsgNumber, W
    XORLW	0x18
    BTFSS	STATUS, 2
    GOTO	TextMessageLoop24
    MOVLW	0x0D
    MOVWF	PCLATH
    MOVF	MsgIndex, W
    CALL	FillMsg3Text
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd
TextMessageLoop24:
    ; Fill cancel message. Displayed before going back to main loop.
    MOVF	MsgNumber, W
    XORLW	0x19
    BTFSS	STATUS, 2
    GOTO	TextMessageLoop25
    MOVLW	0x0D
    MOVWF	PCLATH
    MOVF	MsgIndex, W
    CALL	FillMsg4Text
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd
TextMessageLoop25:
    ; Fill complete message. Displays the written byte.
    MOVF	MsgNumber, W
    XORLW	0x1A
    BTFSS	STATUS, 2
    GOTO	TextMessageLoop26
    MOVLW	0x0D
    MOVWF	PCLATH
    MOVF	MsgIndex, W
    CALL	FillMsg5Text
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd
TextMessageLoop26:
    ; Page display prompt - indicates what the printed bytes on screen are.
    MOVF	MsgNumber, W
    XORLW	0x1B
    BTFSS	STATUS, 2
    GOTO	TextMessageLoop27
    MOVLW	0x0D
    MOVWF	PCLATH
    MOVF	MsgIndex, W
    CALL	PageMsg1Text
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd
TextMessageLoop27:
    ; Page display prompt - indicates what the printed bytes on screen are.
    MOVF	MsgNumber, W
    XORLW	0x1C
    BTFSS	STATUS, 2
    GOTO	TextMessageLoop28
    MOVLW	0x0D
    MOVWF	PCLATH
    MOVF	MsgIndex, W
    CALL	PageMsg2Text
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd
TextMessageLoop28:
    ; Page buffer write success - indicates write to page buffer.
    MOVF	MsgNumber, W
    XORLW	0x1D
    BTFSS	STATUS, 2
    GOTO	TextMessageLoop29
    MOVLW	0x0D
    MOVWF	PCLATH
    MOVF	MsgIndex, W
    CALL	PageMsg3Text
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd
TextMessageLoop29:
    ; Block write success - indicates completion of block write to ROM.
    MOVF	MsgNumber, W
    XORLW	0x1E
    BTFSS	STATUS, 2
    GOTO	TextMessageLoop2A
    MOVLW	0x0E
    MOVWF	PCLATH
    MOVF	MsgIndex, W
    CALL	BlockMsg1Text
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd
TextMessageLoop2A:
    ; Block write error - bytes specified exceeds page capacity.
    MOVF	MsgNumber, W
    XORLW	0x87
    BTFSS	STATUS, 2
    GOTO	TextMessageLoop2B
    MOVLW	0x0E
    MOVWF	PCLATH
    MOVF	MsgIndex, W
    CALL	BlockMsg2Text
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd
TextMessageLoop2B:
    ; Block write error - invalid address for block write.
    MOVF	MsgNumber, W
    XORLW	0x88
    BTFSS	STATUS, 2
    GOTO	TextMessageNotFound
    MOVLW	0x0E
    MOVWF	PCLATH
    MOVF	MsgIndex, W
    CALL	BlockMsg3Text
    CLRF	PCLATH
    GOTO	TextMessageLoopEnd
    
TextMessageNotFound:    
    RETURN				; in case we don't find a match
TextMessageLoopEnd:
    CLRF	PCLATH
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

    ORG		0x0800		    ; a page for message text (240 total words)

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
    
HelpMsgHText:				; 40 data words, message 02
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
    
HelpMsgAText:				; 56 data words, message 03
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
    
HelpMsgBText:			    ; 63 data words, message 04
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

    ORG	    0x900			 ; a page for message text (243 words)
    
ErrorMsgText:
    ; "ERROR - "			  10 data words, message 80
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

InputErrorMsgText:			; 18 data words, message 81
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

HelpMsgDText:					; 56 data words, message 05
    ; "D: Dump Memory. Usage - D. Displays all data in ROM."
    ADDWF   PCL, F
    RETLW   'D'
    RETLW   ':'
    RETLW   ' '
    RETLW   'D'
    RETLW   'u'
    RETLW   'm'
    RETLW   'p'
    RETLW   ' '
    RETLW   'M'
    RETLW   'e'
    RETLW   'm'
    RETLW   'o'
    RETLW   'r'
    RETLW   'y'
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
    RETLW   'D'
    RETLW   '.'
    RETLW   ' '
    RETLW   'D'
    RETLW   'i'
    RETLW   's'
    RETLW   'p'
    RETLW   'l'
    RETLW   'a'
    RETLW   'y'
    RETLW   's'
    RETLW   ' '
    RETLW   'a'
    RETLW   'l'
    RETLW   'l'
    RETLW   ' '
    RETLW   'd'
    RETLW   'a'
    RETLW   't'
    RETLW   'a'
    RETLW   ' '
    RETLW   'i'
    RETLW   'n'
    RETLW   ' '
    RETLW   'R'
    RETLW   'O'
    RETLW   'M'
    RETLW   '.'
    RETLW   0x0D
    RETLW   0x0A
    RETLW   0x00
    
HelpMsgFText:					; 73 data words, message 06
    ; "F: Fill Memory. Usage - F DD. Writes byte DD to each location in ROM."
    ADDWF   PCL, F
    RETLW   'F'
    RETLW   ':'
    RETLW   ' '
    RETLW   'F'
    RETLW   'i'
    RETLW   'l'
    RETLW   'l'
    RETLW   ' '
    RETLW   'M'
    RETLW   'e'
    RETLW   'm'
    RETLW   'o'
    RETLW   'r'
    RETLW   'y'
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
    RETLW   'F'
    RETLW   ' '
    RETLW   'D'
    RETLW   'D'
    RETLW   '.'
    RETLW   ' '
    RETLW   'W'
    RETLW   'r'
    RETLW   'i'
    RETLW   't'
    RETLW   'e'
    RETLW   's'
    RETLW   ' '
    RETLW   'b'
    RETLW   'y'
    RETLW   't'
    RETLW   'e'
    RETLW   ' '
    RETLW   'D'
    RETLW   'D'
    RETLW   ' '
    RETLW   't'
    RETLW   'o'
    RETLW   ' '
    RETLW   'e'
    RETLW   'a'
    RETLW   'c'
    RETLW   'h'
    RETLW   ' '
    RETLW   'l'
    RETLW   'o'
    RETLW   'c'
    RETLW   'a'
    RETLW   't'
    RETLW   'i'
    RETLW   'o'
    RETLW   'n'
    RETLW   ' '
    RETLW   'i'
    RETLW   'n'
    RETLW   ' '
    RETLW   'R'
    RETLW   'O'
    RETLW   'M'
    RETLW   '.'
    RETLW   0x0D
    RETLW   0x0A
    RETLW   0x00

HelpMsgLText:					; 61 data words, message 07
    ; "L: Lock ROM. Usage - L. Enables Software Data Protection."
    ADDWF   PCL, F
    RETLW   'L'
    RETLW   ':'
    RETLW   ' '
    RETLW   'L'
    RETLW   'o'
    RETLW   'c'
    RETLW   'k'
    RETLW   ' '
    RETLW   'R'
    RETLW   'O'
    RETLW   'M'
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
    RETLW   'L'
    RETLW   '.'
    RETLW   ' '
    RETLW   'E'
    RETLW   'n'
    RETLW   'a'
    RETLW   'b'
    RETLW   'l'
    RETLW   'e'
    RETLW   's'
    RETLW   ' '
    RETLW   'S'
    RETLW   'o'
    RETLW   'f'
    RETLW   't'
    RETLW   'w'
    RETLW   'a'
    RETLW   'r'
    RETLW   'e'
    RETLW   ' '
    RETLW   'D'
    RETLW   'a'
    RETLW   't'
    RETLW   'a'
    RETLW   ' '
    RETLW   'P'
    RETLW   'r'
    RETLW   'o'
    RETLW   't'
    RETLW   'e'
    RETLW   'c'
    RETLW   't'
    RETLW   'i'
    RETLW   'o'
    RETLW   'n'
    RETLW   '.'
    RETLW   0x0D
    RETLW   0x0A
    RETLW   0x00    
    
    ORG	    0xA00			 ; a page for message text (249 words)
    
HelpMsgPText:					; 74 data words, message 08
    ; "P: Page Load. Usage - P NN. Loads NN bytes (up to 64) for block write."
    ADDWF   PCL, F
    RETLW   'P'
    RETLW   ':'
    RETLW   ' '
    RETLW   'P'
    RETLW   'a'
    RETLW   'g'
    RETLW   'e'
    RETLW   ' '
    RETLW   'L'
    RETLW   'o'
    RETLW   'a'
    RETLW   'd'
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
    RETLW   'P'
    RETLW   ' '
    RETLW   'N'
    RETLW   'N'
    RETLW   '.'
    RETLW   ' '
    RETLW   'L'
    RETLW   'o'
    RETLW   'a'
    RETLW   'd'
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
    RETLW   '('
    RETLW   'u'
    RETLW   'p'
    RETLW   ' '
    RETLW   't'
    RETLW   'o'
    RETLW   ' '
    RETLW   '6'
    RETLW   '4'
    RETLW   ')'
    RETLW   ' '
    RETLW   'f'
    RETLW   'o'
    RETLW   'r'
    RETLW   ' '
    RETLW   'b'
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
    RETLW   '.'
    RETLW   0x0D
    RETLW   0x0A
    RETLW   0x00

HelpMsgRText:					; 65 data words, message 09
    ; "R: Read ROM. Usage - R NN. Reads NN bytes starting at address."
    ADDWF   PCL, F
    RETLW   'R'
    RETLW   ':'
    RETLW   ' '
    RETLW   'R'
    RETLW   'e'
    RETLW   'a'
    RETLW   'd'
    RETLW   ' '
    RETLW   'R'
    RETLW   'O'
    RETLW   'M'
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
    RETLW   'R'
    RETLW   ' '
    RETLW   'N'
    RETLW   'N'
    RETLW   '.'
    RETLW   ' '
    RETLW   'R'
    RETLW   'e'
    RETLW   'a'
    RETLW   'd'
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
    RETLW   's'
    RETLW   't'
    RETLW   'a'
    RETLW   'r'
    RETLW   't'
    RETLW   'i'
    RETLW   'n'
    RETLW   'g'
    RETLW   ' '
    RETLW   'a'
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

HelpMsgSText:					; 67 data words, message 0A
    ; "S: Size of Device. Usage - S NN. Sets size of ROM in kilobytes."    
    ADDWF   PCL, F
    RETLW   'S'
    RETLW   ':'
    RETLW   ' '
    RETLW   'S'
    RETLW   'i'
    RETLW   'z'
    RETLW   'e'
    RETLW   ' '
    RETLW   'o'
    RETLW   'f'
    RETLW   ' '
    RETLW   'D'
    RETLW   'e'
    RETLW   'v'
    RETLW   'i'
    RETLW   'c'
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
    RETLW   'S'
    RETLW   ' '
    RETLW   'N'
    RETLW   'N'
    RETLW   '.'
    RETLW   ' '
    RETLW   'S'
    RETLW   'e'
    RETLW   't'
    RETLW   's'
    RETLW   ' '
    RETLW   's'
    RETLW   'i'
    RETLW   'z'
    RETLW   'e'
    RETLW   ' '
    RETLW   'o'
    RETLW   'f'
    RETLW   ' '
    RETLW   'R'
    RETLW   'O'
    RETLW   'M'
    RETLW   ' '
    RETLW   'i'
    RETLW   'n'
    RETLW   ' '
    RETLW   'k'
    RETLW   'i'
    RETLW   'l'
    RETLW   'o'
    RETLW   'b'
    RETLW   'y'
    RETLW   't'
    RETLW   'e'
    RETLW   's'
    RETLW   '.'
    RETLW   0x0D
    RETLW   0x0A
    RETLW   0x00
    
LockMsgText:				 ; 21 data words, message 0F
    ; "ROM lock enabled."
    ADDWF   PCL, F
    RETLW   'R'
    RETLW   'O'
    RETLW   'M'
    RETLW   ' '
    RETLW   'l'
    RETLW   'o'
    RETLW   'c'
    RETLW   'k'
    RETLW   ' '
    RETLW   'e'
    RETLW   'n'
    RETLW   'a'
    RETLW   'b'
    RETLW   'l'
    RETLW   'e'
    RETLW   'd'
    RETLW   '.'
    RETLW   0x0D
    RETLW   0x0A
    RETLW   0x00
    
UnlockMsgText:				 ; 22 data words, message 10
    ; "ROM lock disabled."
    ADDWF   PCL, F
    RETLW   'R'
    RETLW   'O'
    RETLW   'M'
    RETLW   ' '
    RETLW   'l'
    RETLW   'o'
    RETLW   'c'
    RETLW   'k'
    RETLW   ' '
    RETLW   'd'
    RETLW   'i'
    RETLW   's'
    RETLW   'a'
    RETLW   'b'
    RETLW   'l'
    RETLW   'e'
    RETLW   'd'
    RETLW   '.'
    RETLW   0x0D
    RETLW   0x0A
    RETLW   0x00    
    
    ORG	    0xB00			 ; a page for message text (254 words)
    
HelpMsgUText:					; 64 data words, message 0B
    ; "U: Unlock ROM. Usage - U. Disables Software Data Protection."  
    ADDWF   PCL, F
    RETLW   'U'
    RETLW   ':'
    RETLW   ' '
    RETLW   'U'
    RETLW   'n'
    RETLW   'l'
    RETLW   'o'
    RETLW   'c'
    RETLW   'k'
    RETLW   ' '
    RETLW   'R'
    RETLW   'O'
    RETLW   'M'
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
    RETLW   'U'
    RETLW   '.'
    RETLW   ' '
    RETLW   'D'
    RETLW   'i'
    RETLW   's'
    RETLW   'a'
    RETLW   'b'
    RETLW   'l'
    RETLW   'e'
    RETLW   's'
    RETLW   ' '
    RETLW   'S'
    RETLW   'o'
    RETLW   'f'
    RETLW   't'
    RETLW   'w'
    RETLW   'a'
    RETLW   'r'
    RETLW   'e'
    RETLW   ' '
    RETLW   'D'
    RETLW   'a'
    RETLW   't'
    RETLW   'a'
    RETLW   ' '
    RETLW   'P'
    RETLW   'r'
    RETLW   'o'
    RETLW   't'
    RETLW   'e'
    RETLW   'c'
    RETLW   't'
    RETLW   'i'
    RETLW   'o'
    RETLW   'n'
    RETLW   '.'
    RETLW   0x0D
    RETLW   0x0A
    RETLW   0x00
    
HelpMsgWText:					; 67 data words, message 0C
    ; "W: Write Data. Usage - W DD. Writes byte DD to current address."     
    ADDWF   PCL, F
    RETLW   'W'
    RETLW   ':'
    RETLW   ' '
    RETLW   'W'
    RETLW   'r'
    RETLW   'i'
    RETLW   't'
    RETLW   'e'
    RETLW   ' '
    RETLW   'D'
    RETLW   'a'
    RETLW   't'
    RETLW   'a'
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
    RETLW   'W'
    RETLW   ' '
    RETLW   'D'
    RETLW   'D'
    RETLW   '.'
    RETLW   ' '
    RETLW   'W'
    RETLW   'r'
    RETLW   'i'
    RETLW   't'
    RETLW   'e'
    RETLW   's'
    RETLW   ' '
    RETLW   'b'
    RETLW   'y'
    RETLW   't'
    RETLW   'e'
    RETLW   ' '
    RETLW   'D'
    RETLW   'D'
    RETLW   ' '
    RETLW   't'
    RETLW   'o'
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

HelpMsgPLUSText:				; 56 data words, message 0D
    ; "+: Increment Address. Usage - +. Increments Address."
    ADDWF   PCL, F
    RETLW   '+'
    RETLW   ':'
    RETLW   ' '
    RETLW   'I'
    RETLW   'n'
    RETLW   'c'
    RETLW   'r'
    RETLW   'e'
    RETLW   'm'
    RETLW   'e'
    RETLW   'n'
    RETLW   't'
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
    RETLW   '+'
    RETLW   '.'
    RETLW   ' '
    RETLW   'I'
    RETLW   'n'
    RETLW   'c'
    RETLW   'r'
    RETLW   'e'
    RETLW   'm'
    RETLW   'e'
    RETLW   'n'
    RETLW   't'
    RETLW   's'
    RETLW   ' '
    RETLW   'A'
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

HelpMsgMINUSText:				; 56 data words, message 0E
    ; "-: Decrement Address. Usage - -. Decrements Address."
    ADDWF   PCL, F
    RETLW   '-'
    RETLW   ':'
    RETLW   ' '
    RETLW   'D'
    RETLW   'e'
    RETLW   'c'
    RETLW   'r'
    RETLW   'e'
    RETLW   'm'
    RETLW   'e'
    RETLW   'n'
    RETLW   't'
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
    RETLW   '-'
    RETLW   '.'
    RETLW   ' '
    RETLW   'D'
    RETLW   'e'
    RETLW   'c'
    RETLW   'r'
    RETLW   'e'
    RETLW   'm'
    RETLW   'e'
    RETLW   'n'
    RETLW   't'
    RETLW   's'
    RETLW   ' '
    RETLW   'A'
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

AddressMsgText:				; 11 data words, message 11
    ; "Address: "
    ADDWF   PCL, F
    RETLW   'A'
    RETLW   'd'
    RETLW   'd'
    RETLW   'r'
    RETLW   'e'
    RETLW   's'
    RETLW   's'
    RETLW   ':'
    RETLW   ' '
    RETLW   0x00

    ORG	    0xC00			; a page for message text (226 words)

IncFailMsgText:				; 23 data words, message 83
    ; "Increment overflow."
    ADDWF   PCL, F
    RETLW   'I'
    RETLW   'n'
    RETLW   'c'
    RETLW   'r'
    RETLW   'e'
    RETLW   'm'
    RETLW   'e'
    RETLW   'n'
    RETLW   't'
    RETLW   ' '
    RETLW   'o'
    RETLW   'v'
    RETLW   'e'
    RETLW   'r'
    RETLW   'f'
    RETLW   'l'
    RETLW   'o'
    RETLW   'w'
    RETLW   '.'
    RETLW   0x0D
    RETLW   0x0A
    RETLW   0x00

DecFailMsgText:				; 24 data words, message 84
    ; "Decrement underflow."
    ADDWF   PCL, F
    RETLW   'D'
    RETLW   'e'
    RETLW   'c'
    RETLW   'r'
    RETLW   'e'
    RETLW   'm'
    RETLW   'e'
    RETLW   'n'
    RETLW   't'
    RETLW   ' '
    RETLW   'u'
    RETLW   'n'
    RETLW   'd'
    RETLW   'e'
    RETLW   'r'
    RETLW   'f'
    RETLW   'l'
    RETLW   'o'
    RETLW   'w'
    RETLW   '.'
    RETLW   0x0D
    RETLW   0x0A
    RETLW   0x00    

InvalidSizeMsgText:			    ; 27 data words, message 85
    ; "ROM size not specified."
    ADDWF   PCL, F
    RETLW   'R'
    RETLW   'O'
    RETLW   'M'
    RETLW   ' '
    RETLW   's'
    RETLW   'i'
    RETLW   'z'
    RETLW   'e'
    RETLW   ' '
    RETLW   'n'
    RETLW   'o'
    RETLW   't'
    RETLW   ' '
    RETLW   's'
    RETLW   'p'
    RETLW   'e'
    RETLW   'c'
    RETLW   'i'
    RETLW   'f'
    RETLW   'i'
    RETLW   'e'
    RETLW   'd'
    RETLW   '.'
    RETLW   0x0D
    RETLW   0x0A
    RETLW   0x00   
    
DeviceSizeMsgText:				; 20 data words, message 12
    ; "ROM size set to "
    ADDWF   PCL, F
    RETLW   'R'
    RETLW   'O'
    RETLW   'M'
    RETLW   ' '
    RETLW   's'
    RETLW   'i'
    RETLW   'z'
    RETLW   'e'
    RETLW   ' '
    RETLW   's'
    RETLW   'e'
    RETLW   't'
    RETLW   ' '
    RETLW   't'
    RETLW   'o'
    RETLW   ' '
    RETLW   0x00

InvalidAddrMsgText:				; 26 data words, message 86
    ; "Address out of bounds."
    ADDWF   PCL, F
    RETLW   'A'
    RETLW   'd'
    RETLW   'd'
    RETLW   'r'
    RETLW   'e'
    RETLW   's'
    RETLW   's'
    RETLW   ' '
    RETLW   'o'
    RETLW   'u'
    RETLW   't'
    RETLW   ' '
    RETLW   'o'
    RETLW   'f'
    RETLW   ' '
    RETLW   'b'
    RETLW   'o'
    RETLW   'u'
    RETLW   'n'
    RETLW   'd'
    RETLW   's'
    RETLW   '.'
    RETLW   0x0D
    RETLW   0x0A
    RETLW   0x00

WriteByteMsg1Text:				; 20 data words, message 13
    ; "Writing data byte "
    ADDWF   PCL, F
    RETLW   'W'
    RETLW   'r'
    RETLW   'i'
    RETLW   't'
    RETLW   'i'
    RETLW   'n'
    RETLW   'g'
    RETLW   ' '
    RETLW   'd'
    RETLW   'a'
    RETLW   't'
    RETLW   'a'
    RETLW   ' '
    RETLW   'b'
    RETLW   'y'
    RETLW   't'
    RETLW   'e'
    RETLW   ' '
    RETLW   0x00

WriteByteMsg2Text:				; 19 data words, message 14
    ; " to ROM location "
    ADDWF   PCL, F
    RETLW   ' '
    RETLW   't'
    RETLW   'o'
    RETLW   ' '
    RETLW   'R'
    RETLW   'O'
    RETLW   'M'
    RETLW   ' '
    RETLW   'l'
    RETLW   'o'
    RETLW   'c'
    RETLW   'a'
    RETLW   't'
    RETLW   'i'
    RETLW   'o'
    RETLW   'n'
    RETLW   ' '
    RETLW   0x00
    
WriteByteMsg3Text:				; 25 data words, message 15
    ; " read from ROM address "
    ADDWF   PCL, F
    RETLW   ' '
    RETLW   'r'
    RETLW   'e'
    RETLW   'a'
    RETLW   'd'
    RETLW   ' '
    RETLW   'f'
    RETLW   'r'
    RETLW   'o'
    RETLW   'm'
    RETLW   ' '
    RETLW   'R'
    RETLW   'O'
    RETLW   'M'
    RETLW   ' '
    RETLW   'a'
    RETLW   'd'
    RETLW   'd'
    RETLW   'r'
    RETLW   'e'
    RETLW   's'
    RETLW   's'
    RETLW   ' '
    RETLW   0x00
    
FillMsg1Text:					; 27 data words, message 16
    ; " will be written to fill "
    ADDWF   PCL, F
    RETLW   ' '
    RETLW   'w'
    RETLW   'i'
    RETLW   'l'
    RETLW   'l'
    RETLW   ' '
    RETLW   'b'
    RETLW   'e'
    RETLW   ' '
    RETLW   'w'
    RETLW   'r'
    RETLW   'i'
    RETLW   't'
    RETLW   't'
    RETLW   'e'
    RETLW   'n'
    RETLW   ' '
    RETLW   't'
    RETLW   'o'
    RETLW   ' '
    RETLW   'f'
    RETLW   'i'
    RETLW   'l'
    RETLW   'l'
    RETLW   ' '
    RETLW   0x00
    
FillMsg2Text:					; 15 data words, message 17
    ; " kilobytes."
    ADDWF   PCL, F
    RETLW   ' '
    RETLW   'k'
    RETLW   'i'
    RETLW   'l'
    RETLW   'o'
    RETLW   'b'
    RETLW   'y'
    RETLW   't'
    RETLW   'e'
    RETLW   's'
    RETLW   '.'
    RETLW   0x0D
    RETLW   0x0A
    RETLW   0x00
    
    ORG	    0xD00			; a page for message text (219 words)
    
FillMsg3Text:				; 48 data words, message 18
    ; "Press Y to continue, any other key to cancel. "
    ADDWF   PCL, F
    RETLW   'P'
    RETLW   'r'
    RETLW   'e'
    RETLW   's'
    RETLW   's'
    RETLW   ' '
    RETLW   'Y'
    RETLW   ' '
    RETLW   't'
    RETLW   'o'
    RETLW   ' '
    RETLW   'c'
    RETLW   'o'
    RETLW   'n'
    RETLW   't'
    RETLW   'i'
    RETLW   'n'
    RETLW   'u'
    RETLW   'e'
    RETLW   ','
    RETLW   ' '
    RETLW   'a'
    RETLW   'n'
    RETLW   'y'
    RETLW   ' '
    RETLW   'o'
    RETLW   't'
    RETLW   'h'
    RETLW   'e'
    RETLW   'r'
    RETLW   ' '
    RETLW   'k'
    RETLW   'e'
    RETLW   'y'
    RETLW   ' '
    RETLW   't'
    RETLW   'o'
    RETLW   ' '
    RETLW   'c'
    RETLW   'a'
    RETLW   'n'
    RETLW   'c'
    RETLW   'e'
    RETLW   'l'
    RETLW   '.'
    RETLW   ' '
    RETLW   0x00
    
FillMsg4Text:				    ; 28 data words, message 19
    ; "Canceled fill operation."
    ADDWF   PCL, F
    RETLW   'C'
    RETLW   'a'
    RETLW   'n'
    RETLW   'c'
    RETLW   'e'
    RETLW   'l'
    RETLW   'e'
    RETLW   'd'
    RETLW   ' '
    RETLW   'f'
    RETLW   'i'
    RETLW   'l'
    RETLW   'l'
    RETLW   ' '
    RETLW   'o'
    RETLW   'p'
    RETLW   'e'
    RETLW   'r'
    RETLW   'a'
    RETLW   't'
    RETLW   'i'
    RETLW   'o'
    RETLW   'n'
    RETLW   '.'
    RETLW   0x0D
    RETLW   0x0A
    RETLW   0x00
    
FillMsg5Text:				    ; 34 data words, message 1A
    ; " written to all ROM addresses."
    ADDWF   PCL, F
    RETLW   ' '
    RETLW   'w'
    RETLW   'r'
    RETLW   'i'
    RETLW   't'
    RETLW   't'
    RETLW   'e'
    RETLW   'n'
    RETLW   ' '
    RETLW   't'
    RETLW   'o'
    RETLW   ' '
    RETLW   'a'
    RETLW   'l'
    RETLW   'l'
    RETLW   ' '
    RETLW   'R'
    RETLW   'O'
    RETLW   'M'
    RETLW   ' '
    RETLW   'a'
    RETLW   'd'
    RETLW   'd'
    RETLW   'r'
    RETLW   'e'
    RETLW   's'
    RETLW   's'
    RETLW   'e'
    RETLW   's'
    RETLW   '.'
    RETLW   0x0D
    RETLW   0x0A
    RETLW   0x00

PageMsg1Text:				    ; 25 data words, message 1B
    ; "Page buffer contents:"
    ADDWF   PCL, F
    RETLW   'P'
    RETLW   'a'
    RETLW   'g'
    RETLW   'e'
    RETLW   ' '
    RETLW   'b'
    RETLW   'u'
    RETLW   'f'
    RETLW   'f'
    RETLW   'e'
    RETLW   'r'
    RETLW   ' '
    RETLW   'c'
    RETLW   'o'
    RETLW   'n'
    RETLW   't'
    RETLW   'e'
    RETLW   'n'
    RETLW   't'
    RETLW   's'
    RETLW   ':'
    RETLW   0x0D
    RETLW   0x0A
    RETLW   0x00

PageMsg2Text:				    ; 49 data words, message 1C
    ; "Enter hexadecimal bytes. Press ENTER to stop."
    ADDWF   PCL, F
    RETLW   'E'
    RETLW   'n'
    RETLW   't'
    RETLW   'e'
    RETLW   'r'
    RETLW   ' '
    RETLW   'h'
    RETLW   'e'
    RETLW   'x'
    RETLW   'a'
    RETLW   'd'
    RETLW   'e'
    RETLW   'c'
    RETLW   'i'
    RETLW   'm'
    RETLW   'a'
    RETLW   'l'
    RETLW   ' '
    RETLW   'b'
    RETLW   'y'
    RETLW   't'
    RETLW   'e'
    RETLW   's'
    RETLW   '.'
    RETLW   ' '
    RETLW   'P'
    RETLW   'r'
    RETLW   'e'
    RETLW   's'
    RETLW   's'
    RETLW   ' '
    RETLW   'E'
    RETLW   'N'
    RETLW   'T'
    RETLW   'E'
    RETLW   'R'
    RETLW   ' '
    RETLW   't'
    RETLW   'o'
    RETLW   ' '
    RETLW   's'
    RETLW   't'
    RETLW   'o'
    RETLW   'p'
    RETLW   '.'
    RETLW   0x0D
    RETLW   0x0A
    RETLW   0x00

PageMsg3Text:				    ; 35 data words, message 1D
    ; " bytes loaded into page buffer."
    ADDWF   PCL, F
    RETLW   ' '
    RETLW   'b'
    RETLW   'y'
    RETLW   't'
    RETLW   'e'
    RETLW   's'
    RETLW   ' '
    RETLW   'l'
    RETLW   'o'
    RETLW   'a'
    RETLW   'd'
    RETLW   'e'
    RETLW   'd'
    RETLW   ' '
    RETLW   'i'
    RETLW   'n'
    RETLW   't'
    RETLW   'o'
    RETLW   ' '
    RETLW   'p'
    RETLW   'a'
    RETLW   'g'
    RETLW   'e'
    RETLW   ' '
    RETLW   'b'
    RETLW   'u'
    RETLW   'f'
    RETLW   'f'
    RETLW   'e'
    RETLW   'r'
    RETLW   '.'
    RETLW   0x0D
    RETLW   0x0A
    RETLW   0x00
    
    ORG	    0xE00		    ; a page for message text (123 words)
    
BlockMsg1Text:					; 42 data words, message 1E
    ; " bytes written to ROM. Current address: "
    ADDWF   PCL, F
    RETLW   ' '
    RETLW   'b'
    RETLW   'y'
    RETLW   't'
    RETLW   'e'
    RETLW   's'
    RETLW   ' '
    RETLW   'w'
    RETLW   'r'
    RETLW   'i'
    RETLW   't'
    RETLW   't'
    RETLW   'e'
    RETLW   'n'
    RETLW   ' '
    RETLW   't'
    RETLW   'o'
    RETLW   ' '
    RETLW   'R'
    RETLW   'O'
    RETLW   'M'
    RETLW   '.'
    RETLW   ' '
    RETLW   'C'
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
    RETLW   ':'
    RETLW   ' '
    RETLW   0x00
    
BlockMsg2Text:			    ; 37 data words, message 87
    ; " not enough bytes in page buffer."
    ADDWF   PCL, F
    RETLW   ' '
    RETLW   'n'
    RETLW   'o'
    RETLW   't'
    RETLW   ' '
    RETLW   'e'
    RETLW   'n'
    RETLW   'o'
    RETLW   'u'
    RETLW   'g'
    RETLW   'h'
    RETLW   ' '
    RETLW   'b'
    RETLW   'y'
    RETLW   't'
    RETLW   'e'
    RETLW   's'
    RETLW   ' '
    RETLW   'i'
    RETLW   'n'
    RETLW   ' '
    RETLW   'p'
    RETLW   'a'
    RETLW   'g'
    RETLW   'e'
    RETLW   ' '
    RETLW   'b'
    RETLW   'u'
    RETLW   'f'
    RETLW   'f'
    RETLW   'e'
    RETLW   'r'
    RETLW   '.'
    RETLW   0x0D
    RETLW   0x0A
    RETLW   0x00

BlockMsg3Text:			    ; 44 data words, message 88
    ; " block write must start at 64-byte page."
    ADDWF   PCL, F
    RETLW   ' '
    RETLW   'b'
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
    RETLW   ' '
    RETLW   'm'
    RETLW   'u'
    RETLW   's'
    RETLW   't'
    RETLW   ' '
    RETLW   's'
    RETLW   't'
    RETLW   'a'
    RETLW   'r'
    RETLW   't'
    RETLW   ' '
    RETLW   'a'
    RETLW   't'
    RETLW   ' '
    RETLW   '6'
    RETLW   '4'
    RETLW   '-'
    RETLW   'b'
    RETLW   'y'
    RETLW   't'
    RETLW   'e'
    RETLW   ' '
    RETLW   'p'
    RETLW   'a'
    RETLW   'g'
    RETLW   'e'
    RETLW   '.'
    RETLW   0x0D
    RETLW   0x0A
    RETLW   0x00    
    
    END
