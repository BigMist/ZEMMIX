10 ' OPL4SIN: chord of sine waves on the MoonSound (OPL4 wave part)
20 ' a sine of NS samples (8 or 16 bit) at 201000h, read at 22.05 kHz at OCT 0
30 ' FN 0, tone 384; C4 E4 G4 C5; any key: notes off. ZEMMIX-0au.11
40 DEFINT A-Z: DIM N!(3): N!(0)=261.63: N!(1)=329.63: N!(2)=392!: N!(3)=523.25
50 INPUT "Samples per period (64 or 256)";NS: IF NS<>64 AND NS<>256 THEN 50
60 INPUT "Bits (8 or 16)";NB: IF NB<>8 AND NB<>16 THEN 60
70 PRINT "Read rate of C4 / C5:";INT(N!(0)*NS);"/";INT(N!(3)*NS);"Hz (output 44100)"
80 OUT &HC6,5: OUT &HC7,3: ' NEW2: OPL4 mode
90 R=2: D=&H11: GOSUB 500: ' memory access, headers of tones 384+ at 200000h
100 PRINT "Writing the sine..."
110 GOSUB 600: OUT &H7E,6
120 FOR I=0 TO NS-1: GOSUB 700: IF NB=16 THEN OUT &H7F,H
130 OUT &H7F,L: NEXT I
140 PRINT "Reading it back...": GOSUB 600: OUT &H7E,6: BD=0
150 FOR I=0 TO NS-1: GOSUB 700: IF NB=16 THEN G=INP(&H7F): IF G<>H THEN GOSUB 800
160 G=INP(&H7F): IF G<>L THEN GOSUB 800
170 NEXT I: PRINT "Bytes read back wrong:";BD
180 ' header of tone 384: start 201000h, loop 0, end NS, AR 15, RR 15
190 R=3: D=&H20: GOSUB 500: R=4: D=0: GOSUB 500: R=5: D=0: GOSUB 500
200 E!=65536!-NS: EH=INT(E!/256): EL=E!-EH*256!
210 OUT &H7E,6
220 FOR I=0 TO 11: READ D: IF I=0 AND NB=16 THEN D=D OR &H80
230 IF I=5 THEN D=EH ELSE IF I=6 THEN D=EL
240 OUT &H7F,D: NEXT I
250 DATA &H20,&H10,&H00, &H00,&H00, &HFF,&H00, &H00,&HF0,&H00,&H0F,&H00
260 R=2: D=&H10: GOSUB 500: ' back to play mode
270 FOR C=0 TO 3
280 F!=N!(C)/(22050!/NS): O=INT(LOG(F!)/LOG(2)): FQ=INT((F!/2^O-1)*1024+.5)
290 PRINT USING "Note ##: ####.## Hz  OCT ## FN ####";C;N!(C);O;FQ
300 R=&H68+C: D=0: GOSUB 500
310 R=&H38+C: D=(O AND 15)*16 OR (FQ\128): GOSUB 500
320 R=&H20+C: D=(FQ AND 127)*2 OR 1: GOSUB 500
330 R=&H08+C: D=&H80: GOSUB 500: ' tone 384: loads the header
340 IF INP(&HC4) AND 2 THEN 340: ' LD
350 R=&H50+C: D=&H20: GOSUB 500: ' level
360 R=&H68+C: D=&H80: GOSUB 500: ' key on, pan centre
370 NEXT C
380 PRINT "Playing. Any key to stop.": PRINT "FIFO of the OPL4 audio (ZEMMIX):": Y=CSRLIN
390 GOSUB 900: IF INKEY$="" THEN 390
400 FOR C=0 TO 3: R=&H68+C: D=0: GOSUB 500: NEXT C
410 END
500 OUT &H7E,R: OUT &H7F,D: RETURN
600 R=3: D=&H20: GOSUB 500: R=4: D=&H10: GOSUB 500: R=5: D=0: GOSUB 500: RETURN
700 ' sample I: H, L (16 bit: high byte first; 8 bit: L)
710 V!=SIN(I*6.283185/NS)*30000!: IF V!<0 THEN V!=V!+65536!
720 H=INT(V!/256): L=INT(V!-H*256!): IF NB=8 THEN L=H
730 RETURN
800 BD=BD+1: IF BD<=8 THEN PRINT USING "  bad sample ### read ###";I;G
810 RETURN
900 OUT &H7E,&HF4: A!=INP(&H7F): OUT &H7E,&HF5: A!=A!+256!*INP(&H7F)
910 OUT &H7E,&HF6: B!=INP(&H7F): OUT &H7E,&HF7: B!=B!+256!*INP(&H7F)
920 LOCATE 0,Y: PRINT USING "  empty ##### times, full ##### times";A!;B!: RETURN
