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

EEPROM_DecrementAddress:
;-------------------------------------------------------------------------------
; DecrementAddress: - decrements address stored in memory by 1, then sets the
;		      new address. Underflow (0000-FFFF) returns with carry
;		      flag set instead.
; Memory: AddressL, AddressH
; Inputs: none
; Destroys: W register
; Outputs: decreases address by 1, new address on PORTA, PORTB, PORTC, or carry
;	   flag set in case of overflow
;-------------------------------------------------------------------------------
	MOVF		AddressL, W	    ; check if low byte is 0
	XORLW		0x00		    ; 
	BTFSC		STATUS, 2	    ; if zero flag is set
	GOTO		Underflow_L	    ; handle low byte 0
	DECF		AddressL, F	    ; otherwise, AddressL -= 1
	BCF		STATUS, 0
	RETURN
Underflow_L:
	MOVF		AddressH, W	    ; check if high byte is also 0
	XORLW		0x00		    ;
	BTFSC		STATUS, 2	    ; if zero flag is set
	GOTO		Underflow_H	    ; handle address = 0x0000
	DECF		AddressH, F	    ; otherwise, AddressH -= 1
	MOVLW		0xFF		    ; roll over low byte
	MOVWF		AddressL
	BCF		STATUS, 0
	RETURN
Underflow_H:
	BSF		STATUS, 0	    ; set carry flag
	RETURN
	
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
; Destroys: W (if D1 is zero at time of calling)
; Outputs: none
; 
; The delay can be calculated by the following formula:
; ((((D3-1) * 3 µS) + 5µS) * (D2-1) + 7µS) + (6µS) + (7µS * (D1 - 1))
;
; NOTE: this is accurate only for an oscillator frequency of 4.000 MHz
;-------------------------------------------------------------------------------
	MOVF		D1, F	    ; check if D1 is zero by writing to itself
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

EEPROM_BoundCheck:
;-------------------------------------------------------------------------------
; BoundCheck: - checks whether the prospective address is within user-defined
;               limits. Size is in number of kilobytes
; Memory: DeviceSize, Temp, InByteH
; Inputs: high byte of new address stored in InByteH
; Destroys: Temp, W
; Outputs: carry = 1 if current address is higher than maximum ROM size
;
; This routine checks the boundary by multiplying device size (in kB) by four
; and checking it against the high byte of the address the program is trying to
; change to. If it is greater than or equal to this number, return a carry
; flag set indicating that is not a valid address. It also allows any address
; if DeviceSize is 64, as any 16-bit address would be valid on a 64 kB ROM.
;
; Example - address is commanded to become 0x1001. Size of ROM has been stated
;           to be 4 kB (0b00000100). Multiply size by four (0b00010000) and
;           compare to the commanded address (0b0001000000000001). Since the
;           high byte of the address is equal to four times the size, this is
;           not a valid address (for a 4 kB ROM, the address span would
;           be limited to 0x0000 - 0x0FFF.
; 
;-------------------------------------------------------------------------------
    MOVF	DeviceSize, W			    ; get device size
    XORLW	0x40				    ; compare it to 64
    BTFSC	STATUS, 2			    ; was it equal?
    GOTO	EEPROM_BoundCheck_Good		    ; any address is valid
    MOVF	DeviceSize, W			    ; get size back
    MOVWF	Temp				    ; save it to memory
    BCF		STATUS, 0
    RLF		Temp, F				    ; rotate it left twice
    BCF		STATUS, 0
    RLF		Temp, W				    ; multiply by four
    SUBWF	InByteH, W			    ; W = InByteH - W
    BTFSC	STATUS, 0
    GOTO	EEPROM_BoundCheck_Bad
EEPROM_BoundCheck_Good:
    BCF		STATUS, 0
    RETURN
EEPROM_BoundCheck_Bad:
    BSF		STATUS, 0
    RETURN
