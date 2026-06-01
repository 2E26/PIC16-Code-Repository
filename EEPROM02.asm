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
	
	CBLOCK 0x20
	    D1
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
	ENDC
	
	CBLOCK 0x40
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
; B - "Block Write ROM" writes a block of 64 bytes into ROM
; D - "Dump" displays entire ROM contents on the serial monitor
; F - "Fill" writes a specified byte to all ROM locations
; H - "Help" displays a help menu with commands, syntax, and function
; L - "Lock" enables software data protection
; R - "Read ROM" reads ROM and displays it on the serial monitor
; S - "Size" sets the size of the ROM in kB. Must be done first
; U - "Unlock" disables software data protection
; W - "Write ROM" writes a single byte to ROM
	
START:
    BCF		STATUS, RP1	    ; set memory bank 1
    BSF		STATUS, RP0
    CLRF	TRISB		    ; set PortB to output
    CLRF	TRISD		    ; set PortD to output
    MOVLW	0x80		    ; set PortC to output except RC7
    MOVWF	TRISC		    ; configure PORTC
    MOVLW	0x00		    ; set PortA to output
    MOVWF	TRISA		    ; configure PortA
    MOVLW	0x06		    ; configure ADCON1
    MOVWF	ADCON1		    ; all A/D ports are digital ports
    BCF		STATUS, 6	    ; set memory bank 0
    BCF		STATUS, 5
    BSF		PORTA, 1	    ; set control bits /WE, /CE, /OE
    BSF		PORTA, 2	    ; to initial states of high
    BSF		PORTA, 3
    CALL	USART_Init	    ; initiate serial port functions
    MOVLW	0x05		    ; dictate 5 mS delay
    MOVWF	D1		    ; and set it into memory
    CALL	EEPROM_msDelay	    ; call a delay function using D1
    MOVLW	0x01		    ; select message one
    CALL	TextMessage
    
LOOP:

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
TextMessage:
    CLRF	MsgIndex	    ; clear the counter used to display text 
    MOVWF	MsgNumber	    ; store the message number we're calling
TextMessageLoop:
    XORLW	0x01		    ; check for message #1
    BTFSS	STATUS, 2	    ; is zero flag set?
    GOTO	TextMessageLoop01   ; if not, check the next message
    MOVLW	0x04		    ; preload the page our message is on
    MOVWF	PCLATH		    ; into PCLATH
    MOVF	MsgIndex, W	    ; load character counter into W
    CALL	StartMsgText	    ; get a string character into W
    GOTO	TextMessageLoopEnd  ; proceed to printing it
TextMessageLoop01:
    MOVF	MsgNumber, W
    XORLW	0x02
    BTFSS	STATUS, 2
    GOTO	TextMessageLoop02
    MOVLW	0x05
    MOVWF	PCLATH
    MOVF	MsgIndex, W
    CALL	HelpMsgText
    GOTO	TextMessageLoopEnd    
TextMessageLoop02:
    MOVF	MsgNumber, W
    XORLW	0x03
    BTFSS	STATUS, 2
    GOTO	TextMessageLoop03
    MOVLW	0x__
    MOVWF	PCLATH
    MOVF	MsgIndex, W
    CALL	_____
    GOTO	TextMessageLoopEnd
TextMessageLoop03:
    ; another message routine here
    
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

    ORG		0x0400		    ; a page for the intro message (others?)

StartMsgText:			    ; 81 data words
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
    
    ORG		0x0500		; place the help message on its own page
    
HelpMsgTxt:
    ADDWF	PCL, F
    RETLW
    
	END
