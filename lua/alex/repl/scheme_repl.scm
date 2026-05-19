#!r6rs

(import (rnrs base)
        (rnrs io ports)
        (rnrs io simple))

(define (u64->bytevector n endian)
  (let ([bv (make-bytevector 8)])
    (bytevector-u64-set! bv 0 n endian)
    bv))

(define transcoder (make-transcoder (utf-8-codec)))

(define (send-message bv stdout)
  (let ([bvlen (bytevector-length bv)])
    (put-bytevector stdout (u64->bytevector bvlen (endianness big)))
    (put-bytevector stdout bv))
    (flush-output-port stdout))

(define (recv-message stdin stdout)
  (let* ([bvlen (get-bytevector-n stdin 8)]
         [payload '()])
    (if (not (eq? (bytevector-length bvlen) 8))
        (begin
              (send-message (string->bytevector "error: unexpected EOF" transcoder) stdout)
                            nil)
        (begin
              (set! bvlen (bytevector-u64-ref bvlen 0 (endianness big)))
              (set! payload (get-bytevector-n stdin bvlen))
              (if (not (eq? (bytevector-length payload) bvlen))
                  (begin
                    (send-message (string->bytevector "error: unexpected EOF" transcoder) stdout)
                                  nil)
                  payload)))))

(define (expr->string e)
  (call-with-string-output-port
   (lambda (out) (write e out))))

(define stdin (standard-input-port))
(define stdout (standard-output-port))

(define (loop)
  (define msg (recv-message stdin stdout))
  (define code '())
  (when (not msg)
    (exit 0))
  (set! msg (bytevector->string msg transcoder))
  (set! code (read (open-input-string msg)))
  (set! msg
    (expr->string (guard (condition (else condition))
            (eval code (interaction-environment)))))
  (send-message (string->bytevector msg transcoder) stdout)
  (loop))

(loop)
