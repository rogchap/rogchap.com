---
title: "Building an Assembler"
date: 2019-07-28T13:04:23+10:00
type: post
tags:
- Go
---

I recently completed the first part of the awesome "[From Nand to Tetris](https://www.nand2tetris.org)" course. For project 6 you build an Assembler for the HACK Computer using a high level language of your choice; naturally I did my project using Go (Golang). 

The HACK Assembly language is very simple, and an Assembler could be written using string manipulation in less than 50 lines of code. However, I've always wanted to build a lexer/scanner and parser in Go and thought this would be a great little project to do so. 
```c
// HACK Assembly Language example
// Draws a rectangle at the top-left corner of the screen.

   @0               // this is an "A" instruction
   D=M              // this is a "C" instruction
   @INFINITE_LOOP
   D;JLE            // this is also a "C" instruction
   @counter         
   M=D
   @SCREEN          // this is also an "A" instruction
   D=A
   @address
   M=D
(LOOP)              // this is a Label
   @address
   A=M
   M=-1
   @address
   D=M
   @32
   D=D+A
   @address
   M=D
   @counter
   MD=M-1
   @LOOP
   D;JGT
(INFINITE_LOOP)
   @INFINITE_LOOP
   0;JMP
```
## Defining the tokens
The HACK assembly language has 2 instruction types: "A" and "C"; it also has "`goto`" labels. Although each instruction can be broken down into parts, I decided to keep my tokens super simple:
```go
type Token int

const ( 
    ILLEGAL Token = iota
	EOF
	COMMENT
	LABEL
	A_INSTRUCTION
	C_INSTRUCTION
)
```  
## The Scanner
My scanner is based on the [standard library's Go Scanner](https://golang.org/src/go/scanner/scanner.go):
```go
type Scanner struct {
	src      []byte
	ch       rune // current character
	offset   int  // character offset
	rdOffset int  // reading offset
}

const bom = 0xFEFF
func (s *Scanner) Init(src []byte) {
	s.src = src
	s.ch = ' '
	s.offset = 0
	s.rdOffset = 0

	s.next()
	if s.ch == bom {
		s.next()
	}
}

func (s *Scanner) next() {
	if s.rdOffset < len(s.src) {
		s.offset = s.rdOffset
		s.ch = rune(s.src[s.rdOffset])
		s.rdOffset += 1
	} else {
		s.offset = len(s.src)
		s.ch = -1 // eof
	}
}
```
The scanners job is to read one `rune` at a time and return a `Token` and the `string` literal of what it scanned.

For the Hack Assembly Language whitespace means nothing, so we can safely skip any found (the indentation in the example is only for readability):
```go
func (s *Scanner) skipWhitespace() {
	for s.ch == ' ' || s.ch == '\t' || s.ch == '\n' || s.ch == '\r' {
		s.next()
	}
}
```
The output of an assembler is `1`s and `0`s so we don't really need to scan for comments, but I thought that handling comments would be a good starting point to building the scanner:
```go
func (s *Scanner) scanComment() string {
	s.next()
	offs := s.offset
	for s.ch != '\n' && s.ch >= 0 {
		s.next()
	}
	return string(s.src[offs:s.offset])
}
```
Our `scanComment()` function keeps progressing the scanner until it finds a newline or reaches the end of file (`EOF`), and returns all the characters as a `string`. Our `Scan()` function can now fully scan for comments:
```go
func (s *Scanner) Scan() (tok Token, lit string) {
	s.skipWhitespace()
	ch := s.ch
	s.next() // always make progress
	
	switch ch {	
	case -1:
		tok = EOF
	case '/':
		if s.ch == '/' { // the second '/' means we have a comment
			tok = COMMENT
			lit = s.scanComment()
        } 
    default:
        tok = ILLEGAL
	}
	return
}               
```
Great, we now have a working Scanner that will tokenize Comments; lets add some more tokens.

The "A" instruction is the easiest to scan; the instruction begins with `@`, and all we need to do is scan the whole line:
```go
func (s *Scanner) scanLine() string {
	offs := s.offset
	for s.ch != '\n' && s.ch != '\r' && s.ch >= 0 && s.ch != ' '  {
		s.next()
	}
	return string(s.src[offs:s.offset])
}
```
A "Label" is also is easy as it begins with a bracket `(`, but instead of reading to the end of the line, we make sure end when we see the closing bracket `)`:
```go
func (s *Scanner) scanLabel() string {
	offs := s.offset
	for {
		ch := s.ch
		if ch == '\n' || ch == '\r' || ch < 0 {
			break
		}
		s.next()
		if ch == ')' {
			break
		}
	}
	return string(s.src[offs:s.offset-1])
}
```
The "C" instruction is the most complex but a simple helper function can help us to determine if it's a C-Instruction (as described by the HACK Assembly Language spec):
```go
func isCInstruction(ch rune) bool {
	return ch == '0' || ch == '1' || ch == '-' || ch == '!' || ch == 'A' || ch == 'D' || ch == 'M'
}
```
We can use the same `scanLine()` function for the C-Instruction, making sure we don't throw away the first character; Our final `Scan()` function looks like this:
```go
func (s *Scanner) Scan() (tok Token, lit string) {
	s.skipWhitespace()

	switch ch := s.ch; {
	case isCInstruction(ch):
		tok = C_INSTRUCTION
		lit = s.scanLine()
	default:
		s.next() // always make progress
		switch ch {	
		case -1:
			tok = EOF
		case '/':
			if s.ch == '/' {
				tok = COMMENT
				lit = s.scanComment()
			}
		case '(':
			tok = LABEL
			lit = s.scanLabel()
		case '@':
			tok = A_INSTRUCTION
			lit = s.scanLine()
		default:
			tok = ILLEGAL
		}
	}
	return
}
```
## Syntax Tree
Before we start parsing the HACK Assembly file we want to define our abstract syntax tree (AST). All Labels get converted to Symbols (more on this later) so we're left with a simple list of either "A", or "C" instructions:
```go
type Instruction interface {
	BinaryString() string
}

type HackFile struct {
	Instructions []Instruction
}

type AInstruction struct {
	lit string // the raw assembly instruction pre-parsing
	addr int
}

func (a *AInstruction) BinaryString() string {
	return fmt.Sprintf("0%015b\n", a.addr)
}

type CInstruction struct {
	lit string
	dest int // C instructions look like: `dest=comp;jump`; dest and jump are optional
	comp int
	jump int
}

func (c *CInstruction) BinaryString() string {
	return fmt.Sprintf("111%07b%03b%03b\n", c.comp, c.dest, c.jump)
}
```
Each `Instruction` interface has a single method `BinaryString()` which will make it really easy for us to output the machine code later.

With out AST defined and our complete Scanner, we are ready to start parsing the data.

## Parsing
The HACK Assembly Language has a number of pre-defined memory allocations defined as Symbols, so we'll initiate our parser with this in mind. Later, Labels we parse will be added to these Symbols and any variables found should also be added to these Symbols for later lookup.
```go
type Parser struct {
	scanner Scanner
	symbols map[string]int
	instructions []Instruction
	nAddr int // next available address
}

func (p *Parser) Init(src []byte) {
	p.scanner.Init(src)	
	p.nAddr = 16 // address [0:15] are reserved
	p.symbols = map[string]int{
		"R0": 0, "R1": 1, "R2": 2, "R3": 3, "R4": 4, "R5": 5, "R6": 6, "R7": 7, "R8": 8,
		"R9": 9, "R10": 10, "R11": 11, "R12": 12, "R13": 13, "R14": 14, "R15": 15,
		"SCREEN": 16384, "KBD": 24576,
		"SP": 0, "LCL": 1, "ARG": 2, "THIS": 3, "THAT": 4,
	}
}
```
Because Labels could appear in an "A" instruction before they are defined, we will need to parse the file in two passes; but instead of re-setting the scanner, we will parse the instructions by storing the raw string literal and parse the instructions in a second pass:
```go
func (p *Parser) Parse() HackFile {
loop:
	for {
		tok, lit := p.scanner.Scan()
		switch tok {
		case EOF:
			break loop // break out of the loop not just the switch
		case LABEL:
			p.symbols[lit] = len(p.instructions)
		case A_INSTRUCTION:
			p.instructions = append(p.instructions, &AInstruction{lit: lit})
		case C_INSTRUCTION:
			p.instructions = append(p.instructions, &CInstruction{lit: lit})
		}
	}

	for _, instr := range p.instructions {
		switch i := instr.(type) {
		case *AInstruction:
			p.parseAInstruction(i)
		case *CInstruction:
			p.parseCInstruction(i)
		}
	} 
	return HackFile{ Instructions: p.instructions }
}
```
I'm intentionally not giving you the `parseAInstruction()` and `parseCInstruction()` methods, just so you can do some of the work yourself :smile:
## Tying it all together
Our CLI tool will read in the `*.asm` file and output the machine code as a `*.hack` file:
```go
func main() {
	asmFilePath := os.Args[1]
	asmData, _ := ioutil.ReadFile(asmFilePath) // ignoring errors for brevity
	
	var p Parser
	p.Init(asmData)
	hackFile := p.Parse()

	var b bytes.Buffer
	for _, i := range hackFile.Instructions {
		b.WriteString(i.BinaryString())
	}

	hackFilePath := strings.Replace(asmFilePath, ".asm", ".hack", 1)
	ioutil.WriteFile(hackFilePath, b.Bytes(), 0644)
}
```
This project was the pre-cursor to writing a lexer/parser for the [Djinni IDL in Go](https://github.com/SafetyCulture/djinni-parser), which builds on top of these concepts; Check it out of you want more detail on building a lexer/parser in Go.
