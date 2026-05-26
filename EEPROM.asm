; EEPROM.asm
;
; A library file of EEPROM functions designed to program ROM chips
; in the AT28C family. These are mainly for use in the programming of 8-bit
; computers such as 6502 and Z80 types. The PIC used for this library is the
; PIC16F877A. This library is used in conjunction with USART.asm

; I/O pins used with these functions:
;
; PORTA(0) - A14
; PORTA(1) - /WE (write enable)
; PORTA(2) - /CE (chip enable)
; PORTA(3) - /OE (output enable)
; PORTB(0-7) - A0-A7
; PORTC(0-5) - A8-A13
; PORTC(6-7) - used with USART library
; PORTD(0-7) - D0-D7
    
EEPROM_SetAddress:
;-------------------------------------------------------------------------------
; SetAddress: - places address information stored in memory onto I/O pins
; Memory: AddressL, AddressH, Temp
; Inputs: address information stored in AddressL/AddressH
; Destroys: W
; Outputs: PORTB, PORTC(0-5), PORTA(0)
;-------------------------------------------------------------------------------
	BCF		STATUS, 5	; select bank 0
	BCF		STATUS, 6
	MOVF		AddressL, 0	; grab the low byte of address stored in memory
	MOVWF		PORTB		; store it in PORTB
	MOVF		PORTC, 0	; store PORTC in W
	ANDLW		0xC0		; clear out all but the two high bits
	MOVWF		Temp		; and store it in memory
	MOVF		AddressH, 0	; grab the high byte of address stored in memory
	ANDLW		0x3F		; mask out the two highest bits
	IORWF		Temp, 0		; restore the two high bits originally in PORTC
	MOVWF		PORTC		; write the address to PORTC 0-5, preserving TX/RX bits
	BSF		PORTA, 0	; make RA0 = 1
	BTFSS		AddressH, 6	; if bit is supposed to be 0
	BCF		PORTA, 0	; then make RA0 = 0
	RETURN
	
EEPROM_IncrementAddress:
;-------------------------------------------------------------------------------
; IncrementAddress: - increments address stored in memory by 1, then sets the
;		      new address. Overflow (FFFF - 0000) returns with carry
;		      flag set instead.
; Memory: AddressL, AddressH
; Inputs: none
; Destroys: none
; Outputs: increases address by 1, new address on PORTA, PORTB, PORTC, or carry
;	   flag set in case of overflow
;-------------------------------------------------------------------------------
	INCFSZ		AddressL, 1
	GOTO		NoOverflow
	INCFSZ		AddressH, 1
	GOTO		NoOverflow
	GOTO		Overflow
NoOverflow:
	CALL		EEPROM_SetAddress
	BCF		STATUS, 0
	RETURN
Overflow:
	BSF		STATUS, 0
	RETURN

EEPROM_WriteByte:
;-------------------------------------------------------------------------------
; WriteByte: - writes the byte stored in W into EEPROM. This assumes TRISD is
;	       configured so that all of PORTD are output pins.
; Memory: none
; Inputs: W
; Destroys: PORTD
; Outputs: none
;-------------------------------------------------------------------------------
	BSF		PORTA, 3	; /OE high
	MOVWF		PORTD		; send W to output pins
	BCF		PORTA, 2	; /CE low
	NOP
	NOP
	BCF		PORTA, 1	; /WE low
	BSF		PORTA, 1	; /WE high
	NOP
	NOP
	BSF		PORTA, 2	; /CE high
	RETURN
	
EEPROM_ReadByte:
;-------------------------------------------------------------------------------
; ReadByte: - reads the byte stored in EEPROM at the predetermined address. This
;	      assumes TRISD is configured for PORTD to be all input pins.
; Memory: none
; Inputs: none
; Destroys: none
; Outputs: W - byte read from EEPROM
;-------------------------------------------------------------------------------
	BCF		PORTA, 2	; make /CE low (chip enable)
	NOP
	BCF		PORTA, 3	; make /OE low (enable read)
	NOP
	MOVF		PORTD, W	; get the byte read at PORTD into W
	NOP
	BSF		PORTA, 3	; make /OE high again
	NOP
	BSF		PORTA, 2	; make /CE high again
	RETURN

EEPROM_msDelay:	
;-------------------------------------------------------------------------------
; msDelay: - wastes a certain amount of cycles to approximate a millisecond
;	     delay, allows user to select number of milliseconds by loading
;	     D1 with a number of repetitions
; Memory: D1, D2, D3
; Inputs: D1 - number of milliseconds to delay
; Destroys: W
; Outputs: none
; 
; The delay can be calculated by the following formula:
; ((((D3-1) * 3 µS) + 5µS) * (D2-1) + 7µS) + (6µS) + (7µS * (D1 - 1))
;-------------------------------------------------------------------------------
	MOVF		D1, W	    ; check if D1 is zero by moving it to W
	BTFSS		STATUS, 2   ; and checking the zero flag
	GOTO		Del1	    ; if not, move along
	MOVLW		0x01	    ; if so, make D1 = 1 to run loop
	MOVWF		D1	    ; at least one time
Del1:	MOVLW		18	    ; loop 18 * 19 = 342 times
	MOVWF		D2
Del2:	MOVLW		19
	MOVWF		D3
Del3:	DECFSZ		D3, F	    ; 1 µS, 2 µS if next instruction is skipped
	GOTO		Del3	    ; 2 µS
	DECFSZ		D2, F	    ; 1 or 2 µS
	GOTO		Del2	    ; 2 µS
	DECFSZ		D1, F	    ; 1 or 2 µS
	GOTO		Del1	    ; 2 µS
	RETURN

EEPROM_SDP_Off:
;-------------------------------------------------------------------------------
; SDP_Off: - disables software data protection (write protect). Only usable with
;	     AT28C256 EEPROM chips currently.
; Memory: AddressL, AddressH
; Inputs: none
; Destroys: W
; Outputs: none
;
; Software Data Protection is disabled by writing six specific bytes and
; addresses. This generates a write cycle, meaning we wait for it to clear.
; Address	Byte
; 0x5555	AA
; 0x2AAA	55
; 0x5555	80
; 0x5555	AA
; 0x2AAA	AA
; 0x5555	20
;-------------------------------------------------------------------------------
	MOVLW		0x55			; write one
	MOVWF		AddressL
	MOVWF		AddressH
	CALL		EEPROM_SetAddress
	MOVLW		0xAA
	CALL		EEPROM_WriteByte
	
	MOVLW		0xAA			; write two
	MOVWF		AddressL
	MOVLW		0x2A
	MOVWF		AddressH
	CALL		EEPROM_SetAddress
	MOVLW		0x55
	CALL		EEPROM_WriteByte
	
	MOVLW		0x55			; write three
	MOVWF		AddressL
	MOVWF		AddressH
	CALL		EEPROM_SetAddress
	MOVLW		0x80
	CALL		EEPROM_WriteByte
	
	MOVLW		0x55			; write four
	MOVWF		AddressL
	MOVWF		AddressH
	CALL		EEPROM_SetAddress
	MOVLW		0xAA
	CALL		EEPROM_WriteByte
	
	MOVLW		0xAA			; write five
	MOVWF		AddressL
	MOVLW		0x2A
	MOVWF		AddressH
	CALL		EEPROM_SetAddress
	MOVLW		0x55
	CALL		EEPROM_WriteByte

	MOVLW		0x55			; write six
	MOVWF		AddressL
	MOVWF		AddressH
	CALL		EEPROM_SetAddress
	MOVLW		0x20
	CALL		EEPROM_WriteByte

	MOVLW		0x0A			; ten mS delay
	MOVWF		D1
	CALL		EEPROM_msDelay
	RETURN
	
EEPROM_SDP_On:
;-------------------------------------------------------------------------------
; SDP_Off: - enables software data protection (write protect). Only usable with
;	     AT28C256 EEPROM chips currently.
; Memory: AddressL, AddressH
; Inputs: none
; Destroys: W
; Outputs: none
;
; Software Data Protection is ensabled by writing three specific bytes and
; addresses. This generates a write cycle, meaning we wait for it to clear.
; Address	Byte
; 0x5555	AA
; 0x2AAA	55
; 0x5555	A0
;-------------------------------------------------------------------------------
	MOVLW		0x55			; write one
	MOVWF		AddressL
	MOVWF		AddressH
	CALL		EEPROM_SetAddress
	MOVLW		0xAA
	CALL		EEPROM_WriteByte
	
	MOVLW		0xAA			; write two
	MOVWF		AddressL
	MOVLW		0x2A
	MOVWF		AddressH
	CALL		EEPROM_SetAddress
	MOVLW		0x55
	CALL		EEPROM_WriteByte
	
	MOVLW		0x55			; write three
	MOVWF		AddressL
	MOVWF		AddressH
	CALL		EEPROM_SetAddress
	MOVLW		0xA0
	CALL		EEPROM_WriteByte

	MOVLW		0x0A			; ten mS delay
	MOVWF		D1
	CALL		EEPROM_msDelay
	RETURN
