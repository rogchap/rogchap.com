---
title: "Building an Assembler"
date: 2019-07-27T15:04:23+10:00
type: post
tags:
- Go
draft: true
---

I recently completed the first part of the awesome "[From Nand to Tetris](https://www.nand2tetris.org)" course. For project 6 you have to build an Assembler for the HACK Computer using a high level language of your choice; naturally I did my project using Go. 

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
The scanners job is to read one `rune` at a time and return a `Token` and the `string` literal of what it "scanned".

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
## Parsing what we know
