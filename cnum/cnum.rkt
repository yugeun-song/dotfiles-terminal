#!/usr/bin/env racket
#lang racket/base

;; cnum: a calculator whose surface is C's expression syntax and whose numbers are C's on x86-64 Linux
;; (GCC, LP64). The reader turns a line into an s-expression, and the rules below evaluate it; every rule
;; (literal typing, promotion, the operators, the helpers) is a definition in this file.

(require racket/list racket/string racket/math)

;; ---------------------------------------------------------------------------------------------------------
;; Values
;;
;; An exact integer is a constant with no type yet, a flonum is a double, and the two structs below carry a
;; C type.

;; A fixed-width integer: `type` is one of u8 .. s64 and `value` is already cut to it.
(struct int (type value))
;; A single-precision number: `value` is a flonum already rounded to 24 bits.
(struct f32 (value))
;; A function defined at the prompt: `f(a, b) = a * b`.
(struct fn (name params body))

;; Raises an error that the prompt reports without a stack trace.
(define (fail message . arguments)
  (raise (exn:fail:user (apply format message arguments) (current-continuation-marks))))

;; Writes one line to standard error.
(define (note message . arguments)
  (eprintf "~a\n" (apply format message arguments)))

;; Each integer type's width in bits and whether it is signed.
(define INTS
  (hasheq 'u8 '(8 . #f) 's8 '(8 . #t) 'u16 '(16 . #f) 's16 '(16 . #t)
          'u32 '(32 . #f) 's32 '(32 . #t) 'u64 '(64 . #f) 's64 '(64 . #t)))
(define TYPES '(u8 s8 u16 s16 u32 s32 u64 s64 f32 f64 big))
(define BASES (hasheq 'bin '(2 . "0b") 'oct '(8 . "0o") 'dec '(10 . "") 'hex '(16 . "0x")))
(define UNITS '(byte kb mb gb tb))

(define (bits type) (car (hash-ref INTS type)))
(define (signed? type) (cdr (hash-ref INTS type)))
(define (int-type? type) (hash-has-key? INTS type))

;; Cuts an integer to a type's width, as a C conversion does.
(define (wrap type number)
  (define width (bits type))
  (define low (bitwise-and number (sub1 (arithmetic-shift 1 width))))
  (if (and (signed? type) (bitwise-bit-set? low (sub1 width))) (- low (arithmetic-shift 1 width)) low))

(define (make type number) (int type (wrap type number)))

;; C's integer promotion: a type narrower than int becomes s32.
(define (promote type) (if (< (bits type) 32) 's32 type))

;; C's usual arithmetic conversion: the wider type, and of two equally wide ones the unsigned.
(define (common left right)
  (define a (promote left))
  (define b (promote right))
  (cond [(> (bits a) (bits b)) a]
        [(< (bits a) (bits b)) b]
        [(signed? a) b]
        [else a]))

;; Types a constant as C types a decimal one: s32 when it fits, else s64, else u64.
(define (literal number)
  (define size (abs number))
  (define type (for/first ([name '(s32 s64 u64)] #:when (= (wrap name size) size)) name))
  (unless type
    (fail "~a is wider than 64 bits, so it has no C type; convert it with u64 or another type" number))
  (make type number))

(define (typed value) (if (exact-integer? value) (literal value) value))
(define (real? value) (or (flonum? value) (f32? value)))
(define (number? value) (or (exact-integer? value) (flonum? value) (int? value) (f32? value)))

;; A value as the plain Racket number it holds.
(define (plain value)
  (cond [(int? value) (int-value value)]
        [(f32? value) (f32-value value)]
        [else value]))

;; Rounds a flonum to single precision.
(define (single number)
  (floating-point-bytes->real (real->floating-point-bytes number 4)))

;; Rounds an exact integer to `width` significant bits in one step, ties to even.
(define (nearest number width)
  (define size (abs number))
  (define shift (max (- (integer-length size) width) 0))
  (define quotient (arithmetic-shift size (- shift)))
  (define rest (+ (* 2 (- size (arithmetic-shift quotient shift))) (bitwise-and quotient 1)))
  (define rounded (if (> rest (arithmetic-shift 1 shift)) (add1 quotient) quotient))
  (* (if (negative? number) -1 1) (arithmetic-shift rounded shift)))

;; What the cvttsd2si instruction leaves in a register of `width` bits: the truncated value, or the lowest
;; value when it does not fit or is not a number.
(define (register number width)
  (define lowest (- (arithmetic-shift 1 (sub1 width))))
  (cond [(or (nan? number) (infinite? number)) lowest]
        [else (define whole (exact-truncate number))
              (if (and (>= whole lowest) (< whole (- lowest))) whole lowest)]))

;; A float as the integer GCC's code converts it to, before the cut to `type`.
(define (whole type number)
  (cond [(exact-integer? number) number]
        [(and (eq? type 'u64) (>= number 9223372036854775808.0))
         (bitwise-xor (register (- number 9223372036854775808.0) 64) (arithmetic-shift 1 63))]
        [else (register number (if (memq type '(u32 s64 u64)) 64 32))]))

;; Converts as the C cast `(type)value` does.
(define (cast type value)
  (define number (plain value))
  (cond [(int-type? type) (make type (whole type number))]
        [(eq? type 'f64) (if (exact-integer? number) (exact->inexact number) number)]
        [(eq? type 'f32)
         (f32 (if (exact-integer? number) (single (exact->inexact (nearest number 24))) (single number)))]
        [(flonum? number)
         (when (or (nan? number) (infinite? number)) (fail "big cannot hold ~a" (float-text number)))
         (exact-truncate number)]
        [else number]))

;; ---------------------------------------------------------------------------------------------------------
;; Operators

(define (double value)
  (define number (plain value))
  (if (exact-integer? number) (exact->inexact number) number))

;; Both operands of a float operation as flonums, and whether the operation is in single precision: it is
;; unless a double takes part, as in C, and an integer beside a float is converted to a float first.
(define (float-operands left right)
  (define narrow? (not (or (flonum? left) (flonum? right))))
  (define (operand value) (if (and narrow? (not (f32? value))) (f32-value (cast 'f32 value)) (double value)))
  (values (operand left) (operand right) narrow?))

(define (float-binary operator left right)
  (define-values (x y narrow?) (float-operands left right))
  (define result
    (case operator
      [(+) (+ x y)]
      [(-) (- x y)]
      [(*) (* x y)]
      [(/) (cond [(not (zero? y)) (/ x y)]
                 [(or (zero? x) (nan? x)) +nan.0]
                 [(eq? (negative? x) (eqv? y -0.0)) +inf.0]
                 [else -inf.0])]
      [else (fail "~a takes integers, got a ~a" operator (if narrow? "float" "double"))]))
  (if narrow? (f32 (single result)) result))

(define (divide operator x y)
  (when (zero? y) (fail "division by zero"))
  (if (eq? operator '/) (quotient x y) (remainder x y)))

;; The shift count the x86-64 instruction uses, with a note when C leaves the shift undefined.
(define (count type places)
  (define width (bits type))
  (unless (<= 0 places (sub1 width))
    (note "~a: a shift by ~a is undefined in C; x86-64 uses the low ~a bits of the count"
          type places (if (= width 64) 6 5)))
  (bitwise-and places (sub1 width)))

(define (shift operator left right)
  (define places (plain right))
  (cond [(exact-integer? left)
         (unless (<= 0 places 65536) (fail "a constant shifts by 0 to 65536 places, got ~a" places))
         (arithmetic-shift left (if (eq? operator '<<) places (- places)))]
        [else
         (define type (promote (int-type left)))
         (define amount (count type places))
         (make type (arithmetic-shift (wrap type (int-value left)) (if (eq? operator '<<) amount (- amount))))]))

(define (exact-binary operator x y)
  (case operator
    [(+) (+ x y)]
    [(-) (- x y)]
    [(*) (* x y)]
    [(/ %) (divide operator x y)]
    [(&) (bitwise-and x y)]
    [(\|) (bitwise-ior x y)]
    [(^) (bitwise-xor x y)]))

;; A binary operator by C's rules: floats first, then constants exactly, then the common type.
(define (binary operator left right)
  (cond [(or (real? left) (real? right))
         (float-binary operator left right)]
        [(memq operator '(<< >>))
         (shift operator (if (int? right) (typed left) left) right)]
        [(and (exact-integer? left) (exact-integer? right))
         (exact-binary operator left right)]
        [else
         (define a (typed left))
         (define b (typed right))
         (define type (common (int-type a) (int-type b)))
         (make type (exact-binary operator (wrap type (int-value a)) (wrap type (int-value b))))]))

;; C's answer to a test: the int 1 or 0.
(define (truth yes?) (make 's32 (if yes? 1 0)))

;; A comparison in the common type.
(define (compare operator left right)
  (define-values (x y)
    (cond [(or (real? left) (real? right))
           (let-values ([(x y narrow?) (float-operands left right)]) (values x y))]
          [(and (exact-integer? left) (exact-integer? right)) (values left right)]
          [else (define a (typed left))
                (define b (typed right))
                (define type (common (int-type a) (int-type b)))
                (values (wrap type (int-value a)) (wrap type (int-value b)))]))
  (truth (case operator
           [(<) (< x y)]
           [(>) (> x y)]
           [(<=) (<= x y)]
           [(>=) (>= x y)]
           [(==) (= x y)]
           [(!=) (not (= x y))])))

(define (truthy? value) (not (zero? (plain value))))

(define (unary operator value)
  (case operator
    [(!) (truth (not (truthy? value)))]
    [(+) (if (int? value) (make (promote (int-type value)) (int-value value)) value)]
    [(-) (cond [(f32? value) (f32 (- (f32-value value)))]
               [(int? value) (make (promote (int-type value)) (- (int-value value)))]
               [(flonum? value) (- value)]
               [else (- value)])]
    [(~) (cond [(real? value) (fail "~~ takes an integer, got a float")]
               [(int? value) (make (promote (int-type value)) (bitwise-not (int-value value)))]
               [else (bitwise-not value)])]))

;; ---------------------------------------------------------------------------------------------------------
;; Types and units by name

(define KNOWN
  (let ([table (make-hash)])
    (for ([name TYPES]) (hash-set! table (symbol->string name) name))
    (for ([(name shape) INTS])
      (hash-set! table (format "~aint~a_t" (if (cdr shape) "" "u") (car shape)) name))
    (for ([pair '(("size_t" . u64) ("ssize_t" . s64) ("intptr_t" . s64) ("uintptr_t" . u64)
                  ("ptrdiff_t" . s64) ("intmax_t" . s64) ("uintmax_t" . u64) ("uint" . u32)
                  ("ulong" . u64) ("ushort" . u16) ("float" . f32) ("double" . f64))])
      (hash-set! table (car pair) (cdr pair)))
    table))
(define WORDS (hash "signed" 1 "unsigned" 1 "char" 1 "short" 1 "int" 1 "long" 2))
(define APART '(("signed" "unsigned") ("char" "short" "long") ("char" "int")))
(define SIZES '(("char" . 8) ("short" . 16) ("long" . 64)))

(define (type-word? text) (or (hash-has-key? KNOWN text) (hash-has-key? WORDS text)))

;; Reads C type specifiers in any order (`unsigned long int`) as GCC does on x86-64.
(define (specifiers words)
  (define counts (for/fold ([counts (hash)]) ([word words]) (hash-update counts word add1 0)))
  (define declared?
    (and (pair? words)
         (for/and ([(word total) counts]) (<= total (hash-ref WORDS word 0)))
         (for/and ([group APART]) (<= (count-of group counts) 1))))
  (unless declared? (fail "~a is not a type" (string-join words " ")))
  (define width (or (for/first ([size SIZES] #:when (hash-has-key? counts (car size))) (cdr size)) 32))
  (string->symbol (format "~a~a" (if (hash-has-key? counts "unsigned") "u" "s") width)))

(define (count-of group counts) (for/sum ([word group]) (if (hash-has-key? counts word) 1 0)))

(define SPELLED
  (let ([table (make-hash '(("b" . byte) ("byte" . byte) ("bytes" . byte)))])
    (for ([entry '((kb "kilo" "kibi") (mb "mega" "mebi") (gb "giga" "gibi") (tb "tera" "tebi"))])
      (define unit (car entry))
      (define name (symbol->string unit))
      (hash-set! table name unit)
      (hash-set! table (string-append (substring name 0 1) "ib") unit)
      (for ([word (cdr entry)])
        (hash-set! table (string-append word "byte") unit)
        (hash-set! table (string-append word "bytes") unit)))
    table))

;; ---------------------------------------------------------------------------------------------------------
;; Text

(define (digits number radix) (string-upcase (number->string number radix)))

(define (whole-text number radix prefix)
  (string-append (if (negative? number) "-" "") prefix (digits (abs number) radix)))

(define (float-text number)
  (cond [(nan? number) "nan"]
        [(infinite? number) (if (positive? number) "inf" "-inf")]
        [else (number->string number)]))

;; A float in a radix, with its exact fraction digits (`0x1.8`).
(define (real-text number radix prefix)
  (cond [(or (= radix 10) (nan? number) (infinite? number)) (float-text number)]
        [else
         (define exact (abs (inexact->exact number)))
         (define fraction
           (let loop ([rest (- exact (floor exact))] [text ""])
             (if (zero? rest)
                 text
                 (let ([scaled (* rest radix)])
                   (loop (- scaled (floor scaled)) (string-append text (digits (floor scaled) radix)))))))
         (string-append (if (or (negative? number) (eqv? number -0.0)) "-" "")
                        (whole-text (floor exact) radix prefix)
                        (if (string=? fraction "") "" (string-append "." fraction)))]))

;; A size: whole numbers with no fraction; others cut to 5 places, or to 20 when the first 5 are zeros.
(define (size-text value)
  (define number (plain value))
  (cond [(exact-integer? number) (number->string number)]
        [(or (nan? number) (infinite? number) (>= (abs number) 1e21)) (float-text number)]
        [else
         (define scaled (floor (* (abs (inexact->exact number)) (expt 10 20))))
         (define text (number->string scaled))
         (define padded (string-append (make-string (max 0 (- 21 (string-length text))) #\0) text))
         (define split (- (string-length padded) 20))
         (define rest (substring padded split))
         (define places (if (string-prefix? rest "00000") rest (substring rest 0 5)))
         (define kept (string-trim places "0" #:left? #f #:repeat? #t))
         (cond [(and (zero? scaled) (not (zero? number))) (float-text number)]
               [else (string-append (if (negative? number) "-" "")
                                    (substring padded 0 split)
                                    (if (string=? kept "") "" (string-append "." kept)))])]))

;; The text of a value in a base. A typed integer shows the two's complement pattern of its type.
(define (render value base)
  (cond [(eq? base 'size) (size-text value)]
        [else
         (define radix (car (hash-ref BASES base)))
         (define prefix (cdr (hash-ref BASES base)))
         (cond [(real? value) (real-text (plain value) radix prefix)]
               [(exact-integer? value) (whole-text value radix prefix)]
               [(= radix 10) (number->string (int-value value))]
               [else
                (define mask (sub1 (arithmetic-shift 1 (bits (int-type value)))))
                (whole-text (bitwise-and (int-value value) mask) radix prefix)])]))

;; ---------------------------------------------------------------------------------------------------------
;; Reader: C's expression syntax to an s-expression

(struct token (kind text value start end))

(define OPERATORS
  '("<<=" ">>=" "++" "--" "<<" ">>" "<=" ">=" "==" "!=" "&&" "||" "+=" "-=" "*=" "/=" "%=" "&=" "|=" "^="
    "+" "-" "*" "/" "%" "&" "|" "^" "~" "!" "<" ">" "=" "?" ":" "(" ")" "," ";"))
(define ESCAPES (hash #\n 10 #\t 9 #\r 13 #\0 0 #\a 7 #\b 8 #\f 12 #\v 11 #\e 27 #\\ 92 #\' 39 #\" 34 #\? 63))

;; Types an integer constant with a suffix as C does: the first type of the suffix's list that holds it.
(define (suffixed number suffix decimal?)
  (define unsigned? (regexp-match? #rx"[uU]" suffix))
  (define long? (regexp-match? #rx"[lL]" suffix))
  (define candidates
    (cond [(and unsigned? long?) '(u64)]
          [unsigned? '(u32 u64)]
          [decimal? '(s64 u64)]
          [else '(s64 u64)]))
  (define type (for/first ([name candidates] #:when (= (wrap name number) number)) name))
  (unless type (fail "the constant ~a is too large for its type" number))
  (make type number))

(define (character text)
  (define body (substring text 1 (sub1 (string-length text))))
  (cond [(not (char=? (string-ref body 0) #\\))
         (unless (= (string-length body) 1) (fail "a character constant holds one character, got ~a" text))
         (char->integer (string-ref body 0))]
        [(regexp-match #rx"^\\\\x([0-9a-fA-F]+)$" body) => (lambda (found) (string->number (cadr found) 16))]
        [(regexp-match #rx"^\\\\([0-7][0-7]?[0-7]?)$" body) => (lambda (found) (string->number (cadr found) 8))]
        [(and (= (string-length body) 2) (hash-ref ESCAPES (string-ref body 1) #f))]
        [else (fail "unknown escape in ~a" text)]))

(define (constant text)
  (define (parts pattern) (regexp-match pattern text))
  (cond [(parts #rx"^0[xX]([0-9a-fA-F]+)([uUlL]*)$")
         => (lambda (found) (integer (string->number (cadr found) 16) (caddr found) #f))]
        [(parts #rx"^0[bB]([01]+)([uUlL]*)$")
         => (lambda (found) (integer (string->number (cadr found) 2) (caddr found) #f))]
        [(parts #rx"^0[oO]?([0-9]+)([uUlL]*)$")
         => (lambda (found)
              (unless (regexp-match? #rx"^[0-7]+$" (cadr found)) (fail "invalid digit in the octal constant ~a" text))
              (integer (string->number (cadr found) 8) (caddr found) #f))]
        [(parts #rx"^([0-9]+)([uUlL]*)$")
         => (lambda (found) (integer (string->number (cadr found) 10) (caddr found) #t))]
        [(parts #rx"^([0-9]*[.]?[0-9]*([eE][+-]?[0-9]+)?)([fF]?)$")
         => (lambda (found)
              (define number (string->number (string-append "0" (regexp-replace #rx"[.]($|[eE])" (cadr found) ".0\\1")) 10))
              (unless number (fail "~a is not a number" text))
              (if (string=? (cadddr found) "") (exact->inexact number) (cast 'f32 (exact->inexact number))))]
        [else (fail "~a is not a number" text)]))

(define (integer number suffix decimal?)
  (cond [(string=? suffix "") number]
        [(regexp-match? #rx"^([uU](l|L|ll|LL)?|(l|L|ll|LL)[uU]?)$" suffix) (suffixed number suffix decimal?)]
        [else (fail "~a is not an integer suffix" suffix)]))

(define (tokenize source)
  (define end (string-length source))
  (let loop ([at 0] [tokens '()])
    (define (match pattern) (regexp-match pattern source at))
    (define (push kind text value)
      (loop (+ at (string-length text)) (cons (token kind text value at (+ at (string-length text))) tokens)))
    (cond [(>= at end) (reverse (cons (token 'end "" #f end end) tokens))]
          [(match #px"^(\\s+|//[^\n]*|/\\*.*?\\*/)") => (lambda (found) (loop (+ at (string-length (car found))) tokens))]
          [(match #px"^'(\\\\[^']*|[^'\\\\]+)'") => (lambda (found) (push 'number (car found) (character (car found))))]
          [(match #px"^(0[xXbBoO][0-9a-zA-Z_]*|([0-9]+[.]?[0-9]*|[.][0-9]+)([eE][+-]?[0-9]+)?[0-9a-zA-Z_]*)")
           => (lambda (found) (push 'number (car found) (constant (car found))))]
          [(match #px"^[A-Za-z_][A-Za-z0-9_]*") => (lambda (found) (push 'name (car found) #f))]
          [(for/first ([operator OPERATORS]
                       #:when (and (<= (+ at (string-length operator)) end)
                                   (string=? operator (substring source at (+ at (string-length operator))))))
             operator)
           => (lambda (operator) (push 'operator operator (string->symbol operator)))]
          [else (fail "unexpected ~a" (substring source at (add1 at)))])))

(define PRECEDENCE
  (hasheq '\|\| 1 '&& 2 '\| 3 '^ 4 '& 5 '== 6 '!= 6 '< 7 '> 7 '<= 7 '>= 7 '<< 8 '>> 8 '+ 9 '- 9 '* 10 '/ 10 '% 10))
(define ASSIGNMENTS '(= += -= *= /= %= &= \|= ^= <<= >>=))

;; Parses one line into a list of statements, each an s-expression:
;;   (const v) (var "x") (unary op e) (binary op a b) (logic op a b) (if c a b) (assign op "x" e)
;;   (step op "x" before?) (cast type e) (sizeof e) (sizeof-type type) (call "f" (arg ...))
;;   (define "f" ("a" ...) e)
;; An argument is (cons expression source-text), where the expression may be (type T).
(define (parse source)
  (define tokens (list->vector (tokenize source)))
  (define at 0)
  (define (peek [ahead 0]) (vector-ref tokens (min (+ at ahead) (sub1 (vector-length tokens)))))
  (define (next!) (begin0 (peek) (set! at (add1 at))))
  (define (operator? symbol [ahead 0])
    (and (eq? (token-kind (peek ahead)) 'operator) (eq? (token-value (peek ahead)) symbol)))
  (define (name? [ahead 0]) (eq? (token-kind (peek ahead)) 'name))
  (define (type-ahead? [ahead 0]) (and (name? ahead) (type-word? (token-text (peek ahead)))))
  (define (expect symbol)
    (unless (operator? symbol)
      (fail "expected ~a, got ~a" symbol (if (eq? (token-kind (peek)) 'end) "the end of the line" (token-text (peek)))))
    (next!))

  (define (type)
    (define first (token-text (next!)))
    (cond [(hash-ref KNOWN first #f)
           => (lambda (name)
                (when (and (memq name '(f32 f64)) (type-ahead?)) (fail "~a ~a is not a type" first (token-text (peek))))
                name)]
          [else
           (let loop ([words (list first)])
             (cond [(and (name? 0) (hash-has-key? WORDS (token-text (peek)))) (loop (cons (token-text (next!)) words))]
                   [(type-ahead?) (fail "~a ~a is not a type" (string-join (reverse words) " ") (token-text (peek)))]
                   [else (specifiers (reverse words))]))]))

  (define (type-only? [start 0])
    (let loop ([ahead start])
      (cond [(type-ahead? ahead) (loop (add1 ahead))]
            [else (or (operator? '\, ahead) (operator? '\) ahead))])))

  (define (variable)
    (unless (and (name? 0) (not (type-ahead?))) (fail "expected a variable, got ~a" (token-text (peek))))
    (token-text (next!)))

  (define (argument)
    (define start (token-start (peek)))
    (define expression
      (cond [(and (type-ahead?) (type-only?)) (list 'type (type))]
            [else (assignment)]))
    (cons expression (string-trim (substring source start (token-start (peek))))))

  (define (arguments)
    (expect '\()
    (cond [(operator? '\)) (next!) '()]
          [else
           (let loop ([found (list (argument))])
             (cond [(operator? '\,) (next!) (loop (cons (argument) found))]
                   [else (expect '\)) (reverse found)]))]))

  (define (primary)
    (define current (peek))
    (cond [(eq? (token-kind current) 'number) (next!) (list 'const (token-value current))]
          [(type-ahead?)
           (define name (type))
           (expect '\()
           (begin0 (list 'cast name (expression)) (expect '\)))]
          [(name? 0)
           (next!)
           (if (operator? '\() (list 'call (token-text current) (arguments)) (list 'var (token-text current)))]
          [(operator? '\()
           (next!)
           (cond [(and (type-ahead?) (type-only?))
                  (define name (type))
                  (expect '\))
                  (list 'cast name (prefix))]
                 [else (begin0 (expression) (expect '\)))])]
          [(eq? (token-kind current) 'end) (fail "the line ends where a value is expected")]
          [else (fail "unexpected ~a" (token-text current))]))

  (define (postfix)
    (define operand (primary))
    (cond [(and (or (operator? '++) (operator? '--)) (eq? (car operand) 'var))
           (list 'step (token-value (next!)) (cadr operand) #f)]
          [else operand]))

  (define (prefix)
    (cond [(or (operator? '+) (operator? '-) (operator? '!) (operator? '~))
           (define operator (token-value (next!)))
           (list 'unary operator (prefix))]
          [(or (operator? '++) (operator? '--))
           (define operator (token-value (next!)))
           (list 'step operator (variable) #t)]
          [(and (name? 0) (string=? (token-text (peek)) "sizeof"))
           (next!)
           (cond [(and (operator? '\() (type-ahead? 1) (type-only? 1))
                  (next!)
                  (begin0 (list 'sizeof-type (type)) (expect '\)))]
                 [else (list 'sizeof (prefix))])]
          [else (postfix)]))

  (define (binary-level lowest)
    (let loop ([left (prefix)])
      (define operator (and (eq? (token-kind (peek)) 'operator) (token-value (peek))))
      (define level (and operator (hash-ref PRECEDENCE operator #f)))
      (cond [(and level (>= level lowest))
             (next!)
             (define right (binary-level (add1 level)))
             (loop (list (if (memq operator '(&& \|\|)) 'logic 'binary) operator left right))]
            [else left])))

  (define (conditional)
    (define test (binary-level 1))
    (cond [(operator? '?)
           (next!)
           (define then (expression))
           (expect ':)
           (list 'if test then (conditional))]
          [else test]))

  (define (assignment)
    (define left (conditional))
    (cond [(and (eq? (token-kind (peek)) 'operator) (memq (token-value (peek)) ASSIGNMENTS))
           (unless (eq? (car left) 'var) (fail "only a variable can be assigned to"))
           (define operator (token-value (next!)))
           (list 'assign operator (cadr left) (assignment))]
          [else left]))

  (define (expression) (assignment))

  (define (definition?)
    (and (name? 0) (not (type-ahead?)) (operator? '\( 1)
         (let loop ([ahead 2] [want-name? #t])
           (cond [(and (= ahead 2) (operator? '\) ahead)) (operator? '= (add1 ahead))]
                 [(and want-name? (name? ahead)) (loop (add1 ahead) #f)]
                 [(and (not want-name?) (operator? '\, ahead)) (loop (add1 ahead) #t)]
                 [(and (not want-name?) (operator? '\) ahead)) (operator? '= (add1 ahead))]
                 [else #f]))))

  (define (statement)
    (cond [(definition?)
           (define name (token-text (next!)))
           (define params (map (lambda (pair)
                                 (unless (eq? (car (car pair)) 'var) (fail "a parameter is a name, got ~a" (cdr pair)))
                                 (cadr (car pair)))
                               (arguments)))
           (expect '=)
           (list 'define name params (expression))]
          [else (expression)]))

  (let loop ([found '()])
    (cond [(operator? '\;) (next!) (loop found)]
          [(eq? (token-kind (peek)) 'end) (reverse found)]
          [else
           (define parsed (statement))
           (unless (or (operator? '\;) (eq? (token-kind (peek)) 'end)) (fail "unexpected ~a" (token-text (peek))))
           (loop (cons parsed found))])))

;; ---------------------------------------------------------------------------------------------------------
;; Evaluator

;; The helper called last in this statement: (list name base type), or #f.
(define shown #f)
(define globals (make-hash (list (cons "true" 1) (cons "false" 0))))
(define depth 0)

(define RESERVED
  (append (map symbol->string (append TYPES UNITS (hash-keys BASES)))
          (hash-keys WORDS)
          (for*/list ([from UNITS] [to UNITS] #:unless (eq? from to)) (format "~a_to_~a" from to))
          '("cast" "sizeof" "true" "false" "help" "quit" "exit")))

(define (lookup name scope)
  (cond [(hash-ref scope name #f)]
        [(hash-ref globals name #f)]
        [(member name RESERVED) (fail "~a is not a value here; call it or pass it as an option" name)]
        [else (fail "~a is not defined" name)]))

(define (store! name value scope)
  (when (member name RESERVED) (fail "~a is part of the language; choose another name" name))
  (hash-set! (if (hash-has-key? scope name) scope globals) name value)
  value)

(define (variable-value name scope)
  (define value (lookup name scope))
  (when (fn? value) (fail "~a is a function; call it" name))
  value)

(define (evaluate tree scope)
  (case (car tree)
    [(const) (cadr tree)]
    [(var) (variable-value (cadr tree) scope)]
    [(unary) (unary (cadr tree) (evaluate (caddr tree) scope))]
    [(binary)
     (define operator (cadr tree))
     (define left (evaluate (caddr tree) scope))
     (define right (evaluate (cadddr tree) scope))
     (if (memq operator '(< > <= >= == !=)) (compare operator left right) (binary operator left right))]
    [(logic)
     (define left? (truthy? (evaluate (caddr tree) scope)))
     (truth (if (eq? (cadr tree) '&&)
                (and left? (truthy? (evaluate (cadddr tree) scope)))
                (or left? (truthy? (evaluate (cadddr tree) scope)))))]
    [(if) (evaluate (if (truthy? (evaluate (cadr tree) scope)) (caddr tree) (cadddr tree)) scope)]
    [(assign)
     (define operator (cadr tree))
     (define name (caddr tree))
     (define value (evaluate (cadddr tree) scope))
     (cond [(eq? operator '=) (store! name value scope)]
           [else
            (define inner (string->symbol (regexp-replace #rx"=$" (symbol->string operator) "")))
            (store! name (binary inner (variable-value name scope) value) scope)])]
    [(step)
     (define name (caddr tree))
     (define old (variable-value name scope))
     (define new (binary (if (eq? (cadr tree) '++) '+ '-) old 1))
     (store! name new scope)
     (if (cadddr tree) new old)]
    [(cast) (cast (cadr tree) (evaluate (caddr tree) scope))]
    [(sizeof) (make 'u64 (size-of (evaluate (cadr tree) scope)))]
    [(sizeof-type) (make 'u64 (width-of (cadr tree)))]
    [(call) (call (cadr tree) (caddr tree) scope)]
    [(define)
     (when (member (cadr tree) RESERVED) (fail "~a is part of the language; choose another name" (cadr tree)))
     (hash-set! globals (cadr tree) (fn (cadr tree) (caddr tree) (cadddr tree)))
     (void)]))

(define (width-of type)
  (cond [(int-type? type) (quotient (bits type) 8)]
        [(eq? type 'f32) 4]
        [(eq? type 'f64) 8]
        [else (fail "sizeof expects a type with a size, got big")]))

(define (size-of value)
  (cond [(int? value) (quotient (bits (int-type value)) 8)]
        [(f32? value) 4]
        [(flonum? value) 8]
        [else (quotient (bits (int-type (literal value))) 8)]))

;; The value of an argument that must be a number.
(define (value-of who argument scope)
  (when (eq? (car (car argument)) 'type) (fail "~a expects a number, got the type ~a" who (cdr argument)))
  (evaluate (car argument) scope))

;; What an option names: (cons 'type T), (cons 'base B), (cons 'unit U), or #f.
(define (option argument)
  (define tree (car argument))
  (cond [(eq? (car tree) 'type) (cons 'type (cadr tree))]
        [(eq? (car tree) 'var)
         (define text (string-downcase (cadr tree)))
         (cond [(hash-has-key? BASES (string->symbol text)) (cons 'base (string->symbol text))]
               [(hash-ref KNOWN text #f) => (lambda (type) (cons 'type type))]
               [(hash-ref SPELLED text #f) => (lambda (unit) (cons 'unit unit))]
               [else #f])]
        [else #f]))

;; Sorts a helper's options by kind, allowing the kinds in `allowed` and one of each.
(define (options who arguments allowed)
  (for/fold ([found (hasheq)]) ([argument arguments])
    (define named (option argument))
    (unless (and named (memq (car named) allowed))
      (fail "~a expects options among ~a or a C type name, got ~a"
            who
            (string-join (map symbol->string
                              (append (if (memq 'base allowed) '(bin oct dec hex) '())
                                      (if (memq 'base allowed) '() UNITS)
                                      TYPES))
                         ", ")
            (cdr argument)))
    (define old (hash-ref found (car named) #f))
    (when (and old (not (eq? old (cdr named)))) (fail "~a takes one ~a, got ~a and ~a" who (car named) old (cdr named)))
    (hash-set found (car named) (cdr named))))

(define (wide who)
  (note "~a: the value is wider than 64 bits and was cut to the low 64; pass big to keep all of it" who))

;; With no type written, a constant is a u64.
(define (default who value)
  (cond [(exact-integer? value)
         (unless (<= (integer-length value) (if (negative? value) 63 64)) (wide who))
         (make 'u64 value)]
        [else value]))

(define (base-helper who arguments scope)
  (when (null? arguments) (fail "~a expects a value" who))
  (define value (value-of who (car arguments) scope))
  (define chosen (options who (cdr arguments) '(base type unit)))
  (define type (hash-ref chosen 'type #f))
  (define unit (hash-ref chosen 'unit #f))
  (set! shown (list who (hash-ref chosen 'base (string->symbol who)) type))
  (cond [unit (scale who value (* 10 (index-of UNITS unit)) type)]
        [type (cast type value)]
        [else (default who value)]))

;; Multiplies or divides by 1024 per step. A typed integer keeps C's arithmetic; without a type among the
;; options, a division with a remainder gives a double.
(define (scale who value places type)
  (define number (if type (cast type value) (default who value)))
  (define factor (arithmetic-shift 1 (abs places)))
  (cond [(real? number)
         (define scaled (* (double number) (expt 2.0 places)))
         (if (f32? number) (f32 (single scaled)) scaled)]
        [(not (negative? places)) (binary '* number factor)]
        [(or (and type (not (eq? type 'big))) (zero? (remainder (plain number) factor))) (binary '/ number factor)]
        [else (/ (exact->inexact (plain number)) (exact->inexact factor))]))

(define (size-helper who target arguments scope [from #f])
  (when (null? arguments) (fail "~a expects a value" who))
  (define value (value-of who (car arguments) scope))
  (define chosen (options who (cdr arguments) '(unit type)))
  (define given (hash-ref chosen 'unit #f))
  (when (and from given (not (eq? from given))) (fail "~a takes one unit, got ~a and ~a" who from given))
  (define unit (or from given 'byte))
  (define type (hash-ref chosen 'type #f))
  (define result (scale who value (* 10 (- (index-of UNITS unit) (index-of UNITS target))) type))
  (set! shown (list who 'size (and (not (and (eq? type 'big) (flonum? result))) type)))
  result)

(define (call name arguments scope)
  (define symbol (string->symbol name))
  (define target (or (hash-ref scope name #f) (hash-ref globals name #f)))
  (cond [(fn? target)
         (unless (= (length arguments) (length (fn-params target)))
           (fail "~a takes ~a, got ~a"
                 name
                 (if (= (length (fn-params target)) 1) "1 value" (format "~a values" (length (fn-params target))))
                 (length arguments)))
         (define frame (make-hash))
         (for ([param (fn-params target)] [argument arguments])
           (hash-set! frame param (value-of name argument scope)))
         (when (> depth 2000) (fail "~a calls itself more than 2000 deep" name))
         (set! depth (add1 depth))
         (dynamic-wind void (lambda () (evaluate (fn-body target) frame)) (lambda () (set! depth (sub1 depth))))]
        [target (fail "~a is not a function" name)]
        [(hash-has-key? BASES symbol) (base-helper name arguments scope)]
        [(memq symbol UNITS) (size-helper name symbol arguments scope)]
        [(regexp-match #rx"^([a-z]+)_to_([a-z]+)$" name)
         => (lambda (found)
              (define from (string->symbol (cadr found)))
              (define to (string->symbol (caddr found)))
              (unless (and (memq from UNITS) (memq to UNITS) (not (eq? from to))) (fail "~a is not defined" name))
              (size-helper name to arguments scope from))]
        [(string=? name "cast")
         (unless (and (= (length arguments) 2) (eq? (car (car (car arguments))) 'type))
           (fail "cast expects a type and a value: cast(u16, x)"))
         (cast (cadr (car (car arguments))) (value-of name (cadr arguments) scope))]
        [else (fail "~a is not defined" name)]))

;; ---------------------------------------------------------------------------------------------------------
;; The prompt

(define colour? (and (terminal-port? (current-output-port)) (not (equal? (getenv "TERM") "dumb")) (not (getenv "NO_COLOR"))))

;; The result line: the statement's value once, in the base of the helper called last.
(define (result-text value)
  (cond [shown
         (define who (car shown))
         (define type (caddr shown))
         (define converted (cond [(int? value) value] [type (cast type value)] [else (default who value)]))
         (render converted (cadr shown))]
        [(real? value) (float-text (plain value))]
        [else (number->string (plain value))]))

(define (show value)
  (when (number? value)
    (define text (result-text value))
    (if colour?
        (printf "\e[1;~am~a\e[0m\n" (if (real? value) 35 34) text)
        (printf "~a\n" text))))

(define HELP #<<TEXT
cnum computes as C does on x86-64 Linux (GCC, LP64).

  0x1000 * 4          a constant has no type until it meets one; with none, a helper takes it as a u64
  1u  1L  1ull  1.5f  suffixes type a constant as in C
  (u32)x  u32(x)      casts, also (unsigned long)x, (int8_t)x, cast(u16, x)
  hex(x)  bin oct dec show a value in a base; hex(x, u16) converts first; hex(4, gb) reads 4 GB as bytes
  gb(x)   byte kb mb tb   convert a size from bytes; gb(512, mb) names the unit; mb_to_gb(512)
  sizeof(int)  sizeof x
  x = 5; x += 1; x++  variables
  f(a, b) = a * b     functions; c ? a : b chooses
  :ast 1 + 2 * 3      shows the s-expression a line is read as
  quit                leaves, as does Ctrl-D
TEXT
  )

;; Runs one line; returns #f when the line asks to leave.
(define (run line)
  (define text (string-trim line))
  (cond [(member text '("quit" "exit")) #f]
        [(string=? text "help") (displayln HELP) #t]
        [(regexp-match #rx"^:ast +(.*)$" text)
         => (lambda (found)
              (for ([tree (parse (cadr found))]) (writeln (readable tree)))
              #t)]
        [else
         (define last
           (for/last ([tree (parse text)])
             (set! shown #f)
             (set! depth 0)
             (evaluate tree (make-hash))))
         (unless (void? last) (when last (show last)))
         #t]))

;; A tree as plain data: constants as their text, and arguments without their source text.
(define (readable tree)
  (cond [(and (pair? tree) (eq? (car tree) 'const))
         (define value (cadr tree))
         (if (exact-integer? value) value (list (type-name value) (plain value)))]
        [(and (pair? tree) (eq? (car tree) 'call))
         (define arguments (map (lambda (argument) (readable (car argument))) (caddr tree)))
         (list* 'call (string->symbol (cadr tree)) arguments)]
        [(pair? tree) (map readable tree)]
        [(string? tree) (string->symbol tree)]
        [else tree]))

(define (type-name value)
  (cond [(int? value) (int-type value)]
        [(f32? value) 'f32]
        [else 'f64]))

;; Runs a line and reports an error on standard error; returns #f to leave and 'failed after an error.
(define (attempt line)
  (with-handlers ([exn:break? (lambda (_) (newline) #t)]
                  [exn:fail? (lambda (raised) (eprintf "error: ~a\n" (exn-message raised)) 'failed)])
    (run line)))

(define (load-startup)
  (define home (or (getenv "XDG_CONFIG_HOME") (build-path (find-system-path 'home-dir) ".config")))
  (define path (build-path home "cnum" "init"))
  (when (file-exists? path)
    (for ([line (call-with-input-file path (lambda (port) (for/list ([line (in-lines port)]) line)))]
          [index (in-naturals 1)])
      (with-handlers ([exn:fail? (lambda (raised) (eprintf "~a:~a: ~a\n" path index (exn-message raised)))])
        (for ([tree (parse line)]) (evaluate tree (make-hash)))))))

(define (prompt-loop)
  (define interactive? (terminal-port? (current-input-port)))
  (define readline
    (and interactive?
         (with-handlers ([(lambda (_) #t) (lambda (_) #f)]) (dynamic-require 'readline/readline 'readline))))
  (define remember (and readline (dynamic-require 'readline/readline 'add-history)))
  (let loop ()
    (define line
      (with-handlers ([exn:break? (lambda (_) (newline) "")])
        (cond [readline (readline "cnum> ")]
              [else (when interactive? (display "cnum> ") (flush-output))
                    (read-line)])))
    (cond [(eof-object? line) (when interactive? (newline))]
          [else
           (when (and remember (not (string=? (string-trim line) ""))) (remember line))
           (when (attempt line) (flush-output) (loop))])))

(module+ main
  (define lines (vector->list (current-command-line-arguments)))
  (load-startup)
  (cond [(null? lines) (prompt-loop)]
        [else (exit (if (for/fold ([ok? #t]) ([line lines]) (and (not (eq? (attempt line) 'failed)) ok?)) 0 1))]))
